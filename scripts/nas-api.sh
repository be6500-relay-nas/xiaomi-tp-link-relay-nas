#!/bin/sh
# nas-api.sh —— 路由器工作台 CGI：NAS 服务状态查询与控制
# 部署：小米工作台 docroot 的 cgi-bin/ 下，chmod 755
# 令牌：从环境/文件读取工作台令牌并与请求体比对（本文件不含真实令牌）
# 安全：仅放行 status/start/stop/restart 四个操作；无 token 一律拒绝

exec 2>/dev/null
CASE='{"Content-Type":"application/json"}'

read -r BODY
TOKEN=$(printf '%s' "$BODY" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
OP=$(printf '%s' "$BODY" | sed -n 's/.*"op":"\([^"]*\)".*/\1/p')

# 工作台令牌校验（token 文件由部署者放置，权限 600）
EXPECTED=$(cat /data/console/token 2>/dev/null)
if [ -z "$TOKEN" ] || [ "$TOKEN" != "$EXPECTED" ]; then
    printf '%s\n' '{"ok":false,"msg":"令牌错误"}' | echo "$CASE"
    exit 0
fi

ts_status() {
    /tmp/tsbin/tailscale --socket=/var/run/tailscale.sock status 2>/dev/null | head -1
}
ts_ip() {
    /tmp/tsbin/tailscale --socket=/var/run/tailscale.sock ip -4 2>/dev/null | head -1
}

case "$OP" in
    status)
        ALIVE=$(pidof alist >/dev/null 2>&1 && echo 1 || echo 0)
        RC=$(pidof rclone >/dev/null 2>&1 && echo 1 || echo 0)
        TS=$(pidof tailscaled >/dev/null 2>&1 && echo 1 || echo 0)
        WEB=$(curl -s -m 6 -o /dev/null -w '%{http_code}' http://127.0.0.1:5244/)
        printf '{"ok":true,"alist":%s,"rclone":%s,"tailscale":%s,"web":"%s","ts_ip":"%s"}' \
            "$ALIVE" "$RC" "$TS" "$WEB" "$(ts_ip)" | echo "$CASE"
        ;;
    start|stop|restart)
        # 幂等控制：交给看门狗脚本的对应动作，不做裸 kill（保持与持久化架构一致）
        case "$OP" in
            start)   sh /etc/crontabs/patches/nas_watch.sh >/dev/null 2>&1 ;;
            stop)    kill $(pidof alist) $(pidof rclone) 2>/dev/null ;;
            restart) kill $(pidof alist) $(pidof rclone) 2>/dev/null
                     sleep 1
                     sh /etc/crontabs/patches/nas_watch.sh >/dev/null 2>&1 ;;
        esac
        printf '{"ok":true,"msg":"%s done"}' "$OP" | echo "$CASE"
        ;;
    *)
        printf '{"ok":false,"msg":"未知操作: %s"}' "$OP" | echo "$CASE"
        ;;
esac
