#!/usr/bin/env sh

set -e

export DOCKER_BUILDKIT=1

TAG=raspios-firstboot

docker build  --progress=plain  --tag  "$TAG"  .

docker run  --privileged  --rm  --volume="$(pwd)/images:/raspios/"  "$TAG"
