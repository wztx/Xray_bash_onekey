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

- [x] S1 target/serverNames 主动回源探测（TCP connect + 证书链/hostname 校验；失败阻断保存）。
  - `internal/deploy/probe.go` / `probe_test.go`：无 SNI 只做 TCP；有 SNI 时按系统根证书
    校验证书链与 hostname（不加 OCSP、不锁 TLS 版本）；失败 rc=2、零落盘、无备份。
  - E3（拒连目标）与 E4（受信本地 CA 回源）均 PASS；E4 证据显示本地 origin 必须协商
    ALPN，否则 Reality 判 invalid 回退（探测本身不背这个锅）。
  - 证据：`tests/e2e-diff/evidence/s1-edit-probe-ca`（全量矩阵，E1–E4 PASS）。
- [x] C4 metadata 补版本与端口/target/serverNames 快照。
  - `internal/store/metadata.go`：新增 `install{engineVersion,port,target,serverNames}`，
    port 必须在 1–65535，否则按损坏处理（rc=4）；旧 metadata 无该字段照常加载。
  - `internal/deploy/deploy.go`：安装时写入快照；端口取「显式 --public-port → 托管 Nginx
    前端 listen → 显式 --port → 运行配置首个 inbound」，与 bash install_config 的 port 同义。
  - `internal/deploy/edit.go`：编辑后用生效配置刷新 target/serverNames，端口/版本不动。
  - 单测：store 快照加载与 port=0 拒绝、安装写入快照、编辑刷新快照；`go test` 三包全绿。
  - 证据：`tests/e2e-diff/evidence/c4-metadata-snapshot-full`（全量矩阵，M1–M7/M9/M10 双侧
    全绿、M8 仍 HARNESS-BLOCKED，E1–E4 全部 PASS）。
- [x] C3 日志轮转/清理（ED-004）。
  - 新增 `idleleo xray logs clean`（`--yes` 必填，截断 Xray/Nginx 日志目录下所有普通
    `*.log`，保留 inode/属主/权限，符号链接与非日志文件不碰）与
    `idleleo xray logs rotate enable|disable`（写入与 bash 同构的
    `etc/logrotate.d/xray_log_cleanup` + `systemd logrotate.service.d` drop-in，
    `logrotate --debug` 通过后才替换，启用 `logrotate.timer`；disable 只删自己的两个文件）。
  - 已知偏差（已登记为主动不对齐 G12，不是 ED）：bash 会自动 `apt`/`dnf` 装 logrotate，
    Go 不碰系统包管理器；缺二进制时在任何写入前失败，并打印 Deb/RHEL/Alpine 三条可直接
    复制的安装命令。后果：全新系统上 `xray logs rotate enable` 需先手动装一次。详见
    `behavior-diff.md`「主动不对齐：G12 不调用系统包管理器」。
  - 验证：单测覆盖截断范围/递归/符号链接/权限、缺二进制不落盘、`--debug` 拒绝不落盘、
    disable 不碰其他 logrotate 文件；容器内实测 clean（freedBytes=20、4 个文件归零、
    keep.txt 保留）、rotate enable（真实 logrotate `--debug` rc=0，配置与 drop-in 内容符）、
    rotate disable（两个文件删除，无残留）。
  - 证据：矩阵 OPS-22 由 `go-missing` 改为 `must-match`，ED-004 从 expected_diffs 移除。
- [x] C1 fail2ban 接入（ED-002）。
  - 新增 `internal/deploy/fail2ban.go` 与 `idleleo fail2ban status|install|uninstall|banned|unban|trust add|del|jail enable|disable`。
  - jail 1:1 对齐 bash：`sshd`（maxretry 5 / bantime 604800 / backend=systemd）、`nginx-badbots`（5/604800）、
    `nginx-botsearch`（604800）、`nginx-no-host`（5 / findtime 120 / 604800）、`nginx-tls-error`
    （8 / findtime 300 / 43200）；全局增量封禁 `1 2 4 8 16 32 64`、上限 180d。阈值与 `ignoreip`
    均原样继承，未放宽、未自动加白。
  - 加固（bash 没有）：日志文件不存在的 jail 不写，只留 warning（否则 fail2ban 起不来）；`sshd` 仅在
    ssh/sshd unit 为 active 时写；候选配置先在 `/etc/fail2ban` 副本上跑 `fail2ban-client -t`，
    不通过则零落盘；已存在且内容不同的 jail 文件不覆盖，只 warning。
  - 卸载：安装时记录 `/etc/idleleo/v1/fail2ban.json` manifest；卸载只删 manifest 内文件，
    manifest 外的 `*.local` 保留并逐个提示「不是 Idleleo 创建的」；manifest 缺失（老安装）列出候选、
    要求 `--force`，且只删已知文件名；不卸载软件包，只重启服务卸载 jail。
  - 安装成功后打印 `SSH_CLIENT`/`SSH_CONNECTION` 来源 IP 与一行
    `idleleo fail2ban trust add --jail sshd --ip <ip>`，**不自动执行**（避免给动态 IP 放行陌生人）。
  - 不调包管理器（G13）：缺 `fail2ban-client` 时打印 deb/rhel/alpine 安装命令并零落盘。
  - 验证：`go test ./internal/deploy -run Fail2ban` 全绿（8 个用例）；容器内真实 fail2ban 1.1.0 实测
    install（4 jail + 跳过 sshd）、status、banned、unban（含二次解封 already_absent）、trust add、
    jail disable、uninstall（保留 `user-custom.local`）。
  - 矩阵：OPS-19 由 `go-missing` 改为 `must-match`，ED-002 从 `expected_diffs.json` 移除。
