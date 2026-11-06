#!/bin/bash
set -euo pipefail

services=(
    api-gateway
    discovery-service
    media-service
    product-service
    security-service
    user-service
    order-service
)

for service in "${services[@]}"; do
    echo "Packaging backend/$service"
    (
        cd "backend/$service"
        ./mvnw -B clean package -DskipTests
    )
done
