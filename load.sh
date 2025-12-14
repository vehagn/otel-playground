#!/usr/bin/env bash
set -euo pipefail

echo "Collecting images from all namespaces..."
IMAGES=$(
  kubectl get pods --all-namespaces -o json \
  | jq -r '
      .items[]
      | [
          (.spec.containers // [] | .[]?.image),
          (.spec.initContainers // [] | .[]?.image)
        ] | .[]
    ' \
  | grep -v '^$' \
  | sort -u
)

readarray -t NODES < <(kind get nodes)

has_image_in_node() {
  local node="$1" image="$2"
  docker exec "$node" ctr -n k8s.io images ls -q | grep -Fxq "$image"
}

has_image_in_cluster() {
  local image="$1"
  for node in "${NODES[@]}"; do
    if ! has_image_in_node "$node" "$image"; then
      return 1
    fi
  done
  return 0
}

echo "Loading missing container images to all nodes..."
while IFS= read -r image; do
  if has_image_in_cluster "$image"; then
    continue
  fi
  docker pull "$image" --quiet
  kind load docker-image "$image"
done <<< "$IMAGES"

echo "Done."