- [x] S2 负载均衡后端增删 + reality-balance 支持（ED-001）。
  - 新增 `internal/deploy/balance.go` 与 `idleleo xray balance add|list|remove`
    （`--upstream ws|grpc|xhttp|reality`、`--host/--port/--weight`、`--probe`、`--container`、`--json`）。
  - 生成物与 bash 对齐：写 `<host>.<ws|reality>Servers`，行格式
    `server <host>:<port> weight=<w> max_fails=2 fail_timeout=10;`；`xray install --mode
    reality-balance --role primary|secondary` 复用 managed Nginx 并生成 `*.realityServers` include。
  - 主动收紧（G14，不进 ED）：reality-nginx 与二级服务器拒绝增删并指路
    `--mode reality-balance --role primary`；拒绝删空最后后端、本机回环、端口不匹配、
    重复/非法 host、保留端口 `443/9403/9404/9443/9444`；`nginx -t` 失败回滚；
    默认不探测并提示依赖 `max_fails/fail_timeout` 被动摘除，`--probe` 才做 TCP+TLS1.3+SNI。
  - 门槛：`go test ./internal/deploy -run Balance` 全绿；两端必须实跑，缺任一侧记
    HARNESS-ERROR，观测不一致记 BLOCKER，绝不写 PASS。
  - 证据：OPS-09（bash M4 安装 + 菜单 `2>3>1` file_manager 增/列/删 ‖ Go TLS 安装 +
    `balance add|list|remove --upstream ws`）与 OPS-31（bash `1>1>5>1` reality-balance
    主服务器 + 同样菜单路径 ‖ Go `--mode reality-balance --role primary`）双端 PASS：
    `evidence/s2-ops-0434/p2/OPS-09/ops.json`、`.../OPS-31/ops.json`。
  - 矩阵：OPS-09 由 `go-missing` 改为 `must-match`，新增 OPS-31 `must-match`；
    ED-001 从 `expected_diffs.json` 移除。
  - 故障摘除 OPS-32：`max_fails=2 fail_timeout=10` 被动摘除双端 PASS
    （`evidence/ops32-failover-0523/p2/OPS-32/ops.json`，ws 与 reality 两条上游）：
    - ws：真实 TLS 流量打到 `backend-a:9001`/`backend-b:9002`，`kill -9` 一个后
      84 次请求零 5xx、全由存活后端返回；每个 worker 的失败尝试止于 `max_fails=2`
      并静默约 12s，重启后重新选中。
    - reality：真实 TLS 1.3 ClientHello 经 stream 入口，84 次连接全到存活端、零连接失败；
      标记后端只做 TCP 应答，故只证明 stream 选路与摘除，**不外推 Reality 握手**。
    - harness 在两侧删除安装自带的回环后端：`xray balance remove` 按设计拒绝删回环，
      没有对称的菜单入口；删除动作与原因记录在 `ops.json` 的 `loopbackRemovedBy`。
