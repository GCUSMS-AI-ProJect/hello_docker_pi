#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import subprocess
import sys


def request(action, host, port, enabled):
    payload = dict(action=action, host=host, port=port, enabled=enabled)
    worker = Path("/opt/helloboard/tools/bash_proxy.py")
    result = subprocess.run(
        [sys.executable, str(worker)],
        input=json.dumps(payload) + "\n",
        text=True,
        stdout=subprocess.PIPE,
        check=True,
    )
    reply = json.loads(result.stdout)
    if "error" in reply:
        sys.exit(reply["error"])
    return reply


def main():
    parser = argparse.ArgumentParser(description="配置当前容器用户的 Bash 代理")
    parser.add_argument("host", help="代理主机名或 IPv4 地址")
    parser.add_argument("port", type=int, help="HTTP 代理端口")
    parser.add_argument("--off", action="store_true", help="关闭代理")
    args = parser.parse_args()

    if not args.off:
        request("test", args.host, args.port, True)
    request("save", args.host, args.port, not args.off)
    print("代理已关闭" if args.off else "代理已保存，联网测试成功")
    print("已打开的 Bash 终端可运行 source ~/.bashrc")


if __name__ == "__main__":
    main()
