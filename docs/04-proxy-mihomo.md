# 04 · mihomo 代理注入

目标：路由器上跑 mihomo，给宿舍网提供代理（显式端口 + 可选透明代理），并有**自动节点轮换**。

## 部署形态：裸二进制（不要 Docker！）

> 🔴 教训：小米的 Docker 数据分区只有 ~190MB，拉一个镜像直接撑爆、分区变只读、连累整机。
> mihomo 单二进制 + 配置文件放 `/data`，用 `start-stop-daemon -S -b` 脱离会话拉起，稳得多。

```
/data/proxy/
  mihomo            # arm64 二进制（GitHub Release）
  config.yaml       # 订阅生成的配置
  geoip.metadb
  start.sh / stop.sh / guard.sh / rotate.sh
  cache.db          # mihomo 自身状态
```

## 显式代理 vs 透明代理

| 方式 | 优点 | 缺点 |
|---|---|---|
| 显式端口（7890） | 零风险，设备按需配 | 每台设备要设置 |
| TCP REDIRECT | 局域网无感 | **TPROXY 在该内核上不可用**；要动 iptables；排障复杂 |

实测结论：**TPROXY 在这台机器上失败，TCP REDIRECT 可用**。日常只用显式端口（够用、零维护），
透明模式留一个开关文件（存在才启用 iptables 规则），默认关。

## 节点轮换 rotate.sh 的设计

```sh
# 触发：显式代理连续失败（cron 每 2 分钟）
# 1) 并行测出全部候选节点的延迟（只测非 hysteria2 —— 校园网封 UDP，hy2 必死）
# 2) 延迟最优者 PUT 回控制器，再真实流量验证
# 3) 全军覆没 → 记日志 + 还原，不瞎切
```

要点：

- **候选解析要剔除订阅里的信息行**（"剩余流量/套餐到期"等伪节点）和 hysteria2
  ——剔除逻辑对 `type` 值要先剥引号再比较，否则**静默失效**（实测候选 69 而非 52）
- 每次"切节点"后必须用**真实流量**验证（generate_204），控制器自测延迟 ≠ 能用
- 全挂时先查[默认路由](02-wisp-relay-nat.md)——整机没网时节点探测必然全失败

## 🔴 urltest 组被信息节点污染（隐蔽坑）

订阅把"剩余流量：xx GB"这类**信息伪节点排在列表最前**。`url-test` 组在节点尚无延迟数据时
默认选第一项 → 组永远先落在假节点上，轮换器跟着误报。

修法（mihomo ≥1.14）：给自动组加排除正则——

```yaml
proxy-groups:
  - name: "自动选择"
    type: url-test
    ...
    exclude-filter: "剩余流量|重置剩余|套餐到期|过期|官网"
  - name: "故障转移"
    type: fallback
    ...
    exclude-filter: "剩余流量|重置剩余|套餐到期|过期|官网"
```

改配置的标准安全流程：

```
备份 → sed 插入 → 断言插入条数 → mihomo -t 试测 →
PUT /configs?force=true 热重载（不断代理）→ 还原手工选点 → 同步一份到 last-good 备份
```

## 验证

```sh
curl -x http://127.0.0.1:7890 -o /dev/null -w '%{http_code} %{time_total}s\n' \
     https://www.google.com/generate_204     # 204 且 <1s
```

下一步：[05 · TP-Link 有线回程子路由](05-tplink-subrouter.md)
