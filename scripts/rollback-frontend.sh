#!/bin/bash

set -e

echo "===== Rollback Frontend ====="

cd frontend

if [ ! -s ".last-good-version" ]; then

    echo "❌ Aucune version fonctionnelle connue — rollback impossible"

    exit 1

fi
if [ ! -s ".last-good-nexus-tag" ]; then

    echo "❌ Aucun tag Nexus fonctionnel connu — rollback impossible"

    exit 1

fi

VERSION=$(cat .last-good-version)
NEXUS_DOCKER_TAG=$(cat .last-good-nexus-tag)

echo "🔄 Retour à la version : $VERSION (Nexus: $NEXUS_DOCKER_TAG)"

IMAGE_TAG="$VERSION" NEXUS_DOCKER_TAG="$NEXUS_DOCKER_TAG" bash ../scripts/pull-images-from-nexus.sh frontend
IMAGE_TAG="$VERSION" docker compose up -d --no-build --wait --wait-timeout 420

docker compose ps

echo "✅ Rollback terminé : $VERSION"