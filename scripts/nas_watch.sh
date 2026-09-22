#!/bin/sh
# nas_watch.sh —— NAS 服务看门狗 v4（重启免疫）
# 部署：小米 /etc/crontabs/patches/nas_watch.sh，crontab 每 2 分钟
# 依赖：FTP 快照库 <NAS盘>/.nasbin/（alist.tar.gz / rclone.gz / rclone.conf /
#       alist-data.tar.gz / tailscale-bin.tar.gz）
# 凭据：一律走环境变量（FTP_USER / FTP_PASS），绝不硬编码
# 特性：幂等；解压后立即删安装包（防 /tmp OOM）；data.db 大小校验；失败显式记日志

FTP_HOST="192.168.31.2"            # TP-Link（FTP 服务器）
FTP_USER="${FTP_USER:-nas}"
FTP_PASS="${FTP_PASS:?need FTP_PASS}"
FTPBASE="ftp://$FTP_HOST/volume3/.nasbin"
LOG=/tmp/nas_watch.log

log() { echo "$(date '+%m-%d %H:%M:%S') $1" >> "$LOG"; }
fetch() { # fetch <远程文件> <本地路径> —— 重试 5 次，成功返回 0
    local i=0
    while [ $i -lt 5 ]; do
        i=$((i+1))
        curl -s --user "$FTP_USER:$FTP_PASS" "$FTPBASE/$1" -o "$2" \
            && [ -s "$2" ] && return 0
        sleep 2
    done
    log "fetch FAILED after 5 tries: $1"
    return 1
}

# ---------- rclone (WebDAV 桥, :5245) ----------
if ! pidof rclone >/dev/null 2>&1; then
    if [ ! -x /tmp/rclone ]; then
        if [ ! -f /tmp/rclone.gz ]; then fetch rclone.gz /tmp/rclone.gz || exit 0; fi
        gzip -d -f -c /tmp/rclone.gz > /tmp/rclone && chmod +x /tmp/rclone \
            && rm -f /tmp/rclone.gz && log "rclone extracted (pkg deleted)"
    fi
    [ -f /tmp/rclone.conf ] || fetch rclone.conf /tmp/rclone.conf
    start-stop-daemon -S -b -m -p /tmp/rclone.pid -x /tmp/rclone -- \
        serve webdav tpftp:/volume3 --addr 127.0.0.1:5245 \
        --vfs-cache-mode writes --vfs-cache-max-size 60M \
        --config /tmp/rclone.conf >> /tmp/rclone.log 2>&1
    log "rclone started"
fi

# ---------- alist (WebUI + WebDAV, :5244) ----------
if ! pidof alist >/dev/null 2>&1; then
    if [ ! -x /tmp/alist-bin/alist ]; then
        if [ ! -f /tmp/alist.tar.gz ]; then fetch alist.tar.gz /tmp/alist.tar.gz || exit 0; fi
        mkdir -p /tmp/alist-bin
        tar -xzf /tmp/alist.tar.gz -C /tmp/alist-bin && chmod +x /tmp/alist-bin/alist \
            && rm -f /tmp/alist.tar.gz && log "alist extracted (pkg deleted)"
    fi
    if [ ! -s /tmp/alist-data/data.db ] || [ "$(wc -c < /tmp/alist-data/data.db)" -lt 32768 ]; then
        mkdir -p /tmp/alist-data
        # 必须整包 tar：SQLite 的存储配置在 -wal 文件里，只拷 data.db = 空库
        if fetch alist-data.tar.gz /tmp/alist-data.tar.gz; then
            tar -xzf /tmp/alist-data.tar.gz -C /tmp/alist-data \
                && rm -f /tmp/alist-data.tar.gz \
                && log "alist-data restored ($(wc -c < /tmp/alist-data/data.db) bytes)"
        fi
    fi
    start-stop-daemon -S -b -m -p /tmp/alist.pid -x /bin/sh -- \
        /tmp/alist-bin/alist server --data /tmp/alist-data >> /tmp/alist.log 2>&1
    log "alist started"
fi

# ---------- tailscaled (userspace, 授权态在 /etc/tailscale 持久) ----------
if [ -x /tmp/tsbin/tailscaled ] && ! pidof tailscaled >/dev/null 2>&1; then
    start-stop-daemon -S -b -m -p /tmp/ts.pid -x /tmp/tsbin/tailscaled -- \
        --tun=userspace-networking --statedir=/etc/tailscale \
        --socket=/var/run/tailscale.sock >> /tmp/tailscaled.log 2>&1
    log "tailscaled started (userspace)"
fi
# 掉授权（新装/状态损坏）时重挂 up：授权链接重新有效，用户点一次即连
if pidof tailscaled >/dev/null 2>&1; then
    if /tmp/tsbin/tailscale --socket=/var/run/tailscale.sock status 2>/dev/null | grep -q "Logged out"; then
        ( /tmp/tsbin/tailscale --socket=/var/run/tailscale.sock up \
            --hostname=dorm-nas --accept-dns=false >> /tmp/tsup.log 2>&1 & )
        log "tailscale up re-armed (waiting for auth)"
    fi
fi
