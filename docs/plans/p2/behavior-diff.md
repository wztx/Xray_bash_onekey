# P2 Go vs Bash 行为差异清单

口径：**Go 对齐 bash，除非真的做不到**。不动 `install.sh`；不静默删除安全闸。
每项标注改动层：CLI 校验 / 生成逻辑 / 安装落地。

| ID | 场景 | 差异 | 分类 | 改动层 | 结论 |
|----|------|------|------|--------|------|
| G1 | M3 Reality + ws | Go 原 `Generate` 拒绝 `--transport ws`（`unsupported transport "ws" for mode reality`），bash 是 Reality 主 inbound + 附加 ws | 可改 | 生成逻辑 | 已改：Reality 保留 raw 主 inbound，ws/grpc/xhttp 以端口 +1 追加，等同 `reality_add_more` |
| G2 | M10 中转 | bash 装 Nginx Stream、写 `relay-stream.conf`、include 进主配置并起服务；Go 只有 `xray relay` 仅生成 conf | 可改 | 安装落地 | 已改：新增 `xray install --role relay`，复用 managed Nginx(stream) + `EnsureRelayInclude` + `Finalize` |
| G3 | M4 nginx 目录 | 曾怀疑 bash 用 `/usr/local/nginx`、Go 用 `/etc/idleleo/conf/nginx` | 不可改（实为无差异） | 无 | 已复核：两侧二进制目录都是 `/usr/local/nginx`，fragment 目录都是 `/etc/idleleo/conf/nginx`，fragment 文件集合一致；Go 仅多一个 `/etc/idleleo/v1/nginx.json` 元数据。不改 |
| G4 | D3 重复安装 | Go 原在配置存在时非零退出；bash 默认保留配置并幂等接管 | 可改 | 安装落地 + CLI 校验 | 已改：默认保留并告警；`--keep-config` 显式保留、`--rewrite-config` 显式覆盖；保留时仍生成 fragments |
| G5 | M2 CLI 形态 | bash 语义是 `--mode reality --nginx-bin`，Go 用 `--mode reality-nginx` | 可改（兼容别名） | CLI 校验 | 已改：`--mode reality --nginx-bin` 自动映射为 `reality-nginx`，原形态不变 |
| G6 | M9 监听 / M5–M7 `--binary` | 测试 argv 缺参或未显式监听 | 测试侧问题 | 测试 argv | 已改测试：补 `--binary`；M9 显式 `--listen 0.0.0.0 --allow-non-loopback` |
| G7 | 安全闸 | Go 的 loopback 监听保护、配置覆盖保护、容器写入确认 | 需拍板（仅在必须动时） | — | 均未删除。M9 通过显式参数放行；D3 通过 `--rewrite-config` 才覆盖；relay 保留混合安装拒绝 |
| G8 | M10 relay 文件集合 | Go relay 角色多写 `00-xray.conf`/`03-isolate.conf` 占位，主配置凭空 include 两个不存在的文件；bash relay 只有 `relay-stream.conf` | 可改 | 安装落地 | 已改：`InstallSpec.RelayOnly` 控制占位创建；`RewriteMainConfig` 的 Stream 分支仅节点模式 include；M10 两侧文件集合一致 |
| G9 | 附加传输端口 | Go 用 `base+1` 硬偏移，不探测占用、不排除 bash 保留端口 | 可改 | 生成逻辑 | 已改：ws/gRPC 10000–10999、xHTTP 11000–11999 升序候选 + bind 探测 + 保留端口排除 + `--ws-port/--grpc-port/--xhttp-port` 覆盖；65535 不回绕 |
| G10 | TLS 回环端口 | Go TLS 模式回环 inbound 与 Nginx 共用公网端口，重启必 `EADDRINUSE` | 可改 | 生成逻辑 | 已改：回环 inbound 取传输端口池，Nginx 独占公网端口；share 仍用公网端口 |
| G11 | 配置编辑能力 | bash 靠菜单改配置，无配置级自检、patch 语义与回滚 | 可改（Go 领先） | CLI + 生成 + 安装落地 | 已新增 `xray config edit`（规格 `interactive-config-editing-discussion.md` v1.0）：patch、自检、备份、回滚、二次确认、`--dry-run`/`--no-restart`/`--json` |

## 需拍板 / 仍保留

