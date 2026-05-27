#!/usr/bin/env bash
# Shared helpers sourced by every smoke-<chart>.sh.

# Wait until a TCP port on localhost is accepting connections.
# Uses bash's built-in /dev/tcp — works in CI runners without nc.
wait_for_port() {
  local port="$1" tries="${2:-60}"
  for i in $(seq 1 "$tries"); do
    (exec 3<>/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1 && {
      exec 3>&- 3<&-
      return 0
    }
    sleep 1
  done
  echo "port $port never opened after $tries seconds" >&2
  return 1
}

# Wait until a URL returns one of the accepted HTTP codes.
wait_for_http() {
  local url="$1" accept_pattern="${2:-2..|3..}" tries="${3:-60}"
  for i in $(seq 1 "$tries"); do
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' "$url" || echo 000)"
    if [[ "$code" =~ ^($accept_pattern)$ ]]; then
      echo "$url -> HTTP $code (ready)"
      return 0
    fi
    sleep 1
  done
  echo "$url never returned an accepted status (last: $code)" >&2
  return 1
}
