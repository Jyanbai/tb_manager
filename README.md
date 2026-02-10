# Traffic Balancer Evolution (v4.5 Stealth Edition) 🚀

![Language](https://img.shields.io/badge/Language-Bash-green.svg)
![Version](https://img.shields.io/badge/Version-4.5-blue.svg)
![License](https://img.shields.io/badge/License-MIT-orange.svg)

**Traffic Balancer (TB)** 是一款专为 Linux VPS/服务器设计的流量平衡管理工具。它通过模拟真实的下载行为，智能平衡网卡的进出流量比例（RX/TX Ratio），并具备深度伪装与抗检测特性，适合需要维护特定流量模型的场景。

## ✨ 核心特性 (v4.5 Update)

* **🛡️ 深度伪装 (Stealth Mode)**
    * **随机 User-Agent**：内置主流浏览器（Chrome/Firefox/Safari/iOS）指纹库，每次请求随机切换。
    * **Referer 欺骗**：随机模拟来自 Google, Bing, YouTube 等高信誉站点的跳转流量。
* **⏰ 潮汐调度 (Smart Schedule)**
    * **日间避峰 (09:00 - 01:00)**：自动降速至 50%，模拟正常用户的日间低频行为。
    * **夜间全速 (01:00 - 09:00)**：自动恢复全速，利用闲时流量。
* **🎲 模拟真人 (Random Interval)**
    * 支持随机休眠机制，打破机器脚本的固定频率特征。
* **🌍 多区域源**
    * 内置 **Global (国际)** 与 **CN (中国大陆)** 两套高速下载源，支持阿里、腾讯、Cloudflare 等大厂镜像。
* **📊 实时仪表盘**
    * 可视化监控下载/上传速率、实时比例、今日流量消耗及伪装状态。

---

## 🚀 快速开始
```
wget -O tb_manager.sh https://raw.githubusercontent.com/Jyanbai/tb_manager/main/tb_manager.sh && sed -i 's/\r$//' tb_manager.sh && chmod +x tb_manager.sh && echo "alias tb='bash $(pwd)/tb_manager.sh'" >> ~/.bashrc && source ~/.bashrc && ./tb_manager.sh
```
输入 tb 启动
## 🚀 分布开始
### 1. 一键安装与运行
在终端中执行以下命令即可下载并启动：

```bash
wget -O tb_manager.sh https://raw.githubusercontent.com/Jyanbai/tb_manager/main/tb_manager.sh && sed -i 's/\r$//' tb_manager.sh && chmod +x tb_manager.sh && ./tb_manager.sh
```
### 2. 设置快捷指令 (推荐)

为了方便日后管理，建议设置 tb 为快捷命令：
```Bash
echo "alias tb='bash $(pwd)/tb_manager.sh'" >> ~/.bashrc && source ~/.bashrc
```
设置完成后，只需在终端输入 tb 即可唤出管理菜单。
📖 使用指南

启动脚本后，你将看到如下交互式菜单：

    启动服务：以守护进程 (Daemon) 方式在后台运行。

    停止服务：安全终止进程并清理 PID 文件。

    重启服务：重新加载配置文件。

    实时监控：打开可视化仪表盘（按 0 退出监控，服务不会停止）。

    修改配置：进入配置向导，设置以下参数：

        目标比例 (Target Ratio)：如下载:上传 = 1.5:1。

        流量上限 (Daily Limit)：达到设定 GB 后自动停止。

        最高限速 (Max Speed)：限制最大消耗带宽。

        潮汐调度 (Smart Schedule)：开启/关闭日夜变速。

        下载源：选择国内或国外镜像源。

        运行策略：切换“持续模式”或“随机间隔模式”。

🛠️ 进阶开发与自定义

如果你需要根据特定环境调整脚本，请参考以下指南修改 tb_manager.sh 源文件。
1. 自定义下载源 (Download URLs)

脚本内置了 URLS_GLOBAL 和 URLS_CN 两个数组。你可以将自己的文件链接添加进去。

    建议：使用大厂的 Speedtest 文件或 Linux ISO 镜像，确保带宽充足且不易失效。

Bash

# 示例：在脚本约 45 行处添加新链接
URLS_GLOBAL=(
    "https://your-custom-url.com/1GB.test"
    ...
)

2. 自定义伪装头 (User-Agent)

在脚本的 UA_LIST 数组中添加新的 User-Agent 字符串，以模拟特定设备。
Bash

# 示例：添加一个 Android 设备的 UA
UA_LIST+=(
    "Mozilla/5.0 (Linux; Android 13; SM-S908B) AppleWebKit/537.36..."
)

3. 调整潮汐调度时间

搜索 run_daemon 函数中的逻辑，修改时间判断条件即可调整“夜间模式”的时段：
Bash

# 默认为 01:00 - 09:00
if [[ $CURRENT_HOUR -ge 1 && $CURRENT_HOUR -lt 9 ]]; then
    # ...
fi

📂 文件结构说明
文件名	说明
tb_manager.sh	核心脚本文件。
traffic_balancer.conf	配置文件（首次运行自动生成）。
traffic_balancer.log	运行日志（记录启动、停止、达标暂停等事件）。
/tmp/traffic_balancer.pid	进程锁文件。
/tmp/tb_status	实时状态数据（用于仪表盘显示）。
⚠️ 免责声明

        本工具仅供网络性能测试、流量模型研究及学术交流使用。

        请勿将本工具用于违反当地法律法规或云服务商服务条款 (ToS) 的用途。

        使用者需自行承担因不当使用（如滥用带宽）导致的服务器封禁或额外费用风险。

Copyright © 2026 Jyanbai. All rights reserved.
