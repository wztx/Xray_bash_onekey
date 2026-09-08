# Xray 管理脚本 — Reality / VLESS WebSocket/gRPC/xHTTP+TLS + Nginx

简体中文 | [English](/i18n/languages/en/README.md) | [Français](/i18n/languages/fr/README.md) | [Русский](/i18n/languages/ru/README.md) | [فارسی](/i18n/languages/fa/README.md) | [한국어](/i18n/languages/ko/README.md)

[![GitHub stars](https://img.shields.io/github/stars/hello-yunshu/Xray_bash_onekey?color=%230885ce)](https://github.com/hello-yunshu/Xray_bash_onekey/stargazers) [![GitHub forks](https://img.shields.io/github/forks/hello-yunshu/Xray_bash_onekey?color=%230885ce)](https://github.com/hello-yunshu/Xray_bash_onekey/network) [![GitHub issues](https://img.shields.io/github/issues/hello-yunshu/Xray_bash_onekey)](https://github.com/hello-yunshu/Xray_bash_onekey/issues)

> Thanks for non-commercial open source development authorization by JetBrains

## Features

* enter`idleleo`Open the Xray management menu to manage installation, services, security settings, etc.
* Use Qwen-MT-Plus AI to achieve accurate translation in multiple languages
* 支持 Reality 协议，建议搭配 Nginx 前置（脚本内可安装）
* Supports WebSocket, gRPC, xHTTP transmission, you can choose single transmission or`ws+gRPC+xHTTP`Enable both
* 支持 IPv4 / IPv6 双栈：安装时可自动检测公网出口能力，按域名 A/AAAA 记录独立校验并生成对应分享链接与 Clash 配置
* Built-in fail2ban protection (installable within script)
* Built-in Xray traffic statistics, traffic blocking, GeoIP/GeoSite rule update and regular update
* Supports scripts, Xray, Nginx and certificate updates, and provides backup and failure rollback for critical updates
* The current running configuration will be automatically backed up before reinstallation and mode switching, and the original configuration will be restored in case of failure.
* 重配置提供三条安全路径：保留配置重新部署、标准模板重建、模式切换
* use[@DuckSoft](https://github.com/DuckSoft) 的分享链接[提案](https://github.com/XTLS/Xray-core/issues/91)（beta），兼容 Qv2ray、V2rayN、V2rayNG
* use[XTLS](https://github.com/XTLS/Xray-core/issues/158) 提案，遵循 [UUIDv5](https://tools.ietf.org/html/rfc4122#section-4.3)Standard, supports custom string mapping to VLESS UUID
* Supports gRPC protocol:[使用 gRPC 协议](https://hey.run/posts/xrayjin-jie-wan-fa---shi-yong-grpcxie-yi)
* Supports Reality / ws/gRPC/xHTTP load balancing:
  - [部署 Reality 负载均衡](https://hey.run/posts/bushu-reality-balance)
  - [搭建后端负载均衡](https://hey.run/posts/xrayjin-jie-wan-fa---da-jian-hou-duan-fu-wu-qi-fu-zai-jun-heng)
* Reality + Nginx mode is enabled by default. SNI Guard: unknown SNI, empty SNI and exception TLS will not enter the Xray Reality backend. The isolation strategy (ssl_reject_handshake) is adopted by default. Advanced users can switch to self-built decoy site fallback or directly TCP Denied. This function is used to reduce active detection and misconfiguration exposure, and does not pursue perfect camouflage.

## 延伸阅读

* `idleleo`Naming backstory:[迷雾后的真容](https://github.com/hello-yunshu/Xray_bash_onekey/wiki/%E8%BF%B7%E9%9B%9C%E5%90%8E%E7%9A%84%E7%9C%9F%E5%AE%B9)
* Reality Installation Guide:[搭建 Xray Reality 服务器](https://hey.run/posts/da-jian-xray-reality-xie-yi-fu-wu-qi)
* Reality 协议风险：[Xray Reality 协议的风险](https://hey.run/posts/reality-xie-yi-de-feng-xian)
* Reality Accelerate server:[利用 Reality 协议"漏洞"加速服务器](https://hey.run/posts/use-reality)

## Telegram group

* Communication group:[点击加入](https://t.me/+48VSqv7xIIFmZDZl)

## Preparation

* An overseas server with public network IP
* Install Reality protocol: You need to prepare a target domain name that meets the requirements of Xray
* Install TLS version: You need to prepare the domain name and correctly configure A and/or AAAA records according to the available network of the server; for dual-stack environments, it is recommended to configure the correct A and AAAA at the same time. The script supports automatic detection of IPv4/IPv6 network capabilities. When dual stack is available, the corresponding client entry can be generated at the same time.
* read[Xray 官方文档](https://xtls.github.io), understand Reality, TLS, WebSocket, gRPC and Xray related concepts
* **Make sure curl is installed: CentOS user execution`yum install -y curl`;Debian/Ubuntu User execution`apt install -y curl`

## Quick installation

```bash
bash <(curl -fsSL https://github.com/hello-yunshu/Xray_bash_onekey/releases/latest/download/install.sh)
```

## Installation mode

| model | illustrate |
|------|------|
| Reality + Nginx | Recommended mode, you can attach ws/gRPC/xHTTP simple protocol as needed for load balancing |
| Nginx + TLS | Support ws/gRPC/xHTTP, automatically apply for and renew Let's Encrypt certificate |
| ws/gRPC/xHTTP ONLY | Independent inbound mode without TLS, mainly used in backend or load balancing scenarios |
| XTLS ONLY | Only used in specific scenarios such as traffic transfer |
| Docker | Xray, Nginx and the main script are pre-installed in the image |

Optional when installing ws/gRPC/xHTTP related modes`ws`、`gRPC`、`xHTTP`or`ws+gRPC+xHTTP`. The script will generate the corresponding port, path, sharing link and QR code respectively; Clash currently does not support xHTTP, and the script will prompt in the configuration output.

## Reconfiguration instructions

When the installed environment is installed again, the script will automatically back up the current running configuration and provide three reconfiguration paths:

| path | illustrate | limit |
|------|------|------|
| Preserve configuration redeployment | Keep custom routing/outbounds/DNS and multi-user configuration, modify only user-selected fields (ports, paths, UUID, Reality parameters, etc.) | Transmission structure changes (such as ws → gRPC) are not supported. If you need to change the transmission combination, please use the standard template to rebuild it. |
| Standard template reconstruction | Generate standard template configuration using current reusable parameters, custom routing/outbounds/DNS may be removed | It is not mandatory that the number of users remains unchanged |
| Mode switch | Switch to a different protocol mode (such as Reality → TLS). By default, only the main user UUID/email is reused. | Other users will not be automatically migrated and will be clearly prompted before switching. |

If any step in the reconfiguration process fails (configuration writing, service startup, health check, etc.), it will automatically roll back to the original backup configuration. The backup directory uses a unique timestamp to support multiple consecutive reconfigurations without conflicting with each other.

## Common commands

| operate | Order |
|------|------|
| Open the admin menu | `idleleo` |
| View help | `idleleo --help` |
| Install Reality mode | `idleleo --install-reality` |
| Install TLS mode | `idleleo --install-tls` |
| Install ws/gRPC/xHTTP ONLY | `idleleo --install-none` |
| View installation information | `idleleo --show` |
| update script | `idleleo --update` |
| Update Xray | `idleleo --xray-update` |
| Update Nginx | `idleleo --nginx-update` |
| Set Fail2ban | `idleleo --set-fail2ban` |
| Set up traffic blocking | `idleleo --traffic-blocker` |
| 查看端口实时流量 | `idleleo --port-traffic` |

## RillML Xray AI 运维助手

RillML（简称 Rill）为 Xray 提供本地自适应智能运维能力。

The built-in local AI operation and maintenance assistant monitors the health status of Xray/Nginx in real time, automatically diagnoses faults and gives treatment suggestions, without the need for external API. Main menu input`9` 或执行 `idleleo --rill-agent` 进入。

**核心能力**

* 监控：实时观测 Xray/Nginx 服务与配置状态
* 诊断：定位故障根因，附置信度建议（高 / 中 / 低 / 证据不足）
* Judgment: Automatically determine the fault type and give processing suggestions. The instructions clearly indicate that automatic processing is allowed or only suggestions are provided.
* 模式：智能判断 / 仅观察 / 安全停用，未开启自动修改前不会更改系统

**常用命令**

| operate | Order |
|------|------|
| 打开 AI 运维助手菜单 | `idleleo --rill-agent` |
| 安装或修复 AI 判断引擎 | `idleleo --rill-agent-install` |
| 查看 AI 判断状态 | `idleleo --rill-agent-status` |
| 运行 AI 故障诊断 | `idleleo --rill-agent-diagnose` |
| Verification AI judgment engine | `idleleo --rill-agent-verify` |
| 安全停用 AI 判断 | `idleleo --rill-agent-safe-disable` |
| 卸载 Rill AI 引擎 | `idleleo --rill-agent-uninstall` |

AI 判断引擎目前仍处于测试阶段，建议以诊断建议为主，默认不会自动修改系统。

## Docker 部署

支持使用 Docker 部署，镜像预装 Xray 和 Nginx，容器内可直接使用原脚本所有功能。详见 [Docker 部署指南](/docker/DOCKER.md)。

```bash
git clone https://github.com/hello-yunshu/Xray_bash_onekey.git
cd Xray_bash_onekey
docker compose up -d
docker attach xray-onekey
```

## AI Skill 部署

支持通过 AI 工具（如 Trae）自动部署 Xray，无需手动交互。详见 [Xray_bash_onekey_skill](https://github.com/hello-yunshu/Xray_bash_onekey_skill)。

传统方式需要 SSH 到服务器、运行安装脚本、逐个回答交互式问题；Skill 方式只需告诉 AI 你的需求，AI 会自动生成非交互式脚本并执行，直接返回 VLESS 链接。

**支持模式**：Reality / TLS / ws ONLY / XTLS ONLY

**使用方式**：在支持 Skill 的 AI 工具中直接说"帮我在服务器上搭建 Xray"，AI 会自动收集信息、生成脚本、执行部署并返回连接信息。

## 注意事项

* 不了解各项设置含义时，除必填项外请使用默认值（全程回车即可）
* Cloudflare 用户请在安装完成后再开启 CDN
* 本脚本需要 Linux 基础知识及计算机网络常识
* 支持 Debian 12+ / Ubuntu 24.04+ / CentOS Stream 10+，部分 CentOS 模板可能存在编译问题，建议遇到问题时更换系统
* 建议单服务器仅部署单个代理，使用默认 443 端口
* 自定义字符串映射至 UUIDv5 需要客户端支持
* 推荐在纯净环境下使用；新手请勿使用 CentOS
* 本程序依赖 Nginx，已通过 [LNMP](https://lnmp.org) 等脚本安装过 Nginx 的用户请注意潜在冲突
* xHTTP 分享链接适用于支持 xHTTP 的客户端；Clash 配置输出会跳过 xHTTP
* 请勿在未验证可用性前将本脚本用于生产环境
* 作者：云舒，仅提供有限支持

## 鸣谢

* 基于 [wulabing/V2Ray_ws-tls_bash_onekey](https://github.com/wulabing/V2Ray_ws-tls_bash_onekey) 开发
* TCP 加速脚本引用自 [ylx2016/Linux-NetSpeed](https://github.com/ylx2016/Linux-NetSpeed)

## 证书配置

**自定义证书**：将 crt 和 key 文件分别命名为 `xray.crt` 和 `xray.key`，放入 `/etc/idleleo/cert` 目录（目录不存在则先创建）。请注意证书权限及有效期，自定义证书过期后需自行续签。

**自动证书**：脚本支持自动生成 Let's Encrypt 证书（有效期 3 个月），理论上支持自动续签。

## 查看客户端配置

```bash
cat /etc/idleleo/info/xray_info.inf
```

## Xray 简介

* Xray 是一款优秀的开源网络代理工具，支持 Windows、macOS、Android、iOS、Linux 等全平台
* 本脚本为一键完整配置脚本，所有流程正常完成后，按输出结果设置客户端即可使用
* **强烈建议**全面了解程序的工作流程及原理

## 服务管理

| operate | Order |
|------|------|
| 启动 Xray | `systemctl start xray` |
| 停止 Xray | `systemctl stop xray` |
| 启动 Nginx | `systemctl start nginx` |
| 停止 Nginx | `systemctl stop nginx` |

## 相关目录

| 内容 | path |
|------|------|
| 主目录 | `/etc/idleleo` |
| Xray 配置 | `/etc/idleleo/conf/xray/config.json` |
| Nginx 配置 | `/etc/idleleo/conf/nginx/` |
| 安装信息 | `/etc/idleleo/conf/install_config.json` |
| 证书文件 | `/etc/idleleo/cert/xray.key`、`/etc/idleleo/cert/xray.crt` |
| 日志目录 | `/etc/idleleo/logs/`、`/var/log/xray/` |
| Nginx 安装目录 | `/usr/local/nginx` |
| 管理命令 | `/usr/bin/idleleo` |