- [x] S3 证书路径/域名（G16/G17）。
  - 入口保持 `xray config edit`：新增 `--domain/--cert/--cert-key`，仅 TLS 生效；
    Reality 指路 `--server-names`，reality/reality-balance 一律拒绝。
  - 可改与不可改：域名、证书路径、私钥路径可改；CA 类型、签发方式、SAN 列表不可改
    （SAN 由证书本身决定，只校验并写入报告），改域名不自动签证书。
  - 写入前交叉校验：证书/私钥必须成对、证书 SAN 必须覆盖目标域名（即「改域名但证书还是
    旧域名」直接拒绝）、不能过期/未生效；30 天内到期与私钥全局可读只 warning。
  - 默认对新域名做本地 TLS 握手（`127.0.0.1:<public-port>`，SNI=新域名，校验 served leaf
    与配置证书一致、SAN、有效期、TLS 1.3；系统根不信任只 warning）；`--no-probe` 关闭；
    服务未监听记 warning 并标 `skipped`，不算通过。`--no-restart` 时同样只标 `skipped`。
  - 仅前端变更时 runtime JSON 不变：不再误判 `NoChanges`，强制重写 Nginx 并 reload；
    **不重启 Xray**，避免无谓断线。
  - 续期链路：`jobs.json` 的 `certDomain/certFile/certKeyFile` 随编辑更新（路径转成相对根）；
    `cert-renew` 优先观测 `cfg.certFile`；不自动重签、不重装 hook。
  - 备份追加 `tls-cert.pem`/`tls-key.pem`（0600，不回显）/`schedule-jobs.json`，失败连同
    `jobs.json` 一起回滚；Bash 根与 `provenance!=native` 的导入根在写入前拒绝（G17）。
  - 单测：`go test ./internal/xraycfg ./internal/deploy ./internal/schedule`（域名/证书
    rewrite、SAN/过期/配对拒绝、近到期与私钥权限 warning、握手 ok/skipped/失败三态、
    备份内容、Bash 根拒绝、jobs.json 更新与观测优先级）。
  - 已知差异：不自动重签（G16，与 G15 分开登记）。
- [ ] S4 Reality 握手参数。
- [ ] C2 流量阻断 ruleset（ED-003）。
- [ ] C5 多用户 UUID 单点修改。
- [ ] C6 direct TLS 支持。
- 规则：每项单独提交；发现「照 bash 做反而降低安全性」先停并上报。

## 待办（未排期，不要在当前批次顺手改）

- [ ] **ED-003 的 `paths` 标错了，做 C2 之前先修描述。** 现在写的是
  `nftables/iptables ruleset`，但 bash 的 `scripts/traffic_blocker.sh` 实际生成的是
  **Xray 路由规则**：`routing.rules` + `blocked` outbound，依赖 `geosite:category-ads-all`、
  `geoip:private`、国家码、bittorrent 与 `geoip.dat`/`geosite.dat`，**没有任何 nftables/iptables 调用**。
  不先改就会把 C2 的验收口径描错（去比内核 ruleset 而不是比 xray 配置）。改描述时同步核对
  `docs/plans/p2/spec.md` 的 C2 段落与 OPS-21 的 layers。

- [ ] **E2E 局部跑（`E2E_ONLY`）会生成一张「局部跑却覆盖全场景」的误导性 `install-matrix.md`。**
  - 现象：`E2E_ONLY="E1,E4" bash tests/e2e-diff/run_p2_matrix.sh` 只跑编辑场景，但
    `compare/report.py` 仍按 `matrix.json` 的全量场景渲染矩阵；未跑的 M1–M10（以及未跑的
    那一侧）没有证据目录，被 report.py 判为「missing evidence」→ **HARNESS-ERROR**。
    结果矩阵里出现 10 行 HARNESS-ERROR，和「全量跑全崩」看起来完全一样。
  - 危害：这是伪证据。后来人翻 `evidence/<run-id>/p2/install-matrix.md` 会把它当成真实
    失败证据：轻则误判 Go/bash 回归，重则把真实回归淹没在这片噪声里，或者反过来被当成
    「已知 HARNESS 问题」而放过。
  - 可能修法（任选其一，倾向第一种）：
    1. runner 把本次实跑范围写进证据目录（如 `scope.json`，列出实际执行的 `场景/侧`），
       `report.py` 读到 scope 时**只渲染实跑过的格子**，未跑的留 `—`/`not run`，
       不进 BLOCKER / HARNESS-ERROR 统计；无 `scope.json` 的历史证据保持现有全量语义。
    2. 更轻的做法：`E2E_ONLY` 非空时，矩阵标题与首行显式标注 `PARTIAL RUN: E1,E4`，
       未跑场景归入新类别 `NOT-RUN`，与 HARNESS-ERROR 分开统计。
  - 影响面：`tests/e2e-diff/run_p2_matrix.sh`、`run_p1_smoke.sh`、`compare/report.py`
    （`--self-test` 需补「局部跑」一例），以及历史 `evidence/*/p2/install-matrix.md` 的可读性。

# Task Dependencies

- T2/T3/T4 可并行，T7 依赖 T2–T6，T8 依赖 T7。
- T5 依赖 T7 的 M4 证据，结论可能回写 spec。
- T9–T11 按序独立验收；T12 依赖 T9–T11 完成。
- T13 依赖 T7；T14 依赖 T13（OPS 待办来源）。
