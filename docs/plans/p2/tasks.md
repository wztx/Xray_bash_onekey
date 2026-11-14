# P2 任务清单

前置：`docs/plans/p2/spec.md` 的差异清单 G1–G11 与 D1–D9 按新口径执行（Go 对齐 bash，
真做不到才保留差异并附证据）。不动 `install.sh`；不静默删除安全闸。

## T0 差异清单

- [x] 产出 `docs/plans/p2/behavior-diff.md`：G1–G11 逐条标注「可改 / 不可改 / 需拍板」、
  改动层（CLI 校验 / 生成逻辑 / 安装落地）、证据与验证方式。
- 验证：清单覆盖 M3、M10、M4、D3、M2、M9/M5–M7、安全闸七项，以及 G8–G11 三项补强。

## T1 矩阵与 argv

- [x] `matrix.json`：M3 改为 Go 实装 argv；M10 改为 `xray install --role relay`；
  删除 `goStatus:"capability-gap"`；D1–D5 按新口径落库；M5–M7 补 `--binary`；M9 保留监听覆盖。
- [x] `run_p2_matrix.sh` 的 argv 探针补 M4、M2 别名、M3/M10，并修正 rc 采集。
- 验证：`jq` 校验矩阵；探针输出里 M2-alias / M3 rc=0。

## T2 G1 Reality + 单传输（生成逻辑）

- [x] `internal/xraycfg/xraycfg.go` 放开 `ModeReality` 的 ws/grpc/xhttp，生成
  raw Reality 主 inbound + 附加传输 inbound（端口 +1），对齐 bash `reality_add_more`。
- [x] 单测：`TestRealitySingleTransportKeepsRealityPrimary`。
- 验证：`go test ./internal/xraycfg`；P2 M3 两侧 L2/L4 MATCH。

## T3 G2 relay 安装落地（安装落地）

- [x] `internal/nginx`：`EnsureRelayInclude` 在主配置顶层写 marker + include，
  已有用户 `stream {}` 时拒绝。
- [x] `internal/deploy/relay.go`：`InstallRelay` 装 managed Nginx(stream)、写
  `relay-stream.conf`、include、`nginx -t`、启服务、写 metadata；幂等。
- [x] `internal/cli/xray.go` + `flags.go`：`xray install --role relay --target --listen-port --listen`。
- [x] 单测：relay 落盘 / 二次运行不重复 include。
- 验证：P2 M10 两侧 L1–L4 MATCH，L4 经中转容器回源成功。

## T4 G4/G5 重复安装与 CLI 别名

- [x] `internal/deploy/deploy.go`：已有 runtime config 且未显式指定时默认保留并告警
  （对齐 bash 保留配置）；`--keep-config` / `--rewrite-config` 保留为显式开关；
  保留配置时仍生成 Nginx fragments。
- [x] `internal/cli/xray.go`：`--mode reality --nginx-bin` 兼容别名到 `reality-nginx`。
- [x] 更新/新增 deploy 单测：默认接管、显式重写、别名。
- 验证：P2 所有场景第 2 轮 rc=0 且 L6 无新增/漂移；M2 两种 CLI 形态生成等价配置。

## T5 G3 M4 nginx 目录取证

- [x] 用 M4 的 P2 manifest 对比两侧 nginx 二进制目录、fragment 目录、include 路径。
- [x] 仅当存在真实磁盘差异时改 Go；否则在矩阵注明“无差异”。
- 验证：M4 的 L1 路径/权限对比结论写入报告。

## T6 驱动、采集与报告

- [x] `drivers/bash_menu.exp` 覆盖 M2/M3/M5/M6/M7/M9/M10 的实际提示词。
- [x] `drivers/go_install.sh` 第 2 轮传 `--keep-config`；relay 场景不种 xray。
- [x] `collect/logs.sh`、`collect/idempotency.sh`、`collect/l4.sh`、`collect/client_config.py`
  支持多传输与 relay。
- [x] `compare/report.py`：MATCH / ED / BLOCKER / HARNESS-ERROR 分类不变，去掉 capability-gap 分支。
- 验证：`bash collect/self_check.sh`、`python3 compare/report.py --self-test` rc=0。

## T7 全量复跑与矩阵

- [x] 小样：M1/M3/M4/M9/M10 两侧 × 2 轮。
- [x] 全量：M1–M10 × 两侧 × 2 轮；HARNESS-ERROR 仅按规则重跑（M6/M10 bash 首轮超时重跑一次）。
- [x] 产出 `evidence/final-full2-8863b10/p2/install-matrix.md`，附基线对比与保留差异。
- [x] 修复两处测试/实现缺陷：bash 第 2 轮不再用空占位覆盖第 1 轮配置（否则 L6 从未真正验证）；
  重复安装 `--keep-config` 依据 `00-xray.conf` 恢复 Nginx 前置模式（否则前置场景第 2 轮丢 Nginx）。
- 验证：M1–M7/M9/M10 两侧 rc/L4 两轮/rc2/L6 全部通过；M8 仍 HARNESS-BLOCKED；
  剩余 BLOCKER 仅由 pending EXPECTED-DIFF 引起。

## T8 提交与汇报

- [ ] 按主题拆 commit：差异清单+spec、Go 生成逻辑、relay 安装、重复安装/别名、矩阵+驱动+runner。
- [ ] 汇报：差异清单分类、每项改法与验证、矩阵前后对比、仍保留的能力缺口。

