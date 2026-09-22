# 05 · TP-Link 有线回程子路由

第二台路由（TP-Link 企业款，QCA 芯片）做小米的**有线 AP 扩展 + USB NAS 底座**。

## 免拆机开 root

老款 TP-Link 企业固件（2017 年代）有一批公开的免拆机漏洞路径（管理页注入 → 调试开关 → 固定密码），
社区有完整工具链。要点：

- 全程不拆机、不刷第三方固件（保留原厂 NAS/FTP 组件）
- root 后第一件事：改 SSH 端口（如 33xxx）+ 强密码
- 持久化白名单极窄：只有 `rc.local`、`/etc/crontabs`、`passwd` 等少数文件能 `config.sh save` 落盘；
  其余 `/etc` 改动**重启即丢**（overlay 上层在内存）

## 有线回程（强烈推荐，不打无线环）

两种回程方式二选一：

| 方式 | 结论 |
|---|---|
| 无线桥接（STA 回程） | 能用，但两台 2.4G/5G 链路质量互相牵连，且配置错误会二层成环 |
| **有线回程（网线）** | 延迟 9ms → 0.94ms；拓扑稳定；**必须关掉无线 STA** 防环 |

有线回程的接线与配置：

```sh
# TP-Link LAN 口 ↔ 小米 LAN 口（小米四个口自适应识别为 LAN）
# TP-Link 侧：
uci set dhcp.lan.ignore='1'          # 关自己的 DHCP，统一由小米发租
uci commit dhcp
# 无线侧保持 AP 模式广播（与小米同名同密码 = 全屋一个 SSID 漫游）
```

🔴 **防环铁律**：小米 br-lan 未开 STP。**先关无线 STA，再插网线**；开机自愈脚本也要按此顺序判断：

```sh
# rc.local 内置循环（伪代码）
# 有线通( ping 小米) → 无线 STA 保持 off
# 有线断(持续 N 次)  → 自动恢复无线 STA 回程   # 断网兜底：网线被人踢掉也不失联
```

## 持久化铁律（TP-Link 特有）

- overlay 上层在 `/tmp`（RAM），**改 `/etc` 重启即丢**；只有 `config.sh save` 能落盘（写 jffs2）
- 落盘后 `diff /etc/rc.local /tmp/userconfig/etc/rc.local` 校验（有 ppp 警告属正常）
- 🔴 **绝不能跑 `config.sh firstboot`**（恢复出厂）
- 5G 信道一旦按中继需求选定，**永远别改**——它同时服务"有线挂了自动恢复无线回程"的 STA，改了变孤岛
- USB 盘能力看 `/proc/filesystems`：老固件只有 vfat/fuseblk → **NTFS（ntfs-3g）是唯一现实选项**

## 断电自愈验证

改完 rc.local 后必须真实断电重启验证两轮：SSH 恢复时间、AP 是否自动广播、NAS 挂载是否自动恢复（见 06 篇 uid 修复循环）。

下一步：[06 · alist NAS](06-nas-alist.md)
