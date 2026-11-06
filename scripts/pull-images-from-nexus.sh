#!/bin/bash
set -euo pipefail
set +x

if [[ -z "${IMAGE_TAG:-}" || -z "${NEXUS_DOCKER_TAG:-}" ]]; then
    echo "IMAGE_TAG et NEXUS_DOCKER_TAG doivent être définis" >&2
    exit 1
fi

if [[ -z "${NEXUS_USERNAME:-}" || -z "${NEXUS_PASSWORD:-}" ]]; then
    echo "Les identifiants Nexus doivent être définis" >&2
    exit 1
fi

registry=nexus:8082
case "${1:-}" in
    backend)
        images=(
            backend-api-gateway
            backend-discovery-service
            backend-media-service
            backend-product-service
            backend-security-service
            backend-user-service
            backend-order-service
        )
        ;;
    frontend)
        images=(frontend-app)
        ;;
    *)
        echo "Usage: $0 backend|frontend" >&2
        exit 1
        ;;
esac

printf '%s' "$NEXUS_PASSWORD" | docker login "$registry" \
    --username "$NEXUS_USERNAME" --password-stdin
trap 'docker logout "$registry" >/dev/null 2>&1 || true' EXIT

for image in "${images[@]}"; do
    remote_image="$registry/buy-02/$image:$NEXUS_DOCKER_TAG"
    local_image="$image:$IMAGE_TAG"
    docker pull "$remote_image"
    docker tag "$remote_image" "$local_image"
done
