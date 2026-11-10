#!/usr/bin/env bash
set -eu

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image_tag="${IMAGE_TAG:-latest}"
nexus_docker_proxy="${NEXUS_DOCKER_PROXY:?NEXUS_DOCKER_PROXY must be set}"
: "${NEXUS_USERNAME:?NEXUS_USERNAME must be set}"
: "${NEXUS_PASSWORD:?NEXUS_PASSWORD must be set}"

e2e_project_prefix="e2e-${BUILD_NUMBER:-0}-$$"
backend_project="${e2e_project_prefix}-backend"
frontend_project="${e2e_project_prefix}-frontend"
export IMAGE_TAG="$image_tag"
export KAFKA_HOST_PORT=0
export DISCOVERY_HOST_PORT=0
export GATEWAY_HOST_PORT=0
export FRONTEND_HOST_PORT=0

cleanup_e2e_environment() {
    test_status=$?
    trap - EXIT

    cd "$repo_root/frontend"
    if ! docker compose --project-name "$frontend_project" down --volumes --remove-orphans; then
        echo "Failed to stop the isolated E2E frontend environment" >&2
        if [ "$test_status" -eq 0 ]; then
            test_status=1
        fi
    fi

    cd "$repo_root/backend"
    if ! docker compose --project-name "$backend_project" down --volumes --remove-orphans; then
        echo "Failed to stop the isolated E2E backend environment" >&2
        if [ "$test_status" -eq 0 ]; then
            test_status=1
        fi
    fi

    if ! docker logout "$nexus_docker_proxy" >/dev/null 2>&1; then
        echo "Failed to log out from Nexus Docker proxy" >&2
        if [ "$test_status" -eq 0 ]; then
            test_status=1
        fi
    fi

    exit "$test_status"
}

trap cleanup_e2e_environment EXIT

printf '%s' "$NEXUS_PASSWORD" | docker login "$nexus_docker_proxy" \
    --username "$NEXUS_USERNAME" --password-stdin

cd "$repo_root/frontend"
docker compose --project-name "$frontend_project" up --no-build -d --wait --wait-timeout 420

frontend_address=$(docker compose --project-name "$frontend_project" port frontend 443)
frontend_port="${frontend_address##*:}"
export APP_CORS_ALLOWED_ORIGINS="https://localhost:${frontend_port}"

cd "$repo_root/backend"
docker compose --project-name "$backend_project" up --no-build -d --wait --wait-timeout 420

gateway_address=$(docker compose --project-name "$backend_project" port api-gateway 8888)
gateway_port="${gateway_address##*:}"

attempts=0
status=000
while [ "$attempts" -lt 60 ]; do
    status=$(curl --silent --insecure --max-time 1 \
        --output /dev/null --write-out '%{http_code}' \
        --request POST --header 'Content-Type: application/json' \
        --data '{}' \
        "https://docker:${gateway_port}/api/auth/register" 2>/dev/null || true)
    if [ "$status" = 400 ]; then
        break
    fi

    attempts=$((attempts + 1))
    if [ "$((attempts % 10))" -eq 0 ]; then
        echo "Waiting for auth route through API Gateway (attempt $attempts/60, HTTP $status)"
    fi
    sleep 1
done

if [ "$status" != 400 ]; then
    echo "Auth route did not become ready through the API Gateway within 2 minutes (expected HTTP 400, got $status)"
    exit 1
fi

cd "$repo_root/frontend"

docker_host_ip=$(getent hosts docker | awk 'NR == 1 { print $1 }')
if [ -z "$docker_host_ip" ]; then
    echo "Could not resolve Docker host 'docker' for Playwright"
    exit 1
fi

e2e_username="e2e$(date +%s%3N)"
e2e_product_name="E2E Product $e2e_username"

E2E_USERNAME="$e2e_username" \
E2E_PRODUCT_NAME="$e2e_product_name" \
E2E_DOCKER_HOST_IP="$docker_host_ip" \
E2E_GATEWAY_PORT="$gateway_port" \
E2E_BASE_URL="https://localhost:${frontend_port}" \
npm run e2e
