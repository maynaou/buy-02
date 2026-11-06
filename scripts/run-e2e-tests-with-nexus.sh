#!/bin/bash
set -euo pipefail
set +x

registry="${NEXUS_DOCKER_PROXY:?NEXUS_DOCKER_PROXY must be set}"

printf '%s' "$NEXUS_PASSWORD" | docker login "$registry" \
    --username "$NEXUS_USERNAME" --password-stdin
trap 'docker logout "$registry" >/dev/null 2>&1 || true' EXIT

bash ./scripts/e2e-tests.sh
