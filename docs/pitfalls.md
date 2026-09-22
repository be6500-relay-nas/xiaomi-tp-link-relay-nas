# 大坑速查表（跨主题）

> 全部实战踩过。按"值多少时间"排序——前几条都以小时计。

## 最高危（会失联/变砖级）

| 坑 | 正确姿势 |
|---|---|
| 双上行抢默认路由 | `ip route` 只允许一条 `dev wl12`；有线侧 `defaultroute=0` + `proto=none` |
| /tmp 堆满 → OOM → WiFi 消失重启循环 | available 红线 50MB；解压即删包；缓存设上限 |
| TP-Link 持久化 | 只有白名单文件能 `config.sh save`；**绝跑 `firstboot`**；落盘必 `diff` 校验 |
| 先关无线 STA 再插回程网线 | 小米 br-lan 无 STP，顺序反了 = 二层环广播风暴 |
| 5G 信道改了变孤岛 | 信道同时服务"有线挂→自动恢复无线回程"的 STA，钉死不动 |
| 在中继 STA 上 `iw scan` | 单频 STA 扫描 = 强制断链；要看邻居 AP 用另一台独立射频的机器 |
| Docker 撑爆数据分区 | 分区仅 ~190MB；一律裸二进制 + `/data` |

## 高频坑（每次操作都会遇到）

| 坑 | 正确姿势 |
|---|---|
| paramiko 5.x 连老 dropbear 失败 | 锁 `paramiko==3.5.1` |
| TP-Link busybox：无 base64/diff/stat/ sort -hr | 文件走 FTP 中转或 b64 分段 + **md5 断言**；属主用 `ls -ldn` |
| 小米 busybox：无 diff、PATH 不含 cwd | `./binary` 调用；比对用 grep/cmp |
| 小米 `iw station dump` 返回空 | 用 `brctl showmacs` + `iwconfig` + `dmesg` |
| 无 nohup/setsid | `start-stop-daemon -S -b -m -p <pid> -x <绝对路径>`（`-x` 用绝对路径，避免误杀同名） |
| alist 只快照 data.db | WAL 里才是配置；整目录 tar，data.db <32KB 即空库 |
| rclone serve webdav 默认只读 | `--vfs-cache-mode writes` + 缓存上限 |
| ntfs-3g uid 参数不进 /proc/mounts | 挂载判据用 `ls -ldn` 属主，别用 /proc/mounts |
| ntfs-3g root 属主 → FTP utime 550 | `uid=55,gid=55` 挂载（uid=FTP 会话映射的系统用户） |
| 体检被本机系统代理污染 | 强制 `ProxyHandler({})` 直连 |
| 时钟漂移误判日志 | 用 `date +%s` vs PC epoch 判偏差；日志判活用"条目是否还在变" |

## 行为准则（写给自己）

- 落盘操作**必带 diff/md5 校验**，失败必须**显式喊出来**（不能静默吞掉假装成功）
- 改配置前先备份到**持久分区**，笔记里记下备份路径与回滚命令
- 任何"自动修复"都要幂等 + 冷却时间，且先在模拟环境（杀进程清 /tmp）演练
- 弱信号问题的答案在物理层：先挪设备，再谈软件
- 涉及无线/回程拓扑的文件（rc.local 等）是**红线文件**——改动前评估最坏情况，改动后真实断电验证
