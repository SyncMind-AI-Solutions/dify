#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${REGISTRY:-crpi-2e30x3ttfmqmx83q.cn-chengdu.personal.cr.aliyuncs.com}"
NAMESPACE="${NAMESPACE:-dify-vision}"
PLATFORM="${PLATFORM:-linux/amd64}"
COMPOSE_FILE="${COMPOSE_FILE:-docker/docker-compose.yaml}"

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

  printf '%s/%s/%s:%s' "$REGISTRY" "$NAMESPACE" "$name" "$tag"
}

cd "$root_dir"

images="$($root_dir/syncmind/scripts/list-compose-images.sh)"

if [[ -z "$images" ]]; then
  echo "No images found in $COMPOSE_FILE" >&2
  exit 1
fi

echo "Mirroring compose images to $REGISTRY/$NAMESPACE (platform: $PLATFORM)"

while IFS= read -r src; do
  if [[ -z "$src" ]]; then
    continue
  fi

  if is_excluded "$src"; then
    echo "Skip (excluded): $src"
    continue
  fi

  dst="$(mirror_ref "$src")"

  echo "Pull:  $src"
  docker pull --platform "$PLATFORM" "$src"

  echo "Tag:   $src -> $dst"
  docker tag "$src" "$dst"

  echo "Push:  $dst"
  docker push "$dst"

done <<< "$images"

echo "Done."
