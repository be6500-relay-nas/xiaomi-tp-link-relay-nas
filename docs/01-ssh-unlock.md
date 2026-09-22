# 01 · SSH 解锁与固化（小米 BE6500 Pro / RD08）

目标：拿到 root SSH 并让它**跨固件升级、跨重启**都存活——后面所有改造的地基。

> ⚠️ 动手前：能备份的全备份。小米的分区（尤其 overlay/kernel）在动手前用 `dd` + `cat /proc/mtd` 全量导出一次，变砖时靠它救回来。

## 思路

小米路由器的 SSH 默认关闭。公开社区（如 xmir-patcher 一类工具）的通用套路：

1. **降级官方固件**到某个存在已知配置接口漏洞的版本（本项目用到 1.0.46）
   - 从官方渠道拿历史固件包，管理页"手动升级"刷入
   - 降级后管理密码会被重置为出厂
2. **用公开工具利用漏洞**注入临时的 SSH 访问（该工具链在 GitHub 上开源，搜索 `xmir-patcher`）
   - 工具会自动探测固件版本、选对应漏洞、写入临时 telnet/SSH 入口
3. **固化**——临时入口重启就没了，必须立刻做持久化：
   - `passwd` 改 root 密码（busybox 没有 `chpasswd`，用交互式 `passwd`；脚本化可用 paramiko pty）
   - dropbear 加自启动（写入会被官方机制保留的启动钩子/`rc.local`）
   - **换端口**（默认 22 会被校内扫描），例如 33xxx 高位
   - 关闭自动 OTA：`/etc/crontabs` 里的 `otapredownload` 相关任务禁用——固件自动升级会把洞补上、把你的固化清掉

## 固化后升回新固件

在 1.0.46 上完成固化后，可以再手动升级到当时的最新官方固件（本项目最终在 1.1.96）。
升级后逐项检查：

- [ ] SSH 仍通（新端口）
- [ ] `crontab -l` 自定义任务还在
- [ ] `/data` 下自己放的文件还在（`/data` 是持久分区，这是所有自部署资产的安家处）

## 验证

```sh
ssh -p <port> root@192.168.31.1   # 密码来自你自己的密码管理器
cat /proc/uptime
busybox | head -1                  # 认识一下这台机器的 busybox 能力边界
```

## 本阶段踩过的坑

| 坑 | 处理 |
|---|---|
| paramiko 5.x 握手失败 `no acceptable host key` | 锁 `paramiko==3.5.1`（老 dropbear 只认旧算法） |
| busybox 没有 `chpasswd` | paramiko pty + 交互式 `passwd` |
| 固件升级清掉自定义启动项 | 关自动 OTA + 每次升级后复查 crontab |
| `/etc` 大部分是 overlay，改了重启丢 | 持久资产放 `/data`；开机钩子写 `/etc/crontabs/patches/`（见 08 篇） |

下一步：[02 · WISP 中继 + NAT](02-wisp-relay-nat.md)
