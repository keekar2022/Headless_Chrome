#!/usr/bin/env bash
# Concept: Mukesh Kesharwani
# Contact: mukesh.kesharwani@adobe.com
# Check signed updates, restarts, privilege dropping, and both browser modes.
# Default-enabled update checks require access to official Debian repositories.
set -euo pipefail

image="${1:-keekar/headless-chrome:latest}"
container=""
cleanup() {
  if [ -n "$container" ]; then
    docker rm -f "$container" >/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

docker run --rm --entrypoint /bin/sh "$image" -ec \
  'chromium --version; test -s /usr/share/headless-chrome/packages.txt; test "$(id -u chrome)" -ne 0'

check_browser() {
  local address response
  address="$(docker port "$container" "$port/tcp")"
  response="$(curl --fail --silent --max-time 5 \
    --retry 120 --retry-all-errors --retry-delay 5 --retry-max-time 660 \
    "http://$address$endpoint")"
  if [ "$mode" = desktop ]; then
    grep -qi '<html' <<<"$response"
  else
    grep -q 'webSocketDebuggerUrl' <<<"$response"
  fi
  test "$(docker inspect --format '{{.State.Running}}' "$container")" = true
  docker exec "$container" /bin/sh -ec '
    found=0
    for path in /proc/[0-9]*/comm; do
      # Short-lived helpers can disappear between glob expansion and reading.
      read -r name 2>/dev/null < "$path" || continue
      if [ "$name" = chromium ]; then
        status="$(cat "${path%/comm}/status" 2>/dev/null)" || continue
        printf "%s\n" "$status" | grep -q "^Uid:[[:space:]]*$(id -u chrome)[[:space:]]"
        printf "%s\n" "$status" | grep -q "^NoNewPrivs:[[:space:]]*1"
        found=1
      fi
    done
    test "$found" = 1
  '
}

for configuration in desktop:1 headless:1 headless:0; do
  mode="${configuration%:*}"
  auto_update="${configuration#*:}"
  run_user=root
  if [ "$auto_update" = 0 ]; then
    run_user=chrome
  fi
  if [ "$mode" = desktop ]; then
    port=6080
    endpoint=/
  else
    port=9222
    endpoint=/json/version
  fi
  container="$(docker run -d --shm-size=2g --user "$run_user" \
    -e "CHROME_MODE=$mode" -e "CHROME_AUTO_UPDATE=$auto_update" \
    -p "127.0.0.1::$port" "$image")"
  check_browser
  docker restart --time 30 "$container" >/dev/null
  check_browser
  if [ "$auto_update" = 1 ]; then
    test "$(docker logs "$container" 2>&1 | grep -c 'Signed package update completed; launching the non-root browser.')" = 2
  fi
  cleanup
  container=""
  printf '%s startup and restart passed (CHROME_AUTO_UPDATE=%s).\n' "$mode" "$auto_update"
done

expect_failure() {
  local message="$1" output
  shift
  if output="$(docker run --rm "$@" "$image" 2>&1)"; then
    echo 'Expected bootstrap to refuse browser startup.' >&2
    return 1
  fi
  grep -q "$message" <<<"$output"
}
expect_failure 'must be 0 or 1' --network none -e CHROME_AUTO_UPDATE=invalid
expect_failure 'require a root bootstrap' --network none --user chrome
expect_failure 'browser startup refused' --network none \
  -e https_proxy=http://127.0.0.1:9 -e http_proxy=http://127.0.0.1:9
printf '%s\n' 'Invalid configuration, missing privileges, and unreachable repository checks passed.'

# An unsigned local repository must be rejected before any browser is launched.
if output="$(docker run --rm -i --network none --entrypoint /bin/bash "$image" -se 2>&1 <<'UNSIGNED_REPOSITORY'
rm -f /etc/apt/sources.list.d/*
mkdir -p /tmp/unsigned-repository/dists/test
printf 'Origin: Unsigned-Test\nSuite: test\nCodename: test\n' > /tmp/unsigned-repository/dists/test/Release
printf 'deb [trusted=no] file:/tmp/unsigned-repository test main\n' > /etc/apt/sources.list.d/test.list
exec /usr/local/bin/bootstrap.sh
UNSIGNED_REPOSITORY
)"; then
  echo 'Expected an unsigned repository to be rejected.' >&2
  exit 1
fi
grep -q 'not signed' <<<"$output"
grep -q 'browser startup refused' <<<"$output"
printf '%s\n' 'Unsigned repository rejection passed.'

# Inject failure-only tools in disposable containers, not in the shipped image.
for failure in timeout candidate; do
  if output="$(docker run --rm -i --network none --entrypoint /bin/bash "$image" -se -- "$failure" 2>&1 <<'FAILURE_FIXTURE'
mkdir -p /tmp/bootstrap-test-tools
if [ "$1" = timeout ]; then
  printf '#!/bin/sh\nexit 124\n' > /tmp/bootstrap-test-tools/timeout
else
  printf '#!/bin/sh\nexit 0\n' > /tmp/bootstrap-test-tools/apt-get
  printf '#!/bin/sh\necho "Candidate: 0"\n' > /tmp/bootstrap-test-tools/apt-cache
fi
chmod +x /tmp/bootstrap-test-tools/*
export PATH="/tmp/bootstrap-test-tools:$PATH"
exec /usr/local/bin/bootstrap.sh
FAILURE_FIXTURE
)"; then
    echo 'Expected injected bootstrap failure to refuse startup.' >&2
    exit 1
  fi
  grep -q 'browser startup refused' <<<"$output"
  if [ "$failure" = candidate ]; then
    grep -q 'does not match' <<<"$output"
  fi
done
printf '%s\n' 'Timeout and candidate-version mismatch rejection passed.'
