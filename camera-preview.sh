#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
export PATH="$HOME/bin:$PATH"
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock"
case "${1:-csi}" in
  csi)
    rpicam-vid --nopreview --timeout 0 --codec mjpeg --width 640 --height 480 --framerate 15 --output -
    ;;
  /dev/video*)
    ffmpeg -hide_banner -loglevel error -f v4l2 -i "$1" -an -c:v mjpeg -f mjpeg -
    ;;
  *) echo "Usage: $0 [csi|/dev/videoN]" >&2; exit 2 ;;
esac | docker compose exec -T desktop ffplay -loglevel error -autoexit -f mjpeg -i pipe:0
