#!/bin/sh -e

show_help() {
	cat <<EOF >&2

Usage: ./${0##*/}  [ --lite | --desktop | --full ]  [ DOCKER_TAG ]

Defaults: --lite & DOCKER_TAG=raspios-firstboot

Variants --lite, --desktop, --full as per:
  https://www.raspberrypi.org/downloads/raspberry-pi-os/
EOF
}

case "$1" in
-h|--help) show_help       ; exit 0;;
--lite)    VARIANT=lite    ; shift ;;
--desktop) VARIANT=desktop ; shift ;;
--full)    VARIANT=full    ; shift ;;
--*)
	>&2 printf "\n  ERR: Flag unknown: '%s'\n" "$1"
	show_help
	exit 1 ;;
esac

export DOCKER_BUILDKIT=1

TAG="${1:-raspios-firstboot}"
DIR="$(pwd)/images"

[ -d "$DIR" ] || mkdir "$DIR"

docker build  --progress=plain  --tag="$TAG"  .
exec docker run  --privileged  --rm --volume="$DIR:/images/"  "$TAG"  create  "${VARIANT:-lite}"
