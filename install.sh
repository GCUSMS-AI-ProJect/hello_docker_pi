#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/bin:$PATH"
export http_proxy="${http_proxy:-${HTTP_PROXY:-}}" https_proxy="${https_proxy:-${HTTPS_PROXY:-}}"
fail() { echo "停止：$*" >&2; exit 1; }
say() { echo "· $*"; }
trap 'echo "安装失败（第 $LINENO 行）。修复上方错误后可重新执行。" >&2' ERR
[[ $# == 0 || ( $# == 1 && $1 == --check ) ]] || fail "用法：./install.sh [--check]"
[[ $EUID != 0 ]] || fail "请以日常用户运行，脚本会按需使用 sudo。"
source /etc/os-release
say "$PRETTY_NAME · $(uname -m) · 可用空间 $(df -h . | awk 'END{print $4}')"
[[ -d /run/systemd/system ]] || fail "需要使用 systemd 的 Linux 主机。"
case "$ID:$VERSION_CODENAME" in
  debian:trixie|raspbian:trixie) compose_pkg=docker-compose ;;
  ubuntu:noble) compose_pkg=docker-compose-v2 ;;
  *) fail "支持 Debian / Raspberry Pi OS 13 或 Ubuntu 24.04。" ;;
esac
case "$(uname -m)" in aarch64|x86_64) ;; *) fail "需要 ARM64 或 x86_64 系统。";; esac
systemctl --user show-environment >/dev/null || fail "请登录目标用户的本机会话或 SSH 会话。"
interface=${WIFI_INTERFACE:-}
if [[ -z $interface ]] && command -v nmcli >/dev/null; then
    interface=$(LC_ALL=C nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2=="wifi" && $3=="connected"{print $1; found=1; exit} $2=="wifi" && $3=="disconnected" && !dev{dev=$1} END{if (!found) print dev}' || true)
fi
wifi=0
if [[ -n $interface && $interface =~ ^[a-zA-Z0-9_.-]{1,15}$ ]] && [[ $(LC_ALL=C nmcli -g WIFI-PROPERTIES.AP device show "$interface" 2>/dev/null) == yes ]]; then
    wifi=1
    say "Wi-Fi 管理网卡 $interface"
else
    say "未检测到由 NetworkManager 管理且支持热点的网卡，将启用系统看板。"
fi
runtime="unix://${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock"
export DOCKER_HOST="$runtime"
unset DOCKER_CONTEXT
available() { docker info --format '{{json .SecurityOptions}}' 2>/dev/null | grep -q rootless; }
own=false
if available; then
    say "Rootless Docker 已就绪"
    project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' hello_docker 2>/dev/null || true)
    if [[ $project == hello_docker_pi ]]; then own=true; elif [[ -n $project ]] || docker inspect hello_docker >/dev/null 2>&1; then
        fail "hello_docker 已由其他部署使用；现有容器已保留。"
    fi
else
    say "需要安装或启动 Rootless Docker"
fi
if ! $own; then
    for port in 6080 8090; do
        [[ -z $(ss -Hlt "sport = :$port") ]] || fail "端口 $port 已被使用。"
    done
fi
[[ ${1:-} != --check ]] || { say "检查完成"; exit 0; }

say "检查系统依赖"
packages=(curl ca-certificates uidmap slirp4netns iptables "$compose_pkg" docker-buildx python3-yaml)
missing=()
for pkg in "${packages[@]}"; do
    [[ $(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null || true) == installed ]] || missing+=("$pkg")
done
if (( ${#missing[@]} )); then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
fi
if ! available; then
    sudo modprobe nf_tables
    if command -v dockerd-rootless-setuptool.sh >/dev/null; then
        dockerd-rootless-setuptool.sh install
    else
        installer=$(mktemp)
        curl -fsSL --retry 3 https://get.docker.com/rootless -o "$installer"
        sh "$installer"
        rm -f "$installer"
    fi
fi
loginctl enable-linger "$USER" || sudo loginctl enable-linger "$USER"
systemctl --user enable --now docker
if [[ -n ${http_proxy:-} || -n ${https_proxy:-} ]]; then
    # Load the local proxy on restart without committing machine-specific values.
    dir="$HOME/.config/systemd/user/docker.service.d"
    mkdir -p "$dir"
    python3 - "$dir/hello-pi-proxy.conf" <<'PY'
import os, pathlib, sys
p = pathlib.Path(sys.argv[1])
lines = ["[Service]"]
for key in ("http_proxy", "https_proxy", "no_proxy"):
    value = os.getenv(key)
    if value:
        if any(c in value for c in '\r\n\0'):
            raise ValueError("invalid proxy setting")
        value = value.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
        lines.append(f'Environment="{key.upper()}={value}"')
data = "\n".join(lines) + "\n"
os.umask(0o077)
changed = not p.exists() or p.read_text() != data
if changed:
    p.write_text(data)
    p.with_suffix(".changed").touch()
PY
    if [[ -f $dir/hello-pi-proxy.changed ]]; then
        systemctl --user daemon-reload
        systemctl --user restart docker
        rm -f "$dir/hello-pi-proxy.changed"
    fi
fi
available || fail "Rootless Docker 未就绪，运行 journalctl --user -u docker 查看原因。"
docker compose version >/dev/null
mkdir -p files
say "构建桌面和 HelloBoard（首次下载较大）"
docker compose build
args=(-f compose.yaml)
if (( wifi )); then
    say "配置宿主机 Wi-Fi 服务"
    stage=$(mktemp -d)
    probe=$(docker run -d --entrypoint sleep hello-docker-pi:local 300)
    cleanup() { docker rm -f "$probe" >/dev/null 2>&1 || true; rm -rf -- "$stage"; }
    trap cleanup EXIT
    pid=$(docker inspect -f '{{.State.Pid}}' "$probe")
    mapped=$(awk '/^Uid:/{print $2}' "/proc/$pid/status")
    [[ $mapped =~ ^[0-9]+$ && $mapped -gt 0 ]] || fail "容器用户映射无效。"
    for file in configuration.py network.py packaging/wifi-control/worker.py; do
        docker cp "$probe:/opt/helloboard/$file" "$stage/"
    done
    sed "s/WIFI_INTERFACE/$interface/" systemd/helloboard-control@.service > "$stage/helloboard-control@.service"
    sed "s/MAPPED_UID/$mapped/" systemd/helloboard-control.socket > "$stage/helloboard-control.socket"
    sudo install -d /usr/local/lib/helloboard-control /var/lib/helloboard-control
    sudo install -m 644 "$stage/"*.py /usr/local/lib/helloboard-control/
    sudo install -m 644 "$stage/"helloboard-control* /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable helloboard-control.socket
    sudo systemctl restart helloboard-control.socket
    cleanup
    trap - EXIT
    export WIFI_INTERFACE="$interface"
    args+=(-f compose.wifi.yaml)
fi
docker compose "${args[@]}" up -d
for attempt in {1..40}; do
    if docker exec hello_docker xdpyinfo >/dev/null 2>&1 && docker exec hello_docker /opt/board-venv/bin/python -c \
        'import json,sys,urllib.request as u; s=json.load(u.urlopen("http://localhost:8090/api/status",timeout=3)); assert bool(s["capabilities"]["manage"]) == bool(int(sys.argv[1]))' "$wifi" 2>/dev/null; then
        ip=$(hostname -I | awk '{print $1}')
        say "安装完成。HelloBoard：http://${ip:-localhost}:8090"
        say "桌面：http://127.0.0.1:6080/vnc.html"
        say "密码：docker exec hello_docker cat /home/hellodocker/desktop-password"
        exit 0
    fi
    sleep 1
done
docker logs --tail 20 hello_docker
fail "服务未就绪，请检查上述日志。"
