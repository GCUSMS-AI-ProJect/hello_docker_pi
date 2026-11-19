# hello_docker_pi

在树莓派上运行开机自启的 Rootless Docker 开发桌面和 HelloBoard。容器名为 `hello_docker`，用户和主机名为 `hellodocker`。代码和桌面设置保存在持久化的 `/home/hellodocker`。

## 安装

在目标设备用普通用户登录，准备好 Git、网络和 sudo 权限，然后运行：

```bash
git clone https://github.com/GCUSMS-AI-ProJect/hello_docker_pi.git
cd hello_docker_pi
./install.sh
```

脚本先检查系统、架构、端口和无线网卡，再安装 Rootless Docker 所需的依赖。构建时从 GitHub 下载 Dockerfile 中固定版本的 HelloBoard，安装 Python 依赖，并配置宿主机代理服务。首次构建会下载图形桌面。仅检查可运行 `./install.sh --check`。已在 Raspberry Pi 5、Debian 13 ARM64 验证镜像；脚本也提供 Ubuntu 24.04 和 x86_64 的安装路径。

## 使用

| 功能 | 入口 |
| --- | --- |
| HelloBoard | 同一局域网打开 `http://设备IP:8090`。默认监听设备全部 IPv4 接口，适用于可信局域网 |
| 终端代理 | 在 HelloBoard 打开「代理」，登录后测试并保存宿主机当前用户的 Bash 代理。已打开的终端可运行 `source ~/.bashrc` |
| 图形桌面 | 本机打开 `http://127.0.0.1:6080/vnc.html`；远程先用 `ssh -L 6080:127.0.0.1:6080 用户@设备IP` |
| 登录 | 用户名 `hellodocker`。首次启动随机生成密码，在设备终端运行 `~/bin/docker exec hello_docker cat /home/hellodocker/desktop-password` 查看 |
| 开发终端 | `~/bin/docker exec -it hello_docker bash` |
| 图片、PDF 和绘图 | 在桌面打开文件或运行 Matplotlib；宿主机的 `files/` 在容器内映射为只读目录 `/work` |
| 摄像头 | CSI 使用 `./camera-preview.sh csi`；USB 使用 `./camera-preview.sh /dev/video0`。宿主机分别需要 `rpicam-vid` 或 `ffmpeg` |

支持热点的 NetworkManager 无线网卡会启用完整 Wi-Fi 面板；其他设备启动系统看板。多网卡可用 `WIFI_INTERFACE=wlan1 ./install.sh` 指定网卡。首次部署沿用当前连接，手动切换热点会断开该网卡上的 SSH。固定使用本机访问可运行 `BOARD_BIND=127.0.0.1 ./install.sh`。

已有同名容器或端口被占用时，脚本会提示并停止。启动失败可运行 `~/bin/docker logs --tail 30 hello_docker` 查看原因。

在已由本项目部署的设备上，`git pull --ff-only` 后重新运行 `./install.sh` 即可更新。面板使用镜像中固定版本的源码，家目录里的 HelloBoard 仓库保留为开发副本。
