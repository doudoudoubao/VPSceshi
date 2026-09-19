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

跑完会在 `./vpstest-result/` 下生成 **5 种格式**的同一份报告：

| 文件 | 用途 |
| :--- | :--- |
| `report-*.md` | 博客 / GitHub / Hexo / Typecho，Markdown 表格 |
| `report-*.bbcode` | 论坛（Discuz、hostloc、NodeSeek 等），BBCode 表格 |
| `report-*.html` | 独立网页，自带样式与深色模式，可直接上传静态托管 |
| `report-*.json` | 机器可读，方便二次处理 / 入库 / 做对比 |
| `report-*.txt` | 纯文本，贴哪都不会乱 |

同时会写一份 `latest.*` 方便脚本取用。发论坛直接 `cat vpstest-result/latest.bbcode` 全选复制即可。

📄 **示例报告**：[Markdown](docs/sample-report.md) ·
[BBCode](docs/sample-report.bbcode) ·
[HTML](docs/sample-report.html) ·
[JSON](docs/sample-report.json) ·
[TXT](docs/sample-report.txt)

---

## 测试内容

### 一、系统与硬件信息
CPU 型号 / 核心数 / 频率 / 缓存、AES-NI、硬件虚拟化（VT-x、AMD-V）、内存、Swap、
硬盘与文件系统、发行版、架构、内核、虚拟化架构（KVM / Xen / LXC / OpenVZ / Docker…）、
TCP 拥塞控制与队列算法（BBR / fq）、IPv4 / IPv6 双栈、负载与运行时长。

### 二、CPU 性能
- `sysbench` 单核 / 多核 events/s，附多核扩展比
- `7-Zip` 压缩综合 MIPS（系统自带时）
- `OpenSSL` AES-256-CBC 吞吐（看 AES-NI 实际效果）
- `Geekbench 6` 单核 / 多核（`--geekbench` 开启，会上传结果并给出公开链接）
- 没有 sysbench 时自动退化为内置素数基准，保证有分可比

### 三、内存性能
`sysbench` 顺序读 / 写带宽；无 sysbench 时用 tmpfs + `dd` 兜底。

### 四、磁盘 I/O
- `dd` 顺序读写：1M×1000（两轮）+ 128K×8000，优先走 `oflag=direct`
- `fio` 随机混合读写：4k / 64k / 512k / 1m，iodepth=64，分别给出 MB/s 与 IOPS

### 五、IP 质量体检
- 基础画像：ASN、归属组织、ISP、地理位置、PTR 反解、时区
- 类型判定：IDC / 代理 / VPN / Tor / 滥用记录 / 爬虫、ASN 类型、注册公司
- 风险信誉：Scamalytics 欺诈分、AbuseIPDB 滥用置信度、Cloudflare 接入 POP
- 邮件黑名单：Spamhaus、SpamCop、Barracuda、SORBS、PSBL、CBL、UCEPROTECT 等 10 个 DNSBL
- 出站端口：TCP 25 / 465 / 587（能不能发信），以及 Google、GitHub、npm、Docker Hub 可达性

### 六、流媒体 / AI 解锁（IPv4 与 IPv6 分别测）
Netflix（区分「仅自制剧」）、Disney+、YouTube Premium（附 CDN 节点）、Amazon Prime Video、
Max(HBO Max)、Paramount+、DAZN、Spotify、TikTok、Steam 货币区、
ChatGPT、Google Gemini、Claude AI、巴哈姆特動畫瘋、AbemaTV、DMM、Hulu 日本、
TVB Anywhere+、Bilibili 港澳台 / 台湾限定、维基百科、Google 搜索。
解锁的服务会一并给出**区域代码**，最后统计通过率。

### 七、延迟与丢包
国内三网 + 教育网共 10 个节点（北京 / 上海 / 广州 × 电信 / 联通 / 移动），
另有香港、日本、新加坡、韩国、台湾、美西、美东、德国、英国等全球节点，给出平均延迟与丢包率。

### 八、网络测速
Ookla 官方 Speedtest CLI。先跑一次就近节点，再按 `--speedtest` 选择：
国内三网 10 个节点 / 国际 9 个节点 / 全部。节点 ID 动态检索，失效时回退到内置 ID。
下载、上传、延迟、抖动全都记录。

### 九、三网回程路由
`nexttrace` 追踪 9 个三网目标（追不到时自动回退 `mtr` / `traceroute` / `tracepath`），
并自动识别线路类型：**CN2 GIA、电信 163、联通 A 网 CUII (9929)、联通 169 (4837)、移动 CMIN2、移动 CMI**。
完整原始输出收进报告的折叠块里。

### 十、综合评分
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
    --full              完整模式，含 Geekbench 与国内+国际全测速
    --speedtest <模式>  cn | global | all | off（默认 cn）
    --geekbench         启用 Geekbench 6 跑分
    --show-ip           报告里显示完整出口 IP（默认部分遮蔽）
    --no-color          关闭彩色输出
-q, --quiet             安静模式，只输出报告路径
-h, --help / -v, --version
```

可用模块名：`cpu` `memory` `disk` `ipquality` `unlock` `ping` `speedtest` `route`

### 常用组合

```bash
# 只看解锁和 IP 质量（最快，一两分钟）
bash vpstest.sh --only unlock,ipquality

# 流量敏感，不跑测速
bash vpstest.sh --speedtest off

# 全量拉满（含 Geekbench + 国内国际全测速，半小时起步）
bash vpstest.sh --full -n "我的小鸡"

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
- **流量消耗**：测速是大头，每个节点 100–500MB。国内 10 节点大约 2–5GB。
  流量敏感请用 `--speedtest off` 或 `--fast`。
- **耗时**：默认约 10–20 分钟；`--fast` 约 5 分钟；`--full` 30 分钟以上。
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
│   ├── 00_core.sh          # 日志、结果存储、通用函数
│   ├── 10_deps.sh          # 依赖检测与安装、二进制下载
│   ├── 20_sysinfo.sh       # 系统与硬件信息
│   ├── 30_cpu.sh           # CPU 性能（sysbench / 7z / openssl / Geekbench）
│   ├── 31_memory.sh        # 内存性能
│   ├── 32_disk.sh          # 磁盘 I/O（dd + fio）
│   ├── 40_ipinfo.sh        # 出口 IP / ASN / 双栈
│   ├── 41_ipquality.sh     # IP 质量体检
│   ├── 50_unlock.sh        # 流媒体 / AI 解锁
│   ├── 60_speedtest.sh     # Speedtest 测速
│   ├── 61_ping.sh          # 延迟丢包
│   ├── 62_route.sh         # 回程路由
│   ├── 65_score.sh         # 综合评分
│   ├── 70_report_md.sh     # Markdown 报告
│   ├── 71_report_bbcode.sh # BBCode 报告
│   ├── 72_report_html.sh   # HTML 报告
│   ├── 73_report_json.sh   # JSON / TXT 报告
│   └── 90_main.sh          # 参数解析与主流程
├── tests/gen_sample.sh     # 用样例数据跑通全部报告路径并校验
└── docs/sample-report.*    # 示例报告
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
