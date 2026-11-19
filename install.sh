#!/usr/bin/env bash
# Parse the full installer before executing anything when streamed into Bash.
{
set -Eeuo pipefail
installer_path=${BASH_SOURCE[0]:-}
if [[ -n $installer_path ]]; then
    cd -- "$(dirname -- "$installer_path")"
fi
export PATH="$HOME/bin:$PATH"
export http_proxy="${http_proxy:-${HTTP_PROXY:-}}" https_proxy="${https_proxy:-${HTTPS_PROXY:-}}"
fail() { echo "停止：$*" >&2; exit 1; }
say() { echo "· $*"; }
trap 'echo "安装失败（第 $LINENO 行）。修复上方错误后可重新执行。" >&2' ERR
usage() {
    echo "用法：./install.sh [--check|--help]，或 curl -fsSL 安装地址 | bash -s -- [--check]"
}
if [[ ${1:-} == --help && $# == 1 ]]; then
    usage
    exit 0
fi
[[ $# == 0 || ( $# == 1 && $1 == --check ) ]] || { usage >&2; exit 2; }
[[ $EUID != 0 ]] || fail "请以日常用户运行，脚本会按需使用 sudo。"
[[ -r /etc/os-release ]] || fail "缺少 /etc/os-release。"
source /etc/os-release
for tool in ss timeout sudo; do
    command -v "$tool" >/dev/null || fail "请先安装 $tool。"
done
say "$PRETTY_NAME · $(uname -m) · 可用空间 $(df -h . | awk 'END{print $4}')"
[[ -d /run/systemd/system ]] || fail "需要使用 systemd 的 Linux 主机。"
case "$ID:${VERSION_CODENAME:-}" in
  debian:trixie|raspbian:trixie) compose_pkg=docker-compose ;;
  ubuntu:noble) compose_pkg=docker-compose-v2 ;;
  *) fail "支持 Debian / Raspberry Pi OS 13 或 Ubuntu 24.04。" ;;
esac
case "$(uname -m)" in aarch64|x86_64) ;; *) fail "需要 ARM64 或 x86_64 系统。";; esac
systemctl --user show-environment >/dev/null || fail "请登录目标用户的本机会话或 SSH 会话。"
export CONTAINER_SUDO="${CONTAINER_SUDO:-0}" GPIO_DEVICE="${GPIO_DEVICE:-}"
case "$CONTAINER_SUDO" in
  0) ;;
  1) say "启用容器内 sudo" ;;
  *) fail "CONTAINER_SUDO 只能设为 0 或 1。" ;;
esac
if [[ -n $GPIO_DEVICE ]]; then
    [[ $GPIO_DEVICE =~ ^/dev/gpiochip[0-9]+$ && -c $GPIO_DEVICE ]] ||
        fail "GPIO_DEVICE 必须指向宿主机存在的 /dev/gpiochipN。"
    [[ -r $GPIO_DEVICE && -w $GPIO_DEVICE ]] ||
        fail "当前宿主机用户需要 $GPIO_DEVICE 的读写权限。"
    say "映射 GPIO 设备 $GPIO_DEVICE"
