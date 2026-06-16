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

chromium_base() {
  "${CHROME_BIN}" \
    --no-sandbox \
    --disable-dev-shm-usage \
    --no-first-run \
    --disable-infobars \
    --user-data-dir="${CHROME_PROFILE}" \
    --window-size=1920,1080 \
    "$@"
}

start_desktop() {
  local display="${DISPLAY_NUM:-99}"
  export DISPLAY=":${display}"
  local novnc_port="${NOVNC_PORT:-6080}"
  local vnc_port="${VNC_PORT:-5900}"

  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-chrome}"
  mkdir -p "${XDG_RUNTIME_DIR}" /tmp/.X11-unix
  chmod 700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true

  Xvfb ":${display}" -screen 0 "${SCREEN}" -ac +extension GLX +render -noreset &
  track $!
  sleep 1

  if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax --exit-with-session)"
  fi

  openbox &
  track $!
  sleep 0.5

  chromium_base --disable-gpu --start-maximized "${START_URL}" &
  track $!

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

  # Bind 0.0.0.0 so remote clients can reach noVNC when port 6080 is published.
  websockify --web /usr/share/novnc/ "${NOVNC_LISTEN}:${novnc_port}" "127.0.0.1:${vnc_port}" &
  track $!

  echo "Desktop Chrome is ready."
  echo "noVNC listening on ${NOVNC_LISTEN}:${novnc_port}"
  echo "Open: http://<server-host-or-ip>:${novnc_port}/"
  echo "On the same machine only: http://127.0.0.1:${novnc_port}/"
  echo "Isolated profile: ${CHROME_PROFILE} (container-only; no host Chrome settings used)."
  if [ -z "${VNC_PASSWORD:-}" ]; then
    echo "Warning: VNC_PASSWORD is not set. Set it before exposing this port on a public server." >&2
  fi
}

start_headless() {
  local chrome_port="${CHROME_PORT:-9222}"
  local internal_port="${CHROME_INTERNAL_PORT:-9223}"

  chromium_base \
    --headless=new \
    --disable-gpu \
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

wait -n
exit $?