- 目前无“必须动安全闸才能对齐”的项，故无待拍板项。
- Bash 侧重复安装有一个已观测问题（非 Go 差异）：在服务运行中对已安装节点执行
  “保留配置重新安装”，`port_exist_check` 把自己的 443 判为被占用并回滚
  （`is_project_service_pid` 未识别到本项目进程，具体成因待 bash 侧单独排查）。
  P2 第 2 轮因此在两侧先停 `xray`/`nginx` 再重装，只验证“配置幂等”，
  不把该问题算作通过。是否修 bash 该守卫需另立需求。
- M8（ACME）仍为 HARNESS-BLOCKED：Pebble HTTP-01/TLS-ALPN 在容器网络内的解析方案未定，与本次差异无关。
- Go 不提供 bash 的“重新进入交互菜单改配置”流程；D3 只对齐“重复安装默认保留配置”的结果，不复制交互体验。若要求交互等价，需另立需求。

## 测试侧修正（不是 Go 缺陷）

- `collect/l4.sh`：macOS bash 3.2 在 `set -u` 下展开空数组 `"${EXTRA[@]}"` 报
  `unbound variable`，导致两侧 L4 都记失败。改为 `${EXTRA[@]+"${EXTRA[@]}"}`。
- `collect/idempotency.sh`：bash 重装会按设计新建
  `/etc/idleleo/backup/reinstall-<ts>-<rand>/`，这是时间戳备份而非幂等漂移。
  L6 仍统计 `backupAddedCount`，但不把它计为 added/removed 失败。
- `drivers/bash_menu.exp` / `matrix.json`：菜单层级修正——安装向导为
  `主菜单 1 > 安装向导 1(Reality) > 2(标准)/3(+传输)`；M2 用 `1>1>1`，
  M3 用 `1>1>3`。M10 第 2 轮补公网 IP 提示；M3 补 ws 端口/路径提示；
  menu 型入口重装后会回到管理菜单，第 2 轮改为发 `0` 正常退出（不再 `exit 124`）。
- `collect/l4.sh` + `collect/client_config.py`：Reality 的附加传输（ws 等）
  是 security=none 的独立 inbound，探测必须用 inbound 端口且不能套 Reality 设置；
  M3 的 ws 探测按此修正。Reality raw 仍走公网 443。
- `run_p2_matrix.sh`：M10 的 origin 容器改为在安装前启动。Nginx 在加载配置时解析
  后端域名，若 origin 尚未运行，`origin.example.com` 会解析到公网地址，导致
  “Empty reply from server”（两侧同样失败，与 Go/bash 差异无关）。

## 安装落地补强（Go）

- `nginx.InstalledArtifact()`：重复安装/重装时先读取已安装的 managed Nginx
  元数据并校验二进制，命中则跳过 artifact 下载；`nginx.Install` 的
  “已安装同 build” 快路径不再要求下载数据。避免第 2 轮因网络抖动重新下载
  整个 Nginx 包而失败（M10 第 2 轮、M5/M6 曾触发）。
- `nginx` 下载重试：bash 用 `curl --retry 2`（无整体超时），Go 原为单次 60s。
  已改为整体 300s、失败重试 2 次，仅对网络错误重试，摘要/大小校验不重试。

## 证据与验证

- G1：`go test ./internal/xraycfg -run RealitySingleTransport`；P2 M3 两侧 L2/L4。
- G2：`go test ./internal/deploy -run Relay`；P2 M10 两侧 L1–L4（客户端经中转容器回源）。
- G3：P2 M4 manifest 中 nginx 目录/权限对比。
- G4/G5：`go test ./internal/deploy`；P2 所有场景第 2 轮 rc=0、L6 无漂移；M2 两种 CLI 形态 generate 等价。
- G8：M10 两侧 `/etc/idleleo/conf/nginx` 文件集合一致（仅 `nginx`、`nginx.default`、`relay-stream.conf`），`nginx -t` 通过，L4 回源与 L6 幂等通过。
- G9：`go test ./internal/xraycfg -run Port`；第三方占用 10000 时自动选 10001 且输出 warning；M3/M7 两侧端口行为对齐。
- G10：`go test ./internal/xraycfg`；M4/M7 两侧 rc/L4/幂等通过，TLS 场景重启成功。
- G11：`go test ./internal/xraycfg ./internal/deploy`；P2 E1/E2 均 PASS（`evidence/step3-edit2/p2/install-matrix.md`）。
- 全量矩阵：`tests/e2e-diff/evidence/<run-id>/p2/install-matrix.md`。
