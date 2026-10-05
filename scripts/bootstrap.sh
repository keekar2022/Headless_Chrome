#!/usr/bin/env bash
# Concept: Mukesh Kesharwani
# Contact: mukesh.kesharwani@adobe.com
# Update signed packages before dropping privileges and starting the browser.
set -euo pipefail

log() {
  # Callers supply constant messages, not environment values or sensitive data.
  printf '{"service.name":"headless-chrome","service.version":"bootstrap-v1","deployment.environment":"container","severity_text":"%s","body":"%s"}\n' "$1" "$2"
}

case "${CHROME_AUTO_UPDATE:-1}" in
  0 | 1) ;;
  *)
    log ERROR 'CHROME_AUTO_UPDATE must be 0 or 1.' >&2
    exit 1
    ;;
esac

if [ "${CHROME_AUTO_UPDATE:-1}" = 1 ]; then
  if [ "$(id -u)" -ne 0 ]; then
    log ERROR 'Automatic updates require a root bootstrap; use CHROME_AUTO_UPDATE=0 for an explicitly non-root deployment.' >&2
    exit 1
  fi
  log INFO 'Checking signed Debian browser packages before startup.'
  update_pid=""
  stop_update() {
    if [ -n "$update_pid" ]; then
      kill -TERM "$update_pid" 2>/dev/null || true
      wait "$update_pid" 2>/dev/null || true
    fi
    exit "$1"
  }
  trap 'stop_update 143' TERM
  trap 'stop_update 130' INT
  timeout --signal=TERM --kill-after=30s 600 /usr/local/bin/update-browser.sh &
  update_pid=$!
  if ! wait "$update_pid"; then
    log ERROR 'Signed package update failed or timed out; browser startup refused.' >&2
    exit 1
  fi
  update_pid=""
  trap - TERM INT
  log INFO 'Signed package update completed; launching the non-root browser.'
else
  log WARN 'Automatic package updates explicitly disabled; using installed packages.'
fi

if [ "$(id -u)" -eq 0 ]; then
  export HOME=/home/chrome USER=chrome LOGNAME=chrome
  exec setpriv --reuid=chrome --regid=chrome --init-groups \
    --no-new-privs --inh-caps=-all --ambient-caps=-all --bounding-set=-all \
    /usr/local/bin/entrypoint.sh "$@"
fi
exec setpriv --no-new-privs --inh-caps=-all --ambient-caps=-all \
  /usr/local/bin/entrypoint.sh "$@"
