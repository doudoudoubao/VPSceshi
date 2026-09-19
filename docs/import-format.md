# 去程数据导入格式

## 为什么去程要导入

「去程」= 国内节点访问 VPS 的方向。这个方向的延迟和路由**只能从国内探针发起**，
VPS 自己没法测（VPS 上 ping 国内测到的是往返 RTT，走的是回程路由，跟去程可能完全是两条路）。

所以第 3、4、5 章（去程延迟 / 去程路由 / 去程 MTR）的数据得先在
[itdog.cn](https://www.itdog.cn/)、[ping.pe](https://ping.pe/)、
[IPIP 路由测试](https://tools.ipip.net/traceroute.php) 这类国内探针平台上测好，
整理成下面的格式喂给脚本。

不导入也能跑，对应章节会保留标题并写明「本次未取得有效数据」——
跟测评站的做法一致，不会凭空编数据。

---

## 1. 去程延迟：`--import-ping <文件.csv>`

四列 CSV，逗号分隔，`#` 开头是注释：

```
节点名,运营商,省份/地区,延迟ms
广州电信,电信,广东,32.4
杭州联通,联通,浙江,48.6
乌鲁木齐移动,移动,新疆,108.4
北京教育网,教育网,北京,88.2
```

- **运营商**：写 `电信` / `联通` / `移动` / `教育网`，脚本会归一成「中国电信」等
- **省份/地区**：用来自动归大区（华东 / 华北 / 华南 / 华中 / 西北 / 西南 / 东北）
- **延迟**：纯数字，单位 ms。非数字的行会被当作无效样本跳过（超时节点直接别写进来）

脚本会自动算出：
- 分运营商：样本数、平均 / 最低 / 最高延迟，以及最快和最慢的节点名
- 分大区：样本数、平均 / 最低 / 最高延迟
- 整体：样本总数与平均延迟

完整示例见 [`examples/inbound-ping.csv`](../examples/inbound-ping.csv)。

---

## 2. 去程路由：`--import-route <文件.txt>`

每个探针节点一段，段首用 `=== 节点名 ===` 分隔，段内直接粘贴 traceroute 原文：

```
=== 广东广州电信 ===
traceroute to 154.31.112.5, 30 hops max
 1  183.59.4.1        1.2 ms   AS4134  中国 广东 广州 电信
 2  202.97.94.153     2.8 ms   AS4134  中国 广东 广州 电信
 3  59.43.130.77      3.4 ms   AS4809  中国 广东 广州 电信 CN2
 4  154.31.112.5     13.0 ms   AS3335  中国 香港 DMIT

=== 浙江杭州联通 ===
traceroute to 154.31.112.5, 30 hops max
 1  115.204.0.1       1.1 ms   AS4837  中国 浙江 杭州 联通
 2  219.158.3.65     22.7 ms   AS4837  中国 上海 联通
 3  154.31.112.5     48.2 ms   AS3335  中国 香港 DMIT
```

脚本会从每段里识别线路类型，并汇总出一句去程结论。能识别的骨干：

| 类型 | 识别依据 |
| :--- | :--- |
| 电信 CN2 GIA | `59.43.*` / AS4809 |
| 电信 163 | `202.97.*` / AS4134 |
| 联通 A网 CUII | AS9929 / `218.105.*` / `218.241.*` |
| 联通 169 | AS4837 / `219.158.*` |
| 移动 CMIN2 | AS58807 / `223.118.*` |
| 移动 CMI | AS58453 / `223.120.*` |
| 移动 CMNET | AS9808 / AS56048 |
| NTT | AS2914 / `129.250.*` |
| Lumen/Level3 | AS3356 / `4.68.*` / `4.69.*` |
| Cogent | AS174 / `154.54.*` |
| HE.net | AS6939 |
| Arelion/Telia | AS1299 |
| GTT | AS3257 |
| TATA | AS6453 |
| Singtel | AS7473 |
| Telstra Global | AS4637 |
| PCCW | AS3491 |

原文会原样收进报告第十二章「原始结果归档」的折叠块里。

完整示例见 [`examples/inbound-route.txt`](../examples/inbound-route.txt)。

---

## 3. 去程 MTR：`--import-mtr <文件.txt>`

没有固定格式，整个文件原样收进「原始结果归档」。不提供时第五章标注为
「本次未取得有效去程 MTR 数据，丢包与抖动未评估」。

> 注意：**回程** MTR（VPS → 国内，含逐跳丢包与抖动）是脚本自动测的，
> 用的是本机 `mtr`，结果在第六章「回程网络质量」里，不需要导入。

---

## 4. 配置核对：`--config <文件.conf>`

`KEY=VALUE` 格式，`#` 开头是注释。所有字段都可以单独用命令行参数覆盖：

```ini
NAME=DMIT HKG.AN5.EB.Tiny      # 报告标题
VENDOR=DMIT                    # 商家
PLAN=HKG.AN5.EB.Tiny           # 套餐名
DC=中国香港 HKG                 # 机房
LINE=三网优化 / 回程 CN2 GIA    # 线路宣传
CPU=1                          # 宣传 CPU 核数
RAM=1GB                        # 宣传内存
DISK=20GB                      # 宣传硬盘
TRAFFIC=1TB                    # 月流量
BANDWIDTH=1Gbps                # 带宽
IPV4=1                         # IPv4 数量
IPV6=1                         # IPv6 数量
PRICE=9.90                     # 价格（纯数字）
CURRENCY=AUD                   # 币种
CYCLE=月付                     # 付费周期
```

脚本会把宣传值和实测值并排放进第 1 章的核对表，自动标 `✅ 相符` / `⚠️ 略低` / `❌ 不符`
（实测 ≥ 宣传值 95% 算相符，≥ 80% 算略低）。`TRAFFIC` 写成 `1TB` 或 `500GB` 这种带单位的形式，
第 11 章才能算出流量单价。

完整示例见 [`examples/vps.conf`](../examples/vps.conf)。

---

## 一起用

```bash
bash vpstest.sh \
  -c examples/vps.conf \
  --import-ping  examples/inbound-ping.csv \
  --import-route examples/inbound-route.txt \
  --import-mtr   my-mtr.txt \
  --iperf
```
