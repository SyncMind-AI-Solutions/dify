#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${REGISTRY:-crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com}"
NAMESPACE="${NAMESPACE:-dify-vision}"
PLATFORM="${PLATFORM:-linux/amd64}"
COMPOSE_FILE="${COMPOSE_FILE:-docker/docker-compose.yaml}"
METHOD="${METHOD:-}"

usage() {
  cat <<'USAGE'
Usage: mirror-compose-images.sh [--image <ref> ...] [--images-file <path>] [--method skopeo|docker]

Mirrors upstream images referenced by docker compose into Alibaba ACR.

Selection:
  - If --image/--images-file are provided, only those images are mirrored.
  - Otherwise, images are read from docker-compose (via list-compose-images.sh).
  - Alternatively, set IMAGES as a newline-separated list of images.

Env:
  REGISTRY   ACR registry host (default set)
  NAMESPACE  ACR namespace (default set)
  PLATFORM   linux/amd64 by default
  METHOD     skopeo (preferred) or docker; if empty, auto-pick skopeo when available
  IMAGES     newline-separated explicit image list (optional)

Notes:
  - Dify API/Web upstream images are excluded by default (we build our own).
  - Alibaba ACR repositories under a namespace cannot contain '/'; this script flattens to the last path segment.
USAGE
}

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Exclude the upstream Dify API/Web images, since we build and push our own in the workflow.
EXCLUDE_PREFIXES=(
  "langgenius/dify-api"
  "langgenius/dify-web"
)

is_excluded() {
  local image_ref="$1"
  local prefix
  for prefix in "${EXCLUDE_PREFIXES[@]}"; do
    if [[ "$image_ref" == "$prefix"* ]]; then
      return 0
    fi
  done
  return 1
}

# Map an upstream image reference to an ACR reference under the namespace.
# Example:
#   ubuntu/squid:latest -> <REGISTRY>/<NAMESPACE>/ubuntu/squid:latest
#   redis:6-alpine      -> <REGISTRY>/<NAMESPACE>/redis:6-alpine
mirror_ref() {
  local src="$1"

  # drop digest if present
  local ref_no_digest="${src%%@*}"

  local name="$ref_no_digest"
  local tag="latest"

  # If the last path segment contains a colon, treat it as a tag separator.
  if [[ "${ref_no_digest##*/}" == *:* ]]; then
    tag="${ref_no_digest##*:}"
    name="${ref_no_digest%:*}"
  fi

  # Alibaba ACR repositories under a namespace cannot contain additional slashes.
  # Flatten upstream names like "certbot/certbot" to "certbot".
  local repo
  repo="${name##*/}"

  printf '%s/%s/%s:%s' "$REGISTRY" "$NAMESPACE" "$repo" "$tag"
}

cd "$root_dir"

declare -a selected_images=()
images_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      shift
      [[ $# -gt 0 ]] || { echo "--image requires a value" >&2; exit 2; }
      selected_images+=("$1")
      ;;
    --images-file)
      shift
      [[ $# -gt 0 ]] || { echo "--images-file requires a value" >&2; exit 2; }
      images_file="$1"
      ;;
    --method)
      shift
      [[ $# -gt 0 ]] || { echo "--method requires a value" >&2; exit 2; }
      METHOD="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

has_skopeo=false
if command -v skopeo >/dev/null 2>&1; then
  has_skopeo=true
fi

if [[ -z "$METHOD" ]]; then
  if [[ "$has_skopeo" == "true" ]]; then
    METHOD="skopeo"
  else
    METHOD="docker"
  fi
fi

if [[ "$METHOD" != "skopeo" && "$METHOD" != "docker" ]]; then
  echo "Invalid METHOD: $METHOD (expected skopeo|docker)" >&2
  exit 2
fi

image_stream=""
if [[ -n "${IMAGES:-}" ]]; then
  image_stream="$IMAGES"
elif [[ ${#selected_images[@]} -gt 0 ]]; then
  image_stream="$(printf '%s\n' "${selected_images[@]}")"
elif [[ -n "$images_file" ]]; then
  if [[ ! -f "$images_file" ]]; then
    echo "Images file not found: $images_file" >&2
    exit 2
  fi
  image_stream="$(cat "$images_file")"
else
  image_stream="$($root_dir/syncmind/scripts/list-compose-images.sh)"
fi

if [[ -z "${image_stream//[[:space:]]/}" ]]; then
  echo "No images selected." >&2
  exit 1
fi

echo "Mirroring images to $REGISTRY/$NAMESPACE (platform: $PLATFORM, method: $METHOD)"

copy_with_skopeo() {
  local src="$1"
  local dst="$2"
  local arch="${PLATFORM##*/}"

  # Stream copy without unpacking into the local docker daemon.
  skopeo copy \
    --override-os linux \
    --override-arch "$arch" \
    docker://"$src" \
    docker://"$dst"
}

copy_with_docker() {
  local src="$1"
  local dst="$2"

  docker pull --platform "$PLATFORM" "$src"
  docker tag "$src" "$dst"
  docker push "$dst"

  # Best-effort cleanup to reduce disk usage.
  docker image rm -f "$src" "$dst" >/dev/null 2>&1 || true
}

while IFS= read -r src; do
  src="${src//$'\r'/}"
  if [[ -z "$src" ]]; then
    continue
  fi

  if is_excluded "$src"; then
    echo "Skip (excluded): $src"
    continue
  fi

  dst="$(mirror_ref "$src")"

  echo "Copy:  $src -> $dst"
  if [[ "$METHOD" == "skopeo" ]]; then
    if [[ "$has_skopeo" != "true" ]]; then
      echo "skopeo not found; install it or set METHOD=docker" >&2
      exit 1
    fi
    copy_with_skopeo "$src" "$dst"
  else
    copy_with_docker "$src" "$dst"
  fi

done <<< "$image_stream"

echo "Done."
