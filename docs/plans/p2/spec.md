# P2 规格：M1–M10 安装矩阵全量差分（bash vs Go）

来源计划：`docs/plans/bash-vs-go-docker-differential-impl.md` §5。
**口径更新（2026-11-14，覆盖早期 D1–D4 推荐）**：凡 Go 与 bash 行为不一致处，**改 Go 对齐 bash**；
只有底层确实做不到的，才保留差异并在矩阵里列明证据。测试侧 argv/监听问题直接改测试，不算 Go 缺陷。
不改 bash 行为；不静默移除安全闸；需要动安全闸才能对齐的，单独列出待拍板。

EXPECTED-DIFF 机读策略不变：per-entry `owner` + `approved_by` + `expires`，pending = BLOCKER。
HARNESS-ERROR 只允许按规则重跑 1 次，环境问题不得判过。

## 1. 目标

1. 产出「Go vs bash 行为差异清单」，逐条分类：可改（改 Go）、不可改（附证据）、需拍板。
2. 按清单改 Go 对齐 bash，并用 P2 矩阵复跑验证 M1–M10 × 两侧 × 2 轮。
3. 产出 `evidence/<run-id>/p2/install-matrix.md`，含前后对比、ED、真实能力缺口。
4. 改动仅限 Go 代码、`tests/e2e-diff/**`、`docs/plans/**`；bash `install.sh` 不动。

## 2. 差异清单（初始，随实现更新）

| # | 差异 | 层级 | 分类 | 处理 |
|---|---|---|---|---|
| G1 | M3 Reality + ws：Go 直接拒绝 `--transport ws` | CLI 校验 / 生成 | 可改 | 放开 Reality 单传输；主 inbound 仍为 Reality raw，附加 ws/grpc/xhttp 走 Bash reality_add_more 拓扑 |
| G2 | M10 中转：bash 装 Nginx Stream 并起服务，Go 只生成 conf | 安装落地 | 可改 | 新增 Go relay 安装路径，落盘 `relay-stream.conf`、include 到 stream{}、启服务 |
| G3 | M4 Nginx 目录 | 安装落地 | 待证据 | 先对比两侧 manifest（bash 的 fragment 目录其实也是 `/etc/idleleo/conf/nginx`）；只有真实不一致才改 |
| G4 | 重复安装：Go 配置存在即 rc≠0，bash 保留并幂等接管 | 部署策略 | 可改 | 默认改为保留接管；`--keep-config`/`--rewrite-config` 保留为显式开关 |
| G5 | M2 `--mode reality-nginx` vs bash `--mode reality --nginx-bin` | CLI 形态 | 可改（别名） | 加兼容别名，不改变落盘语义 |
| G6 | M9 监听 / M5–M7 缺 `--binary` | 测试 argv | 改测试 | 已在 `matrix.json` 修正 |
| G7 | 安全闸（loopback 保护、覆盖保护） | 安全 | 需拍板 | M9 的 `--allow-non-loopback` 保留显式确认；G4 只改默认保留策略，不取消显式覆盖开关 |

## 3. 决策（按新口径重写）

### D1 M3 Reality + ws

- 结论：**可改**。Bash 的「Reality + ws」是 Reality raw 主 inbound + 一个附加 ws inbound，
  Go 的 multi 拓扑已具备该结构，限制只在 `xraycfg.Generate` 的 transport 白名单。
- 改法：Reality 模式接受 `ws|grpc|xhttp` 单传输；`buildInboundDefs` 生成 raw 主 + 单个附加传输；
  share URI 仍取 Reality 主 inbound。
- 验证：`xray generate` 产出两个 inbound；P2 M3 Go 侧安装成功且 reality/ws 都能连通。

### D2 M10 中转

- 结论：**可改**。Go 已有 `xraycfg.RelayConf`（与 bash `relay_render_stream_conf` 对齐）和
  managed Nginx 安装/服务能力，缺的是「安装入口」而非底层能力。
- 改法：为 `xray install` 增加 relay 角色（`--role relay --target H:P --listen-port N`），
  复用 managed Nginx（stream 模式）：写 `relay-stream.conf`、确保 `stream{}` include、启用 nginx。
  不改 bash。
