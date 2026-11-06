#!/bin/bash

set -e

echo "===== Déploiement Frontend ====="

if [ -z "$IMAGE_TAG" ]; then
    echo "❌ IMAGE_TAG n'est pas défini"
    exit 1
fi
if [ -z "${NEXUS_DOCKER_TAG:-}" ]; then
    echo "❌ NEXUS_DOCKER_TAG n'est pas défini"
    exit 1
fi

echo "📦 Version à déployer : $IMAGE_TAG"

cd frontend

# Vérification des certificats
if [ ! -f "certs/nginx.crt" ]; then
    echo "❌ nginx.crt introuvable"
    exit 1
fi

if [ ! -f "certs/nginx.key" ]; then
    echo "❌ nginx.key introuvable"
    exit 1
fi

echo "🔐 Certificats SSL OK"

IMAGE_TAG="$IMAGE_TAG" bash ../scripts/pull-images-from-nexus.sh frontend

# Démarre le frontend et ATTEND qu'il soit healthy.
# Aucun build ici.
IMAGE_TAG="$IMAGE_TAG" docker compose up -d --no-build --wait --wait-timeout 420

docker compose ps

# On note la version SEULEMENT si tout a réussi
echo "$IMAGE_TAG" > .last-good-version
echo "$NEXUS_DOCKER_TAG" > .last-good-nexus-tag

echo "✅ Frontend déployé : $IMAGE_TAG"