## T9 G8 relay 文件集合（安装落地）

- [x] `nginx.InstallSpec.RelayOnly`：relay 不创建 `00-xray.conf`/`03-isolate.conf` 占位。
- [x] `RewriteMainConfig`：Stream 分支仅节点模式 include 两个占位文件；节点模式不变。
- [x] 单测：relay 不生成/不 include 占位文件、不含 http glob。
- 验证：M10 两侧 `/etc/idleleo/conf/nginx` 文件集合一致、`nginx -t` ok、L4 回源与 L6 幂等不回归。

## T10 G9/G10 端口策略（生成逻辑）

- [x] 去掉 `base+1`：ws/gRPC 10000–10999、xHTTP 11000–11999 升序候选。
- [x] 生成前 bind 探测避让；排除 9403/9404/9443/9444 与已用端口；65535 不回绕 1。
- [x] `--ws-port/--grpc-port/--xhttp-port` 显式覆盖，越界/重复/保留/占用直接报错。
- [x] 探测跳过时输出 warning，安装前即报错而不是等服务启动失败。
- [x] G10：TLS 回环 inbound 使用传输端口池，Nginx 独占公网端口。
- 验证：M3/M7 两侧 2 轮 rc=0、L4 ok、幂等 ok；第三方占用 10000 时自动选 10001 并留 warning。

## T11 G11 `xray config edit`（CLI + 生成 + 安装落地）

- [x] `internal/xraycfg/edit.go`：spec 还原、patch、严格 diff 白名单、隐含 keep。
- [x] `internal/deploy/edit.go`：`xray -test` 前置、`nginx -t`、备份
  `/etc/idleleo/backup/edit-<ts>/`、快照与重启失败回滚、`--no-restart`、relay 编辑。
- [x] `internal/cli/xrayedit.go` + flags：6 项第一梯队、`--dry-run`/`--yes`/`--json`、
  断线项二次确认、与 `--rewrite-config` 冲突 rc=2。
- [x] 单测：patch 只改目标字段、自检失败零落盘、重启失败回滚、dry-run。
- [x] 矩阵 E1（改前改后）与 E2（重启失败回滚）+ 驱动/runner/报告。
- 验证：E1/E2 PASS；reality、reality-nginx、TLS、relay 手工验证通过。

## T12 规格与文档收口

- [x] 讨论稿升级为正式规格 v1.0（`interactive-config-editing-discussion.md`）。
- [x] `spec.md` 补 G8–G11、D6–D9 与实现文件。
- [x] `behavior-diff.md` 补 G8–G11 与证据。
- 验证：三份文档口径一致，矩阵场景与规格 §11 对应。

## T13 ED 按类审批（护栏 + 批准）

- [x] 113 条 M1–M10 布局差异归并为 13 类（14 个唯一路径，仅合并 conf 两路径）。
- [x] 两条护栏：`paths` 精确匹配（不再按目录前缀吸收）+ `scenarios` 显式列举；
  未列举路径/场景一律 BLOCKER，原 113 条 id 保留在各类 `supersedes`。
- [x] `owner=hello-yunshu`、`approved_by=release-gate`、`expires=2027-03-31`；
  ED 内注明「流程批准，不是双人批准」并附 review 链接。
- [x] ED-001/002/003/004 判 `rejected`（应改 Go）并挂第二梯队；ED-005 登记。
- [x] `report.py` 判定修正：只要存在未抑制路径即 BLOCKER，不再被部分抑制掩盖。
- [x] release 门槛补「ED 到期复核」。
- 验证：`report.py --self-test` 覆盖新增文件/新增场景/拒绝态三例；用
  `final-full2-8863b10` 证据重生成矩阵，M1–M10 判定从 BLOCKER 变为类 ED，
  未抑制差异为 0。

## T14 第二梯队（顺序已拍板）

- [ ] S1 target/serverNames 主动回源探测（TCP connect + 可选 TLS；失败阻断保存）。
  - 代码与单测完成：`internal/deploy/probe.go`、`probe_test.go`；E3（拒连目标）通过，
    rc=2、SHA 不变、无备份、服务 active。
  - **E4（可达目标）未收口**：本地自签 TLS 回源能通过探测并落盘，但改后 Reality L4
    失败（curl 56）。说明「TCP+不校验证书」挡不住会断线的 target；已上报待拍板
    （三条选项：保持现状并去掉 E4 的 L4 断言 / 探测改为校验证书链+hostname /
    E4 改用第二个公网真实回源）。
- [ ] C4 metadata 补版本与端口/target/serverNames 快照。
- [ ] C3 日志轮转/清理（ED-004）。
- [ ] C1 fail2ban 接入（ED-002）。
- [ ] S2 负载均衡后端增删 + reality-balance 支持（ED-001）。
- [ ] S3 证书路径/域名。
- [ ] S4 Reality 握手参数。
- [ ] C2 流量阻断 ruleset（ED-003）。
- [ ] C5 多用户 UUID 单点修改。
- [ ] C6 direct TLS 支持。
- 规则：每项单独提交；发现「照 bash 做反而降低安全性」先停并上报。

# Task Dependencies

- T2/T3/T4 可并行，T7 依赖 T2–T6，T8 依赖 T7。
- T5 依赖 T7 的 M4 证据，结论可能回写 spec。
- T9–T11 按序独立验收；T12 依赖 T9–T11 完成。
- T13 依赖 T7；T14 依赖 T13（OPS 待办来源）。
