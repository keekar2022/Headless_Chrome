#!/usr/bin/env bash
# Concept: Mukesh Kesharwani
# Contact: mukesh.kesharwani@adobe.com
#
# Start Chromium in desktop (noVNC) or headless (CDP) mode.

set -e

CHROME_MODE="${CHROME_MODE:-desktop}"
CHROME_BIN="${CHROME_BIN:-/usr/lib/chromium/chromium}"
CHROME_PROFILE="${CHROME_PROFILE:-/tmp/chrome-profile}"
START_URL="${START_URL:-about:blank}"
SCREEN="${SCREEN:-1920x1080x24}"
NOVNC_LISTEN="${NOVNC_LISTEN:-0.0.0.0}"

PIDS=()

cleanup() {
  local pid
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}

trap cleanup EXIT INT TERM

track() {
  PIDS+=("$1")
}

parse_screen_size() {
  SCREEN_WIDTH="${SCREEN%%x*}"
  local rest="${SCREEN#*x}"
  SCREEN_HEIGHT="${rest%%x*}"
}

maximize_chromium_window() {
  command -v wmctrl >/dev/null 2>&1 || return 0
  local attempt id
  for ((attempt = 0; attempt < 30; attempt++)); do
    id="$(wmctrl -l 2>/dev/null | grep -iE 'chromium|chrome' | awk '{print $1}' | head -1)"
    if [ -n "$id" ]; then
      wmctrl -i -r "$id" -b add,maximized_vert,maximized_horz 2>/dev/null && return 0
      wmctrl -i -r "$id" -e "0,0,0,${SCREEN_WIDTH},${SCREEN_HEIGHT}" 2>/dev/null && return 0
    fi
    sleep 0.5
  done
  return 0
}

chromium_base() {
  parse_screen_size
  "${CHROME_BIN}" \
    --no-sandbox \
    --no-zygote \
    --disable-features=AsyncDns \
    --no-first-run \
    --disable-infobars \
    --user-data-dir="${CHROME_PROFILE}" \
    --window-size="${SCREEN_WIDTH},${SCREEN_HEIGHT}" \
    --window-position=0,0 \
    "$@"
}

# Block until an essential supervised process exits (not short-lived helpers).
wait_for_supervised_processes() {
  local pid
  while true; do
    for pid in "${PIDS[@]}"; do
      if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid" 2>/dev/null || true
        echo "Essential process $pid exited; stopping container." >&2
        return 1
      fi
    done
    sleep 5
  done
}

start_desktop() {
  local display="${DISPLAY_NUM:-99}"
  export DISPLAY=":${display}"
  local novnc_port="${NOVNC_PORT:-6080}"
  local vnc_port="${VNC_PORT:-5900}"

  parse_screen_size

  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-chrome}"
  mkdir -p "${XDG_RUNTIME_DIR}" /tmp/.X11-unix "${HOME}/.config/openbox"
  chmod 700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true

  # Prefer direct LAN DNS when resolv.conf is writable (TrueNAS: set DNS in app config).
  if [ -n "${DNS_PRIMARY:-}" ] && [ -w /etc/resolv.conf ] 2>/dev/null; then
    {
      echo "nameserver ${DNS_PRIMARY}"
      [ -n "${DNS_SECONDARY:-}" ] && echo "nameserver ${DNS_SECONDARY}"
      echo "options ndots:2 attempts:2 timeout:2"
    } >/etc/resolv.conf 2>/dev/null || true
  fi

  Xvfb ":${display}" -screen 0 "${SCREEN}" -ac +extension GLX +render -noreset &
  track $!
  sleep 1

  openbox &
  track $!
  sleep 0.5

  chromium_base "${START_URL}" &
  track $!

  # One-shot helper — must not trigger container exit when it finishes.
  ( maximize_chromium_window ) &

  local vnc_args=(
    -display ":${display}"
    -forever
    -shared
    -rfbport "${vnc_port}"
    -listen 0.0.0.0
    -noipv6
    -xkb
    -noxrecord
    -noxfixes
    -noxdamage
  )
  if [ -n "${VNC_PASSWORD:-}" ]; then
    x11vnc -storepasswd "${VNC_PASSWORD}" /tmp/vncpass >/dev/null
    vnc_args+=(-rfbauth /tmp/vncpass)
  else
    vnc_args+=(-nopw)
  fi
  x11vnc "${vnc_args[@]}" &
  track $!

  websockify --web /usr/share/novnc/ "${NOVNC_LISTEN}:${novnc_port}" "127.0.0.1:${vnc_port}" &
  track $!

  echo "Desktop Chrome is ready (${SCREEN_WIDTH}x${SCREEN_HEIGHT})."
  echo "noVNC listening on ${NOVNC_LISTEN}:${novnc_port}"
  echo "Open: http://<server-host-or-ip>:${novnc_port}/"
  echo "Recommended DNS at deploy time: ${DNS_PRIMARY:-192.168.1.200} (see deploy/defaults.env)"
  echo "Isolated profile: ${CHROME_PROFILE} (container-only; no host Chrome settings used)."
  if [ -z "${VNC_PASSWORD:-}" ]; then
    echo "Warning: VNC_PASSWORD is not set. Set it before exposing this port on a public server." >&2
  fi

  wait_for_supervised_processes
}

start_headless() {
  local chrome_port="${CHROME_PORT:-9222}"
  local internal_port="${CHROME_INTERNAL_PORT:-9223}"

  chromium_base \
    --headless=new \
    --disable-extensions \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port="${internal_port}" \
    "$@" &
  track $!

  for _ in $(seq 1 60); do
    if curl -sf "http://127.0.0.1:${internal_port}/json/version" >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done

  if ! curl -sf "http://127.0.0.1:${internal_port}/json/version" >/dev/null 2>&1; then
    echo "Timed out waiting for Chromium CDP on port ${internal_port}" >&2
    exit 1
  fi

  socat TCP-LISTEN:"${chrome_port}",bind=0.0.0.0,fork,reuseaddr "TCP:127.0.0.1:${internal_port}" &
  track $!

  echo "Headless CDP is ready at http://<server-host-or-ip>:${chrome_port}/json/version"

  wait_for_supervised_processes
}

case "${CHROME_MODE}" in
  desktop | gui | visual)
    start_desktop
    ;;
  headless | cdp)
    start_headless "$@"
    ;;
  *)
    echo "Unknown CHROME_MODE=${CHROME_MODE}. Use desktop or headless." >&2
    exit 1
    ;;
esac