- 验证：P2 M10 Go 侧安装 rc=0，nginx active，client 经 relay TCP 转发拿到 origin 内容。

### D3 重复安装

- 结论：**可改**。Bash 重复安装默认保留现有配置并幂等接管。
- 改法：`deploy.Install` 在配置已存在且未给显式开关时，默认按 KeepConfig 处理；
  `--rewrite-config` 仍显式重建，`--keep-config` 保持显式语义。
- 验证：P2 第 2 轮 Go rc=0，manifest 无增删，inbound/cron 无重复。

### D4 M9 监听

- 结论：**测试侧**。两侧默认都只监听 loopback；跨容器 L4 必须显式 0.0.0.0。
- 改法：bash 走菜单监听提示；Go 用 `--listen 0.0.0.0 --allow-non-loopback`。
  不改默认安全闸。

### D5 M4 Nginx 目录

- 结论：**先取证再定**。Bash 的 fragment 目录同样是 `/etc/idleleo/conf/nginx`；
  若 P2 证据显示只有 manifest 收录范围不同（如 bash 收录 `/usr/local/nginx` 二进制树），
  按采集口径对齐，不改安装路径；若确有配置落盘差异，再改 Go。

## 4. 实现范围（精确到文件）

| 文件 | 变更 |
|---|---|
| `internal/xraycfg/xraycfg.go` | Reality 接受单传输；`buildInboundDefs` 生成 raw 主 + 单附加传输 |
| `internal/xraycfg/xraycfg_test.go` | 新增 Reality single-transport 生成断言 |
| `internal/cli/xray.go` | relay 安装入口；M2 兼容别名；重复安装默认策略传递 |
| `internal/cli/flags.go` | relay 安装所需 flag 白名单 |
| `internal/deploy/deploy.go` | 默认 keep-config 语义 |
| `internal/deploy/relay.go` | relay 安装落地（managed Nginx stream + relay-stream.conf + include + 启服务） |
| `internal/nginx/install.go` | `EnsureRelayInclude`：主配置顶层 include 与用户 stream 冲突保护 |
| `internal/deploy/deploy_test.go` | 更新/新增默认接管与 relay 断言 |
| `tests/e2e-diff/matrix.json` | Go argv、已验证状态、能力缺口回收 |
| `tests/e2e-diff/drivers/*` | 场景应答与轮次（已扩展，按复跑修正） |
| `tests/e2e-diff/collect/*` | L5/L6 采集（已新增） |
| `tests/e2e-diff/run_p2_matrix.sh` | 全量复跑（已新增） |
| `tests/e2e-diff/compare/report.py` | 矩阵报告（已新增） |

## 5. 执行顺序

1. 出差异清单（第 2 节）并落 `p2/behavior-diff.md`。
2. 改 Go：G1 → G4 → G5 → G2；每项加/改单测。
3. 修测试侧 M9/M5–M7 argv。
4. 小样：M1（回归）、M3、M4、M10、M9 两侧两轮。
5. 全量 M1–M10 × 两侧 × 2 轮；生成 `install-matrix.md`。
6. 按主题提交：Go 对齐改动 / 测试驱动 / 报告与证据。

## 6. 判定与出口

- 原 capability gap 的 M3、M10 在 Go 侧能装出可连通环境。
- 重复安装两轮均 rc=0，无重复 inbound/cron。
- M1/M2/M4–M9 无新增未登记 BLOCKER；ED 具备 owner/approver/expires。
- 真实不可改项在矩阵中逐条给出证据与影响。
- `git status` 仅含 Go 源码/测试、`tests/e2e-diff/**`、`docs/plans/**`。

## 7. 停止条件

- 对齐必须移除安全闸（loopback/覆盖保护）且无法用显式开关保留：停下询问。
- 底层能力确实不可达（附最小复现与代码证据）：记为不可改，继续其余项。
- 同一 HARNESS-ERROR 重跑 1 次仍失败：停下，不继续消耗轮次。
