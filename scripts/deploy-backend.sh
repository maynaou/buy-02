#!/bin/bash
set -e

echo "===== Déploiement Backend ====="

if [ -z "$IMAGE_TAG" ]; then
    echo "❌ IMAGE_TAG n'est pas défini"
    exit 1
fi
if [ -z "${NEXUS_DOCKER_TAG:-}" ]; then
    echo "❌ NEXUS_DOCKER_TAG n'est pas défini"
    exit 1
fi

echo "📦 Version à déployer : $IMAGE_TAG"

cd backend

IMAGE_TAG="$IMAGE_TAG" bash ../scripts/pull-images-from-nexus.sh backend

# Démarre et ATTEND que tous les containers soient healthy.
# Si un seul est unhealthy → la commande échoue → Jenkins lance le rollback.
IMAGE_TAG="$IMAGE_TAG" docker compose up -d --no-build --wait --wait-timeout 420

docker compose ps

# On note la version SEULEMENT si tout a réussi
echo "$IMAGE_TAG" > .last-good-version
echo "$NEXUS_DOCKER_TAG" > .last-good-nexus-tag

echo "✅ Backend déployé : $IMAGE_TAG"