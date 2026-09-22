# 08 · 稳定性治理：OOM、看门狗与全链路体检

前七篇把功能堆起来之后，真正的功课是**让它一直活着**。

## 🔴 OOM 因果链（本项目最深的坑）

```
/tmp（RAM 盘）堆大文件（安装包/解压产物/VFS 缓存）
  → 可用内存跌到个位数 MB
  → 内核 OOM killer 挑最大的进程下手（hostapd！）
  → WiFi 信号凭空消失（"没信号"的真凶）
  → 看门狗检测到异常 → 重启 → 恢复服务又往 /tmp 塞文件 → 循环
```

**判据**：`free` 的 available 跌破 ~50MB 就是红线；`dmesg | grep -i 'out of memory'` 留痕。

**治理**（看门狗 v4 设计）：

1. 从 NAS 快照**解压后立即删安装包**（/tmp 峰值砍半）
2. rclone `--vfs-cache-max-size 60M`（从 100M 降）
3. 往 /tmp 放任何大文件前先 `free`；大文件一律落 NAS 盘
4. 修完跑压测 + 长周期观察（每 10 分钟记录 uptime/服务/外网的独立监控）

## 看门狗全家桶（crontab 布局）

| 任务 | 周期 | 职责 |
|---|---|---|
| campus-keeper | 1 min | 外网 204 探测、Portal 重认证、STA 重连 |
| relay-guard | 1 min | 中继链路守护 |
| nas_watch | 2 min | alist/rclone/tailscale 进程与端口、从 .nasbin 恢复 |
| proxy guard/rotate | 2 min | mihomo 进程、节点轮换 |

设计原则：

- **幂等**：任何时刻手动跑一遍都安全
- **冷却时间**：同一动作 120s 内不重复（防自杀循环）
- **显式失败日志**：FTP 拉取重试 5 次、`data.db` 大小校验（<32KB=空库）——失败要**喊出来**，不能静默吞掉
- 每个 cron 任务都写日志到自己的文件，排障只看日志

## 全链路体检清单（分层，每层都有标准判据）

```
L1 PC→小米   WebUI 200 / 登录 / 列目录 / WebDAV 1MB 字节级往返 / 删除 / 工作台状态 CGI
L2 小米内部  四服务进程数 / 看门狗 cron 在位 / uptime / available 内存 / 代理出口 204
L3 →TP-Link→盘 FTP 可达 / 快照库文件齐 / NTFS 挂载 uid=55 / rc.local 落盘一致
L4 Tailscale API lastSeen < 1min / 固定 IP 可达
L5 外网模拟  纯校园网设备经隧道 6 项全过
```

> 💡 体检脚本全部**强制绕过系统代理**（`ProxyHandler({})`），否则数据被本机代理污染，
> 会出现"502 但网络其实是好的"的幽灵故障。

## 已知残留（诚实清单）

- 一次性 FTP 瞬时抖动（60s 内自愈）：uid 判据若写在 /proc/mounts 会误判重挂（见 06 篇正确判据）
- `/data` 分区 96% 满：删冗余安装包腾空间时注意——UBIFS 满到**连 truncate 都会 ENOSPC**（元数据也要空间）
- 节点"全军覆没"告警先查默认路由再怀疑订阅（见 02/04 篇）

回到 [README](../README.md)
