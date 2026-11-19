# hello_docker_pi

在树莓派上部署开机自启的 Rootless Docker 开发桌面和 HelloBoard。容器名为 `hello_docker`，容器用户和主机名为 `hellodocker`。

## 1. 检查环境

使用有 `sudo` 权限的普通用户，在目标设备上打开终端或通过 SSH 登录。

| 系统 | 架构 | Compose 软件包 |
| --- | --- | --- |
| Raspberry Pi OS 64 位或 Debian 13（Trixie） | ARM64，Debian 也支持 x86_64 | `docker-compose` |
| Ubuntu 24.04 LTS（Noble） | ARM64 或 x86_64 | `docker-compose-v2` |

如果缺少 `curl`，在目标设备运行 `sudo apt-get update && sudo apt-get install -y curl`。然后检查系统、架构、Docker、端口和无线网卡。

```bash
curl -fsSL https://raw.githubusercontent.com/GCUSMS-AI-ProJect/hello_docker_pi/main/install.sh | bash -s -- --check
```

`--check` 仅报告环境检查结果。遇到端口冲突或其他项目占用了 `hello_docker` 时，脚本会停止并提示原因。

## 2. 一键安装或更新

```bash
curl -fsSL https://raw.githubusercontent.com/GCUSMS-AI-ProJect/hello_docker_pi/main/install.sh | bash
```

首次运行会把仓库下载到 `~/hello_docker_pi`，补齐依赖，构建镜像并配置自启。已安装的设备重复运行同一条命令即可更新。代码和桌面设置位于容器的 `/home/hellodocker` 数据卷。

已有其他路径的仓库副本时，可在该目录运行 `git pull --ff-only && ./install.sh`。首次构建需要访问 GitHub、Docker Hub、系统软件源和 PyPI。Docker Hub 超时时，在当前终端加载能访问 Docker Hub 的代理后重试。[安装脚本](install.sh) · [HelloBoard 源码](https://github.com/GCUSMS-AI-ProJect/helloboard)

## 3. 访问和使用

| 功能 | 入口 |
| --- | --- |
| HelloBoard | 同一可信局域网打开 `http://设备IP:8090` |
| 图形桌面 | 设备本机打开 [noVNC](http://127.0.0.1:6080/vnc.html)。从电脑访问时，先在电脑终端运行 `ssh -N -L 6080:127.0.0.1:6080 用户@设备IP`，再用电脑浏览器打开同一地址 |
| 登录 | HelloBoard 用户名为 `hellodocker`。密码首次启动时随机生成，通过下方命令查看。noVNC 也使用此密码 |
| 文件和绘图 | 将文件放入安装目录的 `files/`，在桌面的 `/work` 中打开图片或 PDF。运行 Matplotlib 可以打开绘图窗口 |
| 宿主机代理 | 在 HelloBoard 的「代理」页测试并保存。已打开的 Bash 终端运行 `source ~/.bashrc` 后应用新设置 |

在树莓派终端执行以下命令，连接当前用户的 Rootless Docker，然后查看密码或进入开发目录。

```bash
export PATH="$HOME/bin:$PATH"
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"
unset DOCKER_CONTEXT
docker exec hello_docker cat /home/hellodocker/desktop-password
docker exec -it hello_docker bash
```

## 按需配置

- **只在本机访问 HelloBoard**。把一键安装命令末尾的 `bash` 换成 `BOARD_BIND=127.0.0.1 bash`。
- **指定 Wi-Fi 网卡**。把一键安装命令末尾的 `bash` 换成 `WIFI_INTERFACE=wlan1 bash`，并按实际网卡名修改。完整 Wi-Fi 管理需要 NetworkManager 和支持 AP 模式的网卡。首次部署沿用当前连接，手动切换热点会断开该网卡上的 SSH。
- **查看摄像头**。在安装目录运行 `./camera-preview.sh csi` 或 `./camera-preview.sh /dev/video0`。宿主机分别需要 `rpicam-vid` 或 `ffmpeg`。
- **定位启动失败**。先执行上面的 Rootless Docker 环境设置，再运行 `docker logs --tail 30 hello_docker`。

镜像已在 Raspberry Pi 5、Debian 13 ARM64 上验证。
