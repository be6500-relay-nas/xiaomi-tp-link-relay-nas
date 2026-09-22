#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""router_ssh.py —— 老固件路由器 SSH 执行器模板（paramiko）

用法：
    ROUTER_HOST=192.168.31.1 ROUTER_PORT=22 ROUTER_USER=root \
    ROUTER_PASS='<密码>' python router_ssh.py "cat /proc/uptime"

凭据一律走环境变量，绝不写进代码/仓库。
"""
import os
import sys

import paramiko

# paramiko 5.x 移除了老算法，与老 dropbear 握手会报 "no acceptable host key"
# 必须锁 3.5.1：uv run --python 3.11 --with "paramiko==3.5.1" python router_ssh.py ...
for _attr, _extra in (
    ("_preferred_keys", ("ssh-rsa", "rsa-sha2-256", "rsa-sha2-512")),
    ("_preferred_ciphers", ("aes128-ctr", "aes192-ctr", "aes256-ctr")),
    ("_preferred_macs", ("hmac-sha1", "hmac-sha2-256")),
):
    _cur = list(getattr(paramiko.Transport, _attr, ()) or ())
    for _name in reversed(_extra):
        if _name not in _cur:
            _cur.insert(0, _name)
    setattr(paramiko.Transport, _attr, tuple(_cur))


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    host = os.environ.get("ROUTER_HOST", "192.168.31.1")
    port = int(os.environ.get("ROUTER_PORT", "22"))
    user = os.environ.get("ROUTER_USER", "root")
    password = os.environ.get("ROUTER_PASS")
    if not password:
        print("need ROUTER_PASS env", file=sys.stderr)
        return 2

    cli = paramiko.SSHClient()
    cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    # 老机器握手段宁慢勿炸：auth/banner 超时放宽；高频连接会把 dropbear 打进
    # ~90s 保护期（SYN 不响应、自愈），脚本侧应控制调用节奏
    cli.connect(host, port, user, password=password, timeout=30,
                auth_timeout=60, banner_timeout=30,
                allow_agent=False, look_for_keys=False)
    try:
        _, out, err = cli.exec_command(cmd, timeout=120)
        sys.stdout.write(out.read().decode("utf-8", "replace"))
        e = err.read().decode("utf-8", "replace")
        if e.strip():
            sys.stderr.write("[stderr] " + e[:500])
        rc = out.channel.recv_exit_status()
        return rc or 0
    finally:
        cli.close()


if __name__ == "__main__":
    sys.exit(main())
