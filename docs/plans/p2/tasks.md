# P2 任务清单

前置：`docs/plans/p2/spec.md` 的差异清单 G1–G7 与 D1–D5 按新口径执行（Go 对齐 bash，
真做不到才保留差异并附证据）。不动 `install.sh`；不静默删除安全闸。

## T0 差异清单

- [x] 产出 `docs/plans/p2/behavior-diff.md`：G1–G7 逐条标注「可改 / 不可改 / 需拍板」、
  改动层（CLI 校验 / 生成逻辑 / 安装落地）、证据与验证方式。
- 验证：清单覆盖 M3、M10、M4、D3、M2、M9/M5–M7、安全闸七项。

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

- [ ] 小样：M1/M3/M4/M9/M10 两侧 × 2 轮。
- [ ] 全量：M1–M10 × 两侧 × 2 轮；HARNESS-ERROR 仅按规则重跑。
- [ ] 产出 `evidence/<run-id>/p2/install-matrix.md`，附前后对比与保留差异。
- 验证：无未归因 HARNESS-ERROR；M8 仍 HARNESS-BLOCKED；M3/M10 不再出现 capability-gap。

## T8 提交与汇报

- [ ] 按主题拆 commit：差异清单+spec、Go 生成逻辑、relay 安装、重复安装/别名、矩阵+驱动+runner。
- [ ] 汇报：差异清单分类、每项改法与验证、矩阵前后对比、仍保留的能力缺口。

# Task Dependencies

- T2/T3/T4 可并行，T7 依赖 T2–T6，T8 依赖 T7。
- T5 依赖 T7 的 M4 证据，结论可能回写 spec。
