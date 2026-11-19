#!/bin/bash
set -eu
cd "$HOME"
if [[ ! -e helloboard ]]; then
    stage=$(mktemp -d "$HOME/.board.XXXXXX")
    cp -R /opt/helloboard/. "$stage/"
    mv -T "$stage" helloboard
fi
/usr/local/bin/start-desktop &
args=(--dashboard-only)
if [[ -n ${WIFI_INTERFACE:-} ]]; then
    args=(--wifi-control-socket /run/helloboard-control/network.sock --interface "$WIFI_INTERFACE"
          --config "$HOME/helloboard/wifi.yaml")
fi
if [[ -n ${WIFI_INTERFACE:-} || -n ${HELLOBOARD_PROXY_SOCKET:-} ]]; then
    for attempt in {1..50}; do
        [[ -s "$HOME/desktop-password" ]] && break
        sleep 0.2
    done
    [[ -s "$HOME/desktop-password" ]]
    /opt/board-venv/bin/python - <<'PY'
from pathlib import Path
from werkzeug.security import generate_password_hash
import os
os.umask(0o077)
home = Path.home()
path = home / ".helloboard-password-hash"
if not path.exists():
    tmp = path.with_suffix(".tmp")
    tmp.write_text(generate_password_hash((home / "desktop-password").read_text().strip()))
    tmp.replace(path)
PY
fi
/opt/board-venv/bin/python /opt/helloboard/wifi.py "${args[@]}" &
wait -n
