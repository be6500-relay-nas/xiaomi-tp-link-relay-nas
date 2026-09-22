# 02 · WISP 中继 + NAT（单账号全校共享）

目标：小米作为 **STA 客户端**连上校园 WiFi（而非 AP 模式），再用 NAT 让宿舍内所有设备共享这一个认证。

## 核心配置（UCI）

```sh
# 无线侧：新增一个 STA 接口 wl12（保持原有 AP 不受影响）
uci set network.wwan=interface
uci set network.wwan.proto='dhcp'
uci set network.wwan.metric='10'          # 显式低于有线侧，防止抢路由（见下）
uci commit network

# 防火墙：wl12 归入 wan 区
uci add_list firewall.@zone[1].network='wwan'
uci commit firewall

# 有线 LAN 口照常做 DHCP，网关指向小米
```

STA 的具体无线参数（SSID/加密）用官方管理页的"工作模式 → 无线中继"配一次即可，命令行只负责网络层。

## 🔴 最大坑：双上行抢默认路由

小米默认有 `network.wan`（有线 WAN 口）和 `network.wwan`（中继 STA）**两个都是 `proto=dhcp` 且 `metric=0`**，
都声明默认路由。内核只留一条，**先到的赢**——于是出现经典症状：

> 中继链路完美（信号 -44dBm）、Portal 认证在线、LAN 内 DHCP 全正常，**就是整机和下游设备上不了外网**。

30 秒判别：

```sh
ip route | grep default
# 只应有一条，且必须是 ... dev wl12
# 若 default 走了 eth0.1（空 WAN 口）→ 中招
```

修复（先备份）：

```sh
uci export network > /data/backup/network.uci.bak-$(date +%Y%m%d)
uci set network.wan.defaultroute='0'
uci set network.wan.peerdns='0'
uci set network.wan.metric='100'
uci set network.wan.proto='none'      # WAN 口确认无用时彻底停用
uci commit network; ifdown wan; ifup wan
```

> ⭐ 连带影响：默认路由被抢时，**mihomo 会全线"节点不可用"**（rotate.log 狂刷"候选节点均不可用"）。
> 因为整机出不了网，任何节点探测必然失败——**不是机场/订阅坏了**。先查 `ip route | grep default`，再谈换订阅。

修复后核验：

```sh
curl -s -o /dev/null -w '%{http_code}' http://connect.rom.miui.com/generate_204   # 204 = 通
cat /proc/net/nf_conntrack | grep 192.168.31.    # 会话回包源地址是校园网 IP = NAT 真的通了
```

## 中继质量：信号决定一切

- 用 `iw dev wl12 link` 看关联 AP 与信号。**dBm 每差 10，吞吐差一个量级**
- 同名 SSID 往往有多个 AP，弱信号 AP 会拖死你：`iw dev wl12 scan dump | grep -A5 '<campus-ssid>'` 找出全部 BSSID 与信号
- 路由器的**物理摆放**比任何软件优化都有效——实测同一房间两个同名 AP 信号差 37dB
- ⚠️ 单频中继的 STA **不能主动 `iw scan`**（扫描=强制断链重连）；要看邻居 AP 用 TP-Link 那台独立射频扫（见 05 篇）

## PC 侧同源坑

电脑同时插网线 + 连 WiFi 时，若默认路由指向 192.168.31.1 会"没网"。
正确姿势：**有线静态 IP、不配网关**，默认路由唯一交给别的出口。

下一步：[03 · Portal 认证保活](03-portal-keepalive.md)
