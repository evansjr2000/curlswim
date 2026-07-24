#!/bin/bash
# CWEB container helper script
# Usage: cweb.sh {ctangle|cweave|shell|build} [args...]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#IMAGE_NAME="cweb-tools"
IMAGE_NAME="evansjr/cweb:latest"

usage() {
    cat <<EOF
Usage: $0 {ctangle|cweave|shell|build} [args...]

Commands:
  ctangle file.cweb [changefile]  - Extract C code from CWEB file
  cweave file.cweb [changefile]   - Generate TeX documentation
  shell                           - Interactive bash shell
  build                           - Rebuild the Docker image
EOF
    exit 1
}

ensure_image() {
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        echo "Image not found. Building $IMAGE_NAME..."
        docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
    fi
}

#set +x
check_docker.sh
#sleep 5
#set -x

case "$1" in
    ctangle)
        shift
        ensure_image
        docker run --rm -v "$(pwd):/work" "$IMAGE_NAME" -c "ctangle $*"
        ;;
    cweave)
        shift
        ensure_image
        docker run --rm -v "$(pwd):/work" "$IMAGE_NAME" -c "cweave $*"
        ;;
    shell)
        ensure_image
        docker run --rm -it -v "$(pwd):/work" "$IMAGE_NAME"
        ;;
    build)
        echo "Building $IMAGE_NAME image..."
        docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
        ;;
    *)
        usage
        ;;
esac
