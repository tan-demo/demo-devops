#!/usr/bin/env sh
set -eu

IMAGE="${IMAGE:-ghcr.io/tan-demo/quote-api}"
TAG="${TAG:-dev}"
CLUSTER="${CLUSTER:-devops}"

cd /workspace
echo ">> building ${IMAGE}:${TAG} from ./app/quote-api"
docker build -t "${IMAGE}:${TAG}" app/quote-api

echo ">> importing ${IMAGE}:${TAG} into k3d cluster '${CLUSTER}'"
k3d image import "${IMAGE}:${TAG}" -c "${CLUSTER}"

echo ">> done."
