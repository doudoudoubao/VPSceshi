# VPSceshi · VPS / 服务器一键全能测评

一条命令跑完服务器测评的全部项目，最后直接吐出**可以贴到博客和论坛的成品报告**。

对标 `servertest` 类测评站点的内容组织：系统硬件、CPU/内存/磁盘性能、IP 质量体检、
流媒体与 AI 解锁、三网延迟丢包、三网与国际测速、三网回程路由，外加一个综合评分。

---

## 一键运行

```bash
bash <(curl -sL https://github.com/doudoudoubao/VPSceshi/raw/main/dist/vpstest.sh)
```

带上机器名，报告标题会更好看：

```bash
bash <(curl -sL https://github.com/doudoudoubao/VPSceshi/raw/main/dist/vpstest.sh) -n "DMIT HKG.AN5.EB.Tiny"
```

或者克隆下来跑：

```bash
git clone https://github.com/doudoudoubao/VPSceshi.git
cd VPSceshi && bash vpstest.sh -n "我的小鸡"
```

跑完会在 `./vpstest-result/` 下生成 **6 种格式**的同一份报告：

| 文件 | 用途 |
| :--- | :--- |
| `report-*.md` | 博客 / GitHub / Hexo / Typecho，标准 Markdown |
| `report-*.nodeseek.md` | **[NodeSeek](https://www.nodeseek.com) 专用排版**，用论坛的标签页与折叠容器 |
| `report-*.bbcode` | Discuz 系论坛（hostloc 等），BBCode 表格 |
| `report-*.html` | 独立网页，自带样式与深色模式，可直接上传静态托管 |
| `report-*.json` | 机器可读，方便二次处理 / 入库 / 做对比 |
| `report-*.txt` | 纯文本，贴哪都不会乱 |

同时会写一份 `latest.*` 方便脚本取用。发帖直接 `cat vpstest-result/latest.nodeseek.md` 全选复制即可。

📄 **示例报告**：[Markdown](docs/sample-report.md) ·
[NodeSeek](docs/sample-report.nodeseek.md) ·
[BBCode](docs/sample-report.bbcode) ·
[HTML](docs/sample-report.html) ·
[JSON](docs/sample-report.json) ·
[TXT](docs/sample-report.txt)

### NodeSeek 排版说明

NodeSeek 用的是 markdown-it，**不是 Discuz 那套 BBCode**，而且开了
`markdown-it-container` 扩展。所以它单独出一份 `.nodeseek.md`，用上论坛特有的容器语法：

- **标签页**（`:::: tabs` / `::: tab-item`）——硬件、去程延迟、网络质量、测速、解锁、IP 质量
  这些多表格的章节收进标签页，一屏一个，不用滚半天
- **折叠**（`::: details`）——解锁完整清单和每一段路由 / MTR 原始输出各自折叠，点开哪段看哪段
- **评分条**——论坛没有 CSS，评分用 `████████░░░░` 方块字符画在表格里

这些容器语法只在 NodeSeek 生效，贴到 GitHub 或博客会变成裸文本，所以**没有**动原来的
`.md`，两份各管各的。万一论坛哪天改了关键字，改 `lib/74_report_nodeseek.sh`
顶部的 `NS_DETAILS_KW` / `NS_TABS_KW` / `NS_TAB_ITEM_KW` 三个变量就行，正文逻辑不用碰。
如果标签页渲染不出来，加 `--ns-no-tabs` 会退化成普通三级标题，内容一个不少。

---

## 报告结构（12 章）

### 一、基本配置核对
商家 / 套餐名 / 机房 / 线路宣传 / 月流量 / 带宽 / 价格（这些机器上探测不到，
由 `--config` 或命令行参数提供），并把**宣传配置和实测配置并排放**，
自动标 `✅ 相符` / `⚠️ 略低` / `❌ 不符`——CPU 核数、内存、硬盘、IPv4/IPv6 数量一眼看出有没有缩水。
容量会先统一单位再比，不会把 `1GB` 和 `984MB` 当成 1 对 984。

### 二、性能与硬件检测
- **系统硬件**：CPU 型号 / 核心数 / 频率 / 缓存、AES-NI、硬件虚拟化（VT-x、AMD-V）、
  内存总量 / 可用 / Buff-Cache、Swap、硬盘与文件系统、发行版、架构、内核、
  虚拟化类型（KVM / Xen / LXC / OpenVZ / Docker…）、TCP 拥塞控制与队列算法、双栈、负载、运行时长
- **CPU**：`sysbench` 单核 / 多核 + 多核扩展比、`7-Zip` MIPS、`OpenSSL` AES-256 吞吐、
  `Geekbench 6` 单核 / 多核 + **完整结果链接**（`--geekbench`）。无 sysbench 时退化为内置素数基准
- **内存**：`sysbench` 顺序读写带宽，无 sysbench 时 tmpfs + `dd` 兜底
- **磁盘**：`dd` 顺序读写（1M×1000 两轮 + 128K×8000，优先 `oflag=direct`）
  ＋ `fio` 随机混合读写 4k / 64k / 512k / 1m（iodepth=64，给出 MB/s 与 IOPS）

### 三、去程延迟测试（国内 → VPS）
分运营商汇总（样本数、平均 / 最低 / 最高、最快节点、最慢节点）＋
分大区汇总（**华东 / 华北 / 华南 / 华中 / 西北 / 西南 / 东北**）＋ 各探针节点明细。

> ⚠️ 去程只能由国内探针发起，VPS 自测不到。用 `--import-ping` 导入 itdog / ping.pe 的结果，
> 格式见 [导入格式说明](docs/import-format.md)。不导入则该章标注「本次未取得有效数据」。

### 四、去程路由测试（IPIP 探针）
每个探针节点的完整 traceroute ＋ 自动线路识别 ＋ 去程线路结论汇总。
用 `--import-route` 导入（段落以 `=== 节点名 ===` 分隔）。

### 五、去程 MTR
`--import-mtr` 导入；未提供时明确写「本次未取得有效去程 MTR 数据，丢包与抖动未评估」。

### 六、回程网络质量（NetQuality）
全部走公开免费 API（RIPEstat / RDAP / PeeringDB），不需要任何 key：
- **BGP 与注册信息**：BGP 前缀、Origin AS、网络组织、宣告前缀数、注册主体 Netname、
  注册地区、注册日期、最后修改日期、注册局 RIR（ARIN / RIPE / APNIC…）
- **上游与对等互联**：上游数量、下游数量、PeeringDB 名称 / 网络类型 / 覆盖范围
- **互联网交换点**：IXP 数量与各交换点端口速率
- **本地网络策略**：TCP 拥塞控制、队列调度、可用拥塞算法、IP 转发、MTU、IPv6 支持
- **回程 MTR**：VPS → 国内三网的逐跳**丢包率、平均 / 最优 / 最差延迟、抖动 StDev**（自动测，不用导入）

### 七、回程路由测试（NextTrace 三网）
`nexttrace` 追踪 10 个三网目标（广州/北京/上海电信、茂名/北京/上海/广州联通、
上海/深圳/北京移动），追不到时自动回退 `mtr` / `traceroute` / `tracepath`。
自动识别 **CN2 GIA、电信 163、联通 A网 CUII(9929)、联通 169(4837)、移动 CMIN2、移动 CMI、CMNET、
NTT、Lumen/Level3、Cogent、HE.net、Arelion/Telia、GTT、TATA、Singtel、Telstra、PCCW**，
并给出回程线路结论。

### 八、网络测速
- **国际节点带宽（iperf3）**：YABS 同款公共节点——新加坡 Leaseweb 10G、洛杉矶 Clouvider 10G、
  伦敦 Clouvider 10G、阿姆斯特丹 Eranium 100G、纽约 Leaseweb 10G（`--iperf` 开启）
- **Speedtest**：Ookla 官方 CLI，就近节点 ＋ 国内三网 10 节点 ＋ 国际 9 节点，
  节点 ID 动态检索、失效回退内置 ID，记录下载 / 上传 / 延迟 / 抖动。
  国内测速拿不到数据时明确标注「未取得有效数据」
- **回程延迟与丢包**：国内三网 + 教育网 10 节点，以及全球 9 个节点

### 九、流媒体与在线服务解锁（IPv4 / IPv6 分别测）
结果自动分成 **可用 / 不可用 / 失败待确认 / 难归类** 四组，解锁的服务附带**区域代码**。

- **流媒体 / 视频**：Netflix（区分「仅自制剧」）+ **优选 CDN**、Disney+、
  YouTube Premium + **CDN 节点**、Amazon Prime Video、Max(HBO Max)、Paramount+、DAZN、
  **Viu.com、Viu.TV、MyTVSuper、Now E**、TVB Anywhere+、巴哈姆特動畫瘋、
  Bilibili 港澳台 / 台湾限定、AbemaTV、DMM、Hulu 日本、**SonyLiv、iQiyi 海外版、
  SD Gundam G Generation Eternal**、TikTok
- **AI / 账号地区 / 其他**：ChatGPT、Google Gemini、Claude、Google 搜索无验证码、
  **Google Play 商店地区、Apple 地区、Bing 地区、OneTrust 地区**、Spotify 注册、
  Steam 货币区、**Reddit**、维基百科访问 + **可编辑性**
- **网络识别**：出口 ASN、归属组织、IPv4/IPv6 出口、所属前缀

### 十、IP 质量检测
- **原生 / 广播判定**：比对 RDAP 注册国与 GeoIP 定位国，给出判定 + 依据 + 前缀 + 注册主体 + RIR
- 基础画像：ASN、网络组织、识别位置、PTR、时区
- IP 类型：IDC / 代理 / VPN / Tor / 滥用记录 / 爬虫、ASN 类型、注册公司
- 风险评分：Scamalytics 欺诈分、AbuseIPDB 滥用置信度、Cloudflare 接入 POP
- **黑名单扫描**：10 个 DNSBL 分主流 / 次级两档，汇总成
  **有效数 / 正常 / 已标记 / 黑名单** 四个计数
- 出站端口：TCP 25 / 465 / 587，以及 Google、GitHub、npm、Docker Hub 可达性

### 十一、适用场景与购买建议
从实测数据推出**适合 / 不适合的场景**（每条都附依据）、价格与流量单价、
去程与回程线路分别的结论与使用建议，以及 **FAQ**：
原生还是广播、能否解锁港区流媒体、去程/回程走什么线路、性能够不够、适合谁买、数据会不会变。
没测到的项目不下结论。

### 十二、原始结果归档
测试时间戳、总耗时、采集工具与依赖情况，以及所有路由 / MTR 原始输出的集中折叠块。

### 综合评分
CPU 25 + 磁盘 20 + 网络带宽 25 + 国内延迟 15 + 解锁 10 + IP 质量 5 = 100 分，
给出 S / A / B / C / D 评级。HTML 报告里是带进度条的评分卡。

---

## 参数

```
-n, --name <名称>       报告标题用的机器名，如 "DMIT HKG.AN5.EB.Tiny"
-o, --output <目录>     报告输出目录（默认 ./vpstest-result）
-m, --only <模块,...>   只跑指定模块
-s, --skip <模块,...>   跳过指定模块
    --fast              快速模式，缩短时长、减少节点
    --full              完整模式，含 Geekbench + iperf3 + 全测速
    --speedtest <模式>  cn | global | all | off（默认 cn）
    --geekbench         启用 Geekbench 6 跑分
    --iperf             启用国际节点 iperf3 带宽测试
    --ns-no-tabs        NodeSeek 版不用标签页容器，退化成普通三级标题
    --no-deps           不自动安装依赖，只用系统现有工具
    --speedtest-full    测速跑满 10 个节点（默认 6 个）
    --route-full        回程路由跑满 10 个目标（默认 6 个）
    --show-ip           报告里显示完整出口 IP（默认部分遮蔽）
    --no-color          关闭彩色输出
-q, --quiet             安静模式，只输出报告路径
-h, --help / -v, --version
```

**配置核对（第 1 章）**：

```
-c, --config <文件>     从配置文件读取下列全部字段
    --vendor <商家>         --plan <套餐名>       --dc <机房>
    --line <线路宣传>       --cpu <核数>          --ram <内存>
    --disk <硬盘>           --traffic <月流量>    --bandwidth <带宽>
    --ipv4 <数量>           --ipv6 <数量>
    --price <价格>          --currency <币种，默认 AUD>
    --cycle <周期，默认「月付」>
```

**去程数据导入**（国内 → VPS 方向，VPS 自身测不到）：

```
    --import-ping <CSV>     去程延迟：节点名,运营商,省份,延迟ms
    --import-route <文本>   去程路由：段落以 "=== 节点名 ===" 分隔
    --import-mtr <文本>     去程 MTR 原始输出
```

不提供时对应章节保留并标注「本次未取得有效数据」。
详见 [导入格式说明](docs/import-format.md)，示例文件在 [`examples/`](examples/)。

可用模块名：`cpu` `memory` `disk` `ipquality` `netquality` `unlock` `ping`
`speedtest` `route` `mtr` `inbound` `iperf` `verdict`

### 常用组合

```bash
# 只看解锁和 IP 质量（最快，一两分钟）
bash vpstest.sh --only unlock,ipquality

# 流量敏感，不跑测速
bash vpstest.sh --speedtest off

# 带配置核对
bash vpstest.sh -c examples/vps.conf

# 全量拉满（Geekbench + iperf3 + 国内国际全测速，半小时起步）
bash vpstest.sh --full -c examples/vps.conf

# 配置核对 + 去程数据一起上，出完整 12 章报告
bash vpstest.sh -c examples/vps.conf \
  --import-ping  examples/inbound-ping.csv \
  --import-route examples/inbound-route.txt \
  --iperf

# 跳过路由（非 root 或 ICMP 被封时）
bash vpstest.sh --skip route
```

---

## 环境要求与注意事项

- **bash 4.0+**，Linux。支持 Debian / Ubuntu / CentOS / RHEL / Rocky / Alma / Alpine / Arch / openSUSE。
- **建议 root 运行**：自动装依赖、`dd` 直接 I/O、路由追踪发 ICMP 都需要。
  非 root 也能跑，相关项会自动降级或跳过，不会中断。
- 依赖（`curl` `wget` `bc` `jq` `sysbench` `fio` `ping` `dig` `tar`）会自动安装；
  装不上就走降级方案，缺什么会在报告的「依赖情况」里写明。
- **流量消耗**：测速是大头，Speedtest 每节点 100–500MB，默认 6 个节点约 1–3GB；
  `--speedtest-full` 跑满 10 个约 2–5GB；iperf3 每节点 1–3GB（默认不开，要 `--iperf`）。
  流量敏感请用 `--speedtest off` 或 `--fast`。
- **耗时**：默认约 10–15 分钟；`--fast` 约 4–6 分钟；`--full` 30 分钟以上。
  每一步的标题都会带上累计耗时（如 `[+3:24]`），卡住时一眼看得出卡了多久。
- **依赖是按需现装的**：只有 curl / bc / jq 在开头装，sysbench、fio、ping、dig、
  mtr、iperf3 都是对应模块真正要用时才装，装不上就走降级方案，不会堵在最前面。
  apt 被 `unattended-upgrades` 占着锁时最多等 60 秒就放弃；
  完全不想动系统就加 `--no-deps`。
- **「去程」为什么要导入**：去程是国内访问 VPS 的方向，只能从国内探针发起，
  VPS 上 ping 国内测到的是往返 RTT（走回程路由），跟去程可能是两条完全不同的路。
  所以第 3、4、5 章需要 `--import-*` 导入外部探针结果，不导入就如实标注未取得，不编数据。
- **隐私**：报告默认把出口 IP 遮蔽成 `1.2.*.*`，要完整 IP 加 `--show-ip`。
  报告只写在本地，脚本不会自动上传到任何地方——发不发、发哪里，你自己决定。
  注意报告里含有机器配置、IP 归属、路由路径等信息，公开前自己过一眼。
- 测试会调用 ipinfo、ip-api、Scamalytics、AbuseIPDB、Speedtest、各流媒体站点等第三方服务，
  这些服务本身可能限频或改接口，个别项目返回「待确认」属正常现象。

---

## 项目结构

```
VPSceshi/
├── vpstest.sh              # 开发入口，加载 lib/ 模块
├── build.sh                # 把 lib/ 打包成单文件
├── dist/vpstest.sh         # 一键单文件版（构建产物，curl 一条命令跑的就是它）
├── lib/
│   ├── 00_core.sh          # 日志、结果存储、未取得标记、通用函数
│   ├── 05_profile.sh       # ① 基本配置核对（宣传 vs 实测）
│   ├── 10_deps.sh          # 依赖检测与安装、二进制下载
│   ├── 20_sysinfo.sh       # ② 系统与硬件信息
│   ├── 30_cpu.sh           # ② CPU（sysbench / 7z / openssl / Geekbench）
│   ├── 31_memory.sh        # ② 内存性能
│   ├── 32_disk.sh          # ② 磁盘 I/O（dd + fio）
│   ├── 40_ipinfo.sh        # 出口 IP / ASN / 双栈
│   ├── 41_ipquality.sh     # ⑩ IP 质量 + 原生/广播判定 + 黑名单
│   ├── 42_netquality.sh    # ⑥ BGP/RDAP/PeeringDB 回程网络质量
│   ├── 50_unlock.sh        # ⑨ 流媒体 / AI 解锁（含分组）
│   ├── 60_speedtest.sh     # ⑧ Speedtest 测速
│   ├── 61_ping.sh          # ⑧ 回程延迟丢包
│   ├── 62_route.sh         # ⑦ 回程路由 + 线路识别
│   ├── 63_inbound.sh       # ③④⑤ 去程延迟/路由/MTR（导入与聚合）
│   ├── 64_mtr.sh           # ⑥ 回程 MTR（丢包 / 抖动）
│   ├── 65_score.sh         # 综合评分
│   ├── 66_iperf.sh         # ⑧ 国际节点 iperf3 带宽
│   ├── 67_verdict.sh       # ⑪ 适用场景 / 购买建议 / FAQ
│   ├── 70_report_md.sh     # Markdown 报告（博客）
│   ├── 71_report_bbcode.sh # BBCode 报告（Discuz 系）
│   ├── 72_report_html.sh   # HTML 报告
│   ├── 73_report_json.sh   # JSON / TXT 报告
│   ├── 74_report_nodeseek.sh # NodeSeek 专用排版（tabs / details 容器）
│   └── 90_main.sh          # 参数解析与主流程
├── tests/gen_sample.sh     # 用样例数据跑通全部报告路径并校验（64 项断言）
├── examples/               # 配置文件与去程导入的示例
└── docs/
    ├── import-format.md    # 去程数据与配置文件的格式说明
    └── sample-report.*     # 示例报告
```

### 二次开发

改完 `lib/` 下的模块后重新打包：

```bash
./build.sh --check          # 打包 + 语法检查
./tests/gen_sample.sh       # 用样例数据验证报告渲染
```

加一个新测试模块，照着现有模块写就行：用 `row_add <表名> <字段...>` 塞表格数据、
`kv_set <键> <值>` 塞单值，然后在对应的报告生成器里加一段 `md_table` / `bb_table` / `html_table`。

---

## 许可

MIT
