#!/usr/bin/env bash
set -euo pipefail

compose_file="${COMPOSE_FILE:-docker/docker-compose.yaml}"

if [[ ! -f "$compose_file" ]]; then
  echo "Compose file not found: $compose_file" >&2
  exit 1
fi

awk '
  /^[[:space:]]*image:[[:space:]]*/ {
    line=$0
    sub(/^[[:space:]]*image:[[:space:]]*/, "", line)
    sub(/[[:space:]]+#.*/, "", line)
    gsub(/\"/, "", line)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (length(line) > 0) print line
  }
' "$compose_file" | sort -u
