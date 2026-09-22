# 07 · Tailscale 外网访问

目标：人在外面（流量/别的 WiFi）也能直达宿舍 NAS，**不用公网 IP、不开端口映射**。

## 模式选择：必须 userspace

```sh
tailscaled --tun=userspace-networking --statedir=/etc/tailscale --socket=/var/run/tailscale.sock
```

> 🔴 **血泪教训**：先用内核 TUN 模式启动，路由器在几秒内自发重启（连续复现 3 次）。
> 这台机器的内核 TUN 驱动不可靠。userspace 模式纯用户态、完全不碰内核，稳定运行至今。
> 代价：路由器**自己**访问自己的 100.x 地址不通（设计如此），验证必须从另一台 tailnet 设备发起。

## 授权一次，永久生效

```sh
tailscale up --hostname=dorm-nas --accept-dns=false
# 输出一个 https://login.tailscale.com/a/xxx 链接，浏览器点一次登录即可
```

- 状态存 `/etc/tailscale/`（持久分区）——**重启自动重连，无需再授权**
- 看门狗兜底：发现"未授权"状态就自动重挂 `up`，让授权链接一直有效（拖延症友好）
- 授权后固定虚拟 IP `100.x.x.x`，外网开 `http://100.x.x.x:5244` = NAS

## 批量管理：API key

管理后台生成 API key（`tskey-api-...`，建议最小权限 + 短有效期）：

- **生成一次性授权密钥**给新设备入网（PC 静默 `tailscale up --authkey=...`，全程不弹窗）
- **清理僵尸节点**（改名/重装后残留的离线设备）：`DELETE /api/v2/device/<id>`
- tailnet 设备表定期看一眼：`GET /api/v2/tailnet/-/devices`，`lastSeen` 几天前的就是僵尸

⚠️ API key 权限大，用完即吊销；绝不写进任何脚本/仓库。

## PC / 手机客户端

- 装 Tailscale 客户端登同一账号即可，零配置
- 之后 `http://100.x.x.x:5244`（网页）与 `http://100.x.x.x:5244/dav`（WebDAV 挂载）宿舍内外同一套用法

## 下载慢的曲线救国

路由器经代理下载大文件常被掐（代理链路 + 弱中继双重抖动）。实测最快路径：
**PC 直连下载 → FTP 推到 NAS 盘 → 看门狗从 NAS 盘拉取**。PC 端 `curl -C -` 断点续传循环，
72 秒拿满 35MB（路由器侧同样内容试了半小时没下完）。

下一步：[08 · 稳定性治理](08-stability-oom.md)