fi
interface=${WIFI_INTERFACE:-}
requested_interface=$interface
if [[ -z $interface ]] && command -v nmcli >/dev/null; then
    interface=$(LC_ALL=C nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2=="wifi" && $3=="connected"{print $1; found=1; exit} $2=="wifi" && $3=="disconnected" && !dev{dev=$1} END{if (!found) print dev}' || true)
fi
wifi=0
if [[ -n $interface && $interface =~ ^[a-zA-Z0-9_.-]{1,15}$ ]] && [[ $(LC_ALL=C nmcli -g WIFI-PROPERTIES.AP device show "$interface" 2>/dev/null) == yes ]]; then
    wifi=1
    say "Wi-Fi 管理网卡 $interface"
elif [[ -n $requested_interface ]]; then
    fail "指定网卡 $requested_interface 不支持热点，或 NetworkManager 未管理该网卡。"
else
    say "未检测到由 NetworkManager 管理且支持热点的网卡，将启用系统看板。"
fi
runtime="unix://${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock"
export DOCKER_HOST="$runtime"
unset DOCKER_CONTEXT
available() {
    timeout 5 docker info --format '{{json .SecurityOptions}}' 2>/dev/null | grep -q rootless
}
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

if [[ -z $installer_path ]]; then
    repo_url=https://github.com/GCUSMS-AI-ProJect/hello_docker_pi.git
    deploy_dir="$HOME/hello_docker_pi"

    if [[ -e $deploy_dir || -L $deploy_dir ]]; then
        [[ -d $deploy_dir/.git ]] || fail "$deploy_dir 已存在，请移开该目录后重试。"
    fi
    if ! command -v git >/dev/null; then
        say "安装 Git"
        sudo apt-get update
        sudo apt-get install -y git
    fi

    if [[ -d $deploy_dir/.git ]]; then
        [[ $(git -C "$deploy_dir" remote get-url origin) == "$repo_url" ]] ||
            fail "$deploy_dir 指向其他仓库。"
        [[ $(git -C "$deploy_dir" branch --show-current) == main ]] ||
            fail "请先切换 $deploy_dir 到 main 分支。"
        [[ -z $(git -C "$deploy_dir" status --porcelain --untracked-files=no) ]] ||
            fail "$deploy_dir 有未提交的更改，请先提交或保存。"
        say "更新安装文件"
        git -C "$deploy_dir" pull --ff-only origin main
    else
        say "下载安装文件"
        download_dir=$(mktemp -d "$HOME/.hello_docker_pi.XXXXXX")
        trap 'rm -rf -- "$download_dir"' EXIT
        git clone --depth 1 --branch main "$repo_url" "$download_dir"
        mv -T -- "$download_dir" "$deploy_dir"
        trap - EXIT
    fi
    exec bash "$deploy_dir/install.sh"
fi

say "检查系统依赖"
packages=(acl curl ca-certificates git uidmap slirp4netns iptables "$compose_pkg" docker-buildx python3-yaml)
missing=()
for pkg in "${packages[@]}"; do
    [[ $(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null || true) == installed ]] || missing+=("$pkg")
done
if (( ${#missing[@]} )); then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
fi
say "检查 HelloBoard 下载来源"
timeout 15 git ls-remote --exit-code https://github.com/GCUSMS-AI-ProJect/helloboard.git refs/heads/main >/dev/null ||
    fail "无法访问 HelloBoard 仓库，请检查网络或代理。"

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
loginctl enable-linger "$(id -un)" || sudo loginctl enable-linger "$(id -un)"
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
docker compose build || fail "镜像构建失败，请检查上方下载日志。"
args=(-f compose.yaml)
[[ $CONTAINER_SUDO == 0 ]] || args+=(-f compose.sudo.yaml)
[[ -z $GPIO_DEVICE ]] || args+=(-f compose.gpio.yaml)
stage=$(mktemp -d)
probe=
cleanup() {
    if [[ -n $probe ]]; then
        docker rm -f "$probe" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$stage"
}
trap cleanup EXIT
probe=$(docker run -d --entrypoint sleep hello-docker-pi:local 300)
pid=$(docker inspect -f '{{.State.Pid}}' "$probe")
mapped=$(awk '/^Uid:/{print $2}' "/proc/$pid/status")
[[ $mapped =~ ^[0-9]+$ && $mapped -gt 0 && $mapped -ne $UID ]] ||
    fail "容器用户映射无效。"

share_dir="$HOME/file_share"
[[ ! -L $share_dir ]] || fail "$share_dir 必须是实际目录。"
mkdir -p -m 700 -- "$share_dir" || fail "无法创建 $share_dir。"
[[ -O $share_dir ]] || fail "$share_dir 须由当前宿主机用户拥有。"
setfacl -m "u:$mapped:rwx,d:u:$UID:rwx,d:u:$mapped:rwx,d:g::---,d:o::---" -- "$share_dir" ||
    fail "无法设置 $share_dir 的共享权限，请检查文件系统是否支持 ACL。"
say "共享文件夹 $share_dir ↔ /home/hellodocker/file_share"

say "配置宿主机 Bash 代理服务"
proxy_dir="$HOME/.local/share/hello_docker_pi"
units_dir="$HOME/.config/systemd/user"
install -d -m 700 "$proxy_dir" "$proxy_dir/proxy"
mkdir -p "$units_dir"
docker cp "$probe:/opt/helloboard/tools/bash_proxy.py" "$stage/"
install -m 644 "$stage/bash_proxy.py" "$proxy_dir/bash_proxy.py"
sed "s/MAPPED_UID/$mapped/" systemd/helloboard-bash-proxy.socket > "$stage/helloboard-bash-proxy.socket"
install -m 644 "$stage/helloboard-bash-proxy.socket" systemd/helloboard-bash-proxy@.service "$units_dir/"
systemctl --user daemon-reload
systemctl --user enable helloboard-bash-proxy.socket
systemctl --user restart helloboard-bash-proxy.socket
if (( wifi )); then
    say "配置宿主机 Wi-Fi 服务"
    for file in configuration.py network.py packaging/wifi-control/worker.py; do
        docker cp "$probe:/opt/helloboard/$file" "$stage/"
    done
    sed "s/WIFI_INTERFACE/$interface/" systemd/helloboard-control@.service > "$stage/helloboard-control@.service"
    sed "s/MAPPED_UID/$mapped/" systemd/helloboard-control.socket > "$stage/helloboard-control.socket"
    sudo install -d /usr/local/lib/helloboard-control /var/lib/helloboard-control
    sudo install -m 644 "$stage/"{configuration,network,worker}.py /usr/local/lib/helloboard-control/
    sudo install -m 644 "$stage/"helloboard-control{.socket,@.service} /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable helloboard-control.socket
    sudo systemctl restart helloboard-control.socket
    export WIFI_INTERFACE="$interface"
    args+=(-f compose.wifi.yaml)
fi
cleanup
trap - EXIT
docker compose "${args[@]}" up -d
for attempt in {1..40}; do
    if docker exec hello_docker xdpyinfo >/dev/null 2>&1 && docker exec hello_docker /opt/board-venv/bin/python -c \
        'import json,sys,urllib.request as u; s=json.load(u.urlopen("http://localhost:8090/api/status",timeout=3)); assert bool(s["capabilities"]["manage"]) == bool(int(sys.argv[1])); assert b"id=\"proxy-form\"" in u.urlopen("http://localhost:8090/proxy",timeout=3).read()' "$wifi" 2>/dev/null; then
        ip=$(hostname -I | awk '{print $1}')
        say "安装完成。HelloBoard：http://${BOARD_BIND:-${ip:-localhost}}:8090"
        say "桌面：http://127.0.0.1:6080/vnc.html"
        say "密码：$(command -v docker) exec hello_docker cat /home/hellodocker/config/desktop-password"
        exit 0
    fi
    sleep 1
done
docker logs --tail 20 hello_docker
fail "服务未就绪，请检查上述日志。"
}
