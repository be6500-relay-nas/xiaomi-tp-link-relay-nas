# 06 · alist NAS（网页 + WebDAV + FTP 三通道）

目标：USB 硬盘挂 TP-Link，小米上跑 alist 提供网页与多端 WebDAV，**重启断电全自愈**。

## 架构

```
客户端 ──WebUI/WebDAV──▶ alist(:5244) ──WebDAV──▶ rclone(:5245) ──FTP──▶ TP-Link pure-ftpd ──▶ NTFS 盘
```

为什么要三层？alist 需要一个"存储后端"，选 FTP 直连 TP-Link 最稳（不走 SMB/STP 那些坑）；
rclone 做 WebDAV↔FTP 桥。牺牲一点延迟，换来每层都可独立重启、独立升级。

## 关键配置与坑（每个都实测踩过）

### 1) ntfs-3g 必须按 FTP 用户的 uid 挂载

pure-ftpd 会话（虚拟用户映射到系统 uid 55）对 root 属主的文件 **utime 被拒** →
rclone 上传在 `SetModTime` 阶段全挂（报 550）——而且数据其实已写入，只是收尾失败，**极难排查**。

```sh
mount -t ntfs-3g -o umask=000,uid=55,gid=55 /dev/sda3 /home/ftp/volume3
# rc.local 里放一个每分钟循环：发现属主不对就重挂（覆盖开机+重插盘两种场景）
```

> ⚠️ 注意：ntfs-3g 的 uid 参数**不会出现在 /proc/mounts 里**（那里只有 FUSE 守护进程自己的
> user_id=0）。用 `/proc/mounts` 判断"是否已按 uid=55 挂载"会**每分钟误判重挂**（空闲瞬时空窗 =
> 偶发 FTP 抖动）。正确判据：`ls -ldn /home/ftp/volume3` 看属主数字是否 55。

### 2) rclone WebDAV 桥默认只读

`rclone serve webdav` 默认 VFS 只读，PUT 全 405。必须：

```sh
rclone serve webdav tpftp:/volume3 --addr 127.0.0.1:5245 \
    --vfs-cache-mode writes --vfs-cache-max-size 60M
```

缓存上限要给——它是吃内存的大户（见 08 篇 OOM）。

### 3) alist 的 SQLite 配置在 WAL 文件里

只拷 `data.db` = 恢复出**空库**（管理员/存储配置全丢）。快照必须**整目录 tar**：

```sh
cd /tmp/alist-data && tar -czf /tmp/alist-data.tar.gz data.db data.db-shm data.db-wal config.json
# 校验：data.db < 32KB 即空库；完整库 ≥128KB
```

### 4) 重启免疫：快照放 NAS 盘，看门狗从 FTP 拉回

```
TP-Link 盘上的 /volume3/.nasbin/  ←—— 唯一真相源（alist/rclone/tailscale 压缩包 + alist 数据快照）
        ▲ 每 2 分钟
小米 /etc/crontabs/patches/nas_watch.sh
  ├─ 检查进程/端口 → 不在则：FTP 拉包（重试 5 次）→ /tmp 解压 → 立即删压缩包 → start-stop-daemon 拉起
  ├─ alist 数据不存在 → 拉快照 tar → 解出
  └─ tailscale 未授权 → 自动重挂 up（等用户点一次授权，之后 /etc/tailscale 持久生效）
```

> 🔴 **解压后立即删安装包**是保命符：/tmp 是 RAM 盘，堆满 → OOM 杀 hostapd → WiFi 信号消失 →
> 看门狗重启循环（完整因果链见 08 篇）。

### 5) 部署链路（路由器内存盘方案）

- alist/rclone 单二进制，经代理下载到 /tmp，**立刻快照到 .nasbin**，从此与外网解耦
- 大文件在 PC 侧下载（PC 直连快得多），FTP 千兆推到 .nasbin——**路由器只当搬运工**
- busybox 没有 `diff`/`base64`（TP-Link），文件传输走 FTP 中转或 b64 分段 + md5 断言

## 速度天花板（别再调参了）

写 3.08 / 读 3.5 MB/s = **USB 2.0（480Mbps 理论）+ ntfs-3g FUSE 用户态 + MIPS 单核**的物理上限。
想翻倍只有两条路：TP-Link 刷 OpenWrt 用内核 ntfs3 驱动，或换带 USB 3.0 的主路由。

## 验收清单

```sh
# PC 侧一条龙（全部应 PASS）
curl alist 登录 → fs/list /nas → WebDAV PUT 1MB → GET 字节级比对 → DELETE
# 路由器侧
ls -la /home/ftp/volume3/     # 属主应为 55/55（ftp）
tail /tmp/nas_watch.log       # 看门狗动作日志
```

下一步：[07 · Tailscale 外网访问](07-tailscale.md)
