#!/bin/bash
set -euo pipefail
set +x

registry=nexus:8082
images=(
    backend-api-gateway
    backend-discovery-service
    backend-media-service
    backend-product-service
    backend-security-service
    backend-user-service
    backend-order-service
    frontend-app
)

printf '%s' "$NEXUS_PASSWORD" | docker login "$registry" \
    --username "$NEXUS_USERNAME" --password-stdin
trap 'docker logout "$registry" >/dev/null 2>&1 || true' EXIT

for image in "${images[@]}"; do
    source_image="$image:$IMAGE_TAG"
    target_image="$registry/buy-02/$image:$NEXUS_DOCKER_TAG"
    docker tag "$source_image" "$target_image"
    docker push "$target_image"
done
