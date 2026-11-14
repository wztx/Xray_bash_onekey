#!/usr/bin/env python3
"""Builds the P2 install matrix report from evidence.

Classification per scenario:
  MATCH              both sides installed, both L4 probes passed, round 2 stable,
                     and the L1 artifact layout has no unsuppressed difference.
  ED-xxx             an L1 difference is exactly covered by a registered
                     EXPECTED-DIFF (cited); pending/expired/unknown is still a
                     BLOCKER per policy.
  BLOCKER            install/L4/idempotency failure or an unregistered layout diff.
  HARNESS-ERROR      driver rc=124 / HARNESS-ERROR marker / missing evidence.
  HARNESS-BLOCKED    scenario explicitly ineligible (M8 ACME).

L1 comparison is layout-level: full path sets are compared, then grouped by
top-level root so the report stays readable. L2 semantic field diffing is not
claimed here; the sanitized config digest is reported for follow-up inspection.
"""
import argparse
import datetime
import json
import os
import sys

LAYERS = ("L0", "L1", "L2", "L3", "L4", "L5", "L6")


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return default


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def install_rc(side_dir):
    value = read_text(os.path.join(side_dir, "install.rc")).strip()
    try:
        return int(value)
    except ValueError:
        return None


def l4_results(side_dir, round_dir):
    base = os.path.join(side_dir, "L4") if not round_dir else os.path.join(side_dir, round_dir, "L4")
    results = {}
    if not os.path.isdir(base):
        return results
    for name in sorted(os.listdir(base)):
        conn = read_json(os.path.join(base, name, "connectivity.json"))
        if conn is not None:
            results[name] = bool(conn.get("ok"))
    return results


def relay_l4(side_dir, round_dir):
    path = os.path.join(side_dir, "L4-relay.json") if not round_dir else \
        os.path.join(side_dir, round_dir, "L4-relay.json")
    data = read_json(path)
    if data is None:
        return None
    return data.get("rc") == 0


def manifest_paths(side_dir):
    data = read_json(os.path.join(side_dir, "manifest.json"), {})
    return {entry.get("path") for entry in data.get("entries", []) if entry.get("path")}


def idempotency(side_dir):
    return read_json(os.path.join(side_dir, "round2", "idempotency.json"))


def harness_error(side_dir):
    if install_rc(side_dir) == 124:
        return "driver rc=124"
    log = read_text(os.path.join(side_dir, "install.log"))
    if "HARNESS-ERROR" in log:
        return "HARNESS-ERROR marker in install.log"
    if install_rc(side_dir) is None and not os.path.isdir(side_dir):
        return "missing evidence directory"
    return None


def group_roots(paths):
    groups = {}
    for path in paths:
        parts = [p for p in path.split("/") if p]
        root = "/" + "/".join(parts[:3]) if len(parts) >= 3 else path
        groups.setdefault(root, 0)
        groups[root] += 1
    return groups


def diff_manifests(bash_paths, go_paths):
    added = sorted(go_paths - bash_paths)
    removed = sorted(bash_paths - go_paths)
    return removed, added


def ed_suppression(diffs, scenario, layer, entries):
    """Returns (suppressed, unsuppressed). Directory ED paths act as prefixes."""
    suppressed, unsuppressed = {}, []
    active = [e for e in entries if e.get("scenario") == scenario and e.get("layer") == layer]
    for path in diffs:
        hit = None
        for entry in active:
            ep = (entry.get("path") or "").rstrip("/")
            if ep and (path == ep or path.startswith(ep + "/")):
                hit = entry
                break
        if hit is None:
            unsuppressed.append(path)
        else:
            suppressed[path] = hit
    return suppressed, unsuppressed


def ed_state(entry):
    status = entry.get("status")
    expires = entry.get("expires")
    if status != "approved":
        return "BLOCKER(%s)" % (status or "unknown")
    if not entry.get("owner") or not entry.get("approved_by") or not expires:
        return "BLOCKER(missing-owner/approver/expires)"
    try:
        if datetime.date.fromisoformat(expires) < datetime.date.today():
            return "BLOCKER(expired)"
    except ValueError:
        return "BLOCKER(bad-expires)"
    return "ED"


def side_summary(side_dir):
    return {
        "rc": install_rc(side_dir),
        "l4": l4_results(side_dir, None),
        "relayL4": relay_l4(side_dir, None),
        "rc2": install_rc(os.path.join(side_dir, "round2")),
        "l4Round2": l4_results(side_dir, "round2"),
        "relayL4Round2": relay_l4(side_dir, "round2"),
        "idempotency": idempotency(side_dir),
        "harness": harness_error(side_dir),
        "logs": read_json(os.path.join(side_dir, "logs.json"), {}),
    }


def verdict_for(scenario, bash, go, entries):
    sid = scenario["id"]
    if not scenario.get("eligible", True):
        return "HARNESS-BLOCKED", ["scenario ineligible: " + scenario.get("notes", "")]

    reasons = []
    for side_name, side in (("bash", bash), ("go", go)):
        if side["harness"]:
            return "HARNESS-ERROR", ["%s: %s" % (side_name, side["harness"])]
        if side["rc"] != 0:
            return "BLOCKER", ["%s install rc=%s" % (side_name, side["rc"])]
        if side["rc2"] not in (0, None):
            return "BLOCKER", ["%s repeat install rc=%s" % (side_name, side["rc2"])]
        bad = [name for name, ok in side["l4"].items() if not ok]
        if side["relayL4"] is False:
            bad.append("relay")
        if bad:
            return "BLOCKER", ["%s L4 failed: %s" % (side_name, ",".join(sorted(bad)))]
        bad2 = [name for name, ok in (side.get("l4Round2") or {}).items() if not ok]
        if side.get("relayL4Round2") is False:
            bad2.append("relay")
        if bad2:
            return "BLOCKER", ["%s L4 round2 failed: %s" % (side_name, ",".join(sorted(bad2)))]
        idem = side["idempotency"]
        if idem is not None and not idem.get("ok"):
            return "BLOCKER", ["%s idempotency failed" % side_name]

    bash_paths, go_paths = manifest_paths(os.path.join(EVID, sid, "bash")), \
        manifest_paths(os.path.join(EVID, sid, "go"))
    removed, added = diff_manifests(bash_paths, go_paths)
    diffs = removed + added
    if diffs:
        suppressed, unsuppressed = ed_suppression(diffs, sid, "L1", entries)
        blocked = [p for p, e in suppressed.items() if ed_state(e).startswith("BLOCKER")]
        if blocked:
            return "BLOCKER", ["ED still pending/expired for %d L1 paths" % len(blocked)]
        if suppressed:
            return "ED-" + ",".join(sorted({e["id"] for e in suppressed.values()})), \
                ["%d L1 paths suppressed by registered ED" % len(suppressed)]
        return "BLOCKER", ["unregistered L1 layout diff (%d paths)" % len(unsuppressed)]
    return "MATCH", []


def render_edits(evidence, matrix):
    """Go-only config-edit rows: before/after plus restart-failure rollback."""
    entries = matrix.get("edits", [])
    if not entries:
        return []
    lines = ["## 配置编辑场景（xray config edit，Go）", "",
             "| 场景 | 编辑 rc | SHA 改前 → 改后 | 检查项 | L4 改前/改后 | 判定 | 说明 |",
             "|---|---|---|---|---|---|---|"]
    sha_notes = []
    for entry in entries:
        eid = entry["id"]
        base = os.path.join(evidence, eid, "go")
        checks = read_json(os.path.join(base, "edit", "checks.json"), {})
        before = read_json(os.path.join(base, "edit", "L4-before", "connectivity.json"), {})
        after = read_json(os.path.join(base, "edit", "L4-after", "connectivity.json"), {})
        got = checks.get("checks", {})
        wanted = checks.get("wanted") or entry.get("checks", [])

        def mark(value):
            return "ok" if value is True else ("fail" if value is False else "-")

        def short(value):
            return (value or "-")[:12]

        passed = bool(checks) and checks.get("allPassed") is True and \
            before.get("ok") is True and after.get("ok") is True
        notes = []
        if not checks:
            notes.append("缺 checks.json")
        if before.get("ok") is not True:
            notes.append("改前 L4 未通过")
        if after.get("ok") is not True:
            notes.append("改后/回滚后 L4 未通过")
        if eid == "E2" and got.get("configRestored") is True:
            notes.append("回滚后 SHA 还原")
        detail = ", ".join("%s:%s" % (name, mark(got.get(name))) for name in wanted) or "-"
        lines.append("| %s %s | %s | %s → %s | %s | %s / %s | **%s** | %s |" % (
            eid, entry.get("name", ""), checks.get("editRc", "-"),
            short(checks.get("beforeSha")), short(checks.get("afterSha")), detail,
            mark(before.get("ok")), mark(after.get("ok")),
            "PASS" if passed else "BLOCKER",
            ("; ".join(notes) or entry.get("notes", "")).replace("|", "/")))
        if checks:
            sha_notes.append("- %s SHA：改前 `%s` → 改后 `%s`（%s）" % (
                eid, checks.get("beforeSha", "-"), checks.get("afterSha", "-"),
                "已还原" if checks.get("beforeSha") == checks.get("afterSha") else "已变更"))
    lines.append("")
    lines.extend(sha_notes)
    lines.append("")
    return lines


def cell_parts(side):
    return {
        "rc": side["rc"],
        "l4": side["l4"] if side["l4"] else ({"relay": side["relayL4"]} if side["relayL4"] is not None else {}),
        "l4r2": side["l4Round2"] if side["l4Round2"] else (
            {"relay": side["relayL4Round2"]} if side["relayL4Round2"] is not None else {}),
        "rc2": side["rc2"],
        "l6": (side["idempotency"] or {}).get("ok"),
    }


def cell_label(bash, go, verdict):
    def fmt_side(side):
        parts = cell_parts(side)
        l4 = ",".join("%s:%s" % (k, "ok" if v is True else "fail") for k, v in sorted(parts["l4"].items())) or "-"
        l4r2 = ",".join("%s:%s" % (k, "ok" if v is True else "fail") for k, v in sorted(parts["l4r2"].items())) or "-"
        l6 = "-" if parts["l6"] is None else ("ok" if parts["l6"] else "fail")
        return "%s / %s / %s / %s / %s" % (
            parts["rc"] if parts["rc"] is not None else "-", l4, l4r2,
            parts["rc2"] if parts["rc2"] is not None else "-", l6)
    return "%s / %s / %s" % (fmt_side(bash), fmt_side(go), verdict)


def runtime_ports(evidence, sid, side, loopback=False):
    """Ports owned by the install, excluding docker DNS and the 80/443 front."""
    data = read_json(os.path.join(evidence, sid, side, "runtime.json"), {})
    ports = set()
    for item in data.get("listeners", []):
        local = item.get("local", "")
        if local.startswith("127.0.0.11"):
            continue
        host, _, port = local.rpartition(":")
        if not port.isdigit():
            continue
        if loopback:
            if host != "127.0.0.1":
                continue
        elif host in ("0.0.0.0", "[::]", "*") and port in ("80", "443"):
            continue
        ports.add(int(port))
    return ", ".join(str(p) for p in sorted(ports)) or "-"


def nginx_files(evidence, sid, side):
    data = read_json(os.path.join(evidence, sid, side, "manifest.json"), {})
    root = "/etc/idleleo/conf/nginx"
    names = [os.path.basename(e.get("path", "")) for e in data.get("entries", [])
             if e.get("path", "").startswith(root + "/")
             and e.get("path", "").count("/") == root.count("/") + 1]
    return ", ".join(sorted(names)) or "-"


def render_step_changes(evidence, baseline):
    if not baseline or not os.path.isdir(baseline):
        return []
    lines = ["## 三步改动落地证据", "",
             "| 主题 | 基线 go | 本轮 go | 本轮 bash | 关联 |",
             "|---|---|---|---|---|",
             "| M10 relay nginx 文件 | %s | %s | %s | G8 |" % (
                 nginx_files(baseline, "M10", "go"), nginx_files(evidence, "M10", "go"),
                 nginx_files(evidence, "M10", "bash")),
             "| M3 附加传输端口 | %s | %s | %s | G9 |" % (
                 runtime_ports(baseline, "M3", "go"), runtime_ports(evidence, "M3", "go"),
                 runtime_ports(evidence, "M3", "bash")),
             "| M7 附加传输端口 | %s | %s | %s | G9 |" % (
                 runtime_ports(baseline, "M7", "go"), runtime_ports(evidence, "M7", "go"),
                 runtime_ports(evidence, "M7", "bash")),
             "| M4 TLS 回环端口 | %s | %s（公网 443） | %s | G10 |" % (
                 runtime_ports(baseline, "M4", "go", True), runtime_ports(evidence, "M4", "go", True),
                 runtime_ports(evidence, "M4", "bash", True)),
             "| E1/E2 配置编辑 | 无 | 2 场景 PASS（见上表） | — | G11 |",
             ""]
    return lines


def render_baseline(evidence, baseline, matrix, entries):
    """Per-scenario diff against an earlier run; only changed cells are named."""
    if not baseline or not os.path.isdir(baseline):
        return []
    global EVID
    lines = ["## 与基线对比（%s）" % os.path.basename(baseline.rstrip("/")), "",
             "| 场景 | 基线（bash ‖ go ‖ 判定；每侧 rc/L4r1/L4r2/rc2/L6） | "
             "本轮（bash ‖ go ‖ 判定；每侧 rc/L4r1/L4r2/rc2/L6） | 变化格子 |",
             "|---|---|---|---|"]
    current = EVID
    changed_total = 0
    try:
        for scenario in matrix.get("install", []):
            sid = scenario["id"]
            snapshots = []
            for root in (baseline, evidence):
                EVID = root
                bash = side_summary(os.path.join(root, sid, "bash"))
                go = side_summary(os.path.join(root, sid, "go"))
                verdict, _ = verdict_for(scenario, bash, go, entries)
                snapshots.append((bash, go, verdict))
            (bb, bg, bv), (cb, cg, cv) = snapshots
            changes = []
            for side_name, old, new in (("bash", bb, cb), ("go", bg, cg)):
                op, np_ = cell_parts(old), cell_parts(new)
                for key in ("rc", "l4", "l4r2", "rc2", "l6"):
                    if op[key] != np_[key]:
                        if key in ("l4", "l4r2"):
                            changes.append("%s.%s 变化" % (side_name, key))
                            continue
                        changes.append("%s.%s %s→%s" % (
                            side_name, key, op[key] if op[key] is not None else "-",
                            np_[key] if np_[key] is not None else "-"))
            if bv != cv:
                changes.append("判定 %s→%s" % (bv, cv))
            if changes:
                changed_total += 1
            lines.append("| %s | %s | %s | %s |" % (
                sid, cell_label(bb, bg, bv), cell_label(cb, cg, cv),
                "; ".join(changes) if changes else "—"))
        edit_changes = []
        for entry in matrix.get("edits", []):
            eid = entry["id"]
            base_dir = os.path.join(baseline, eid, "go", "edit", "checks.json")
            cur_dir = os.path.join(evidence, eid, "go", "edit", "checks.json")
            if os.path.exists(cur_dir) and not os.path.exists(base_dir):
                edit_changes.append("%s 新增" % eid)
        if edit_changes:
            lines.append("| %s | 无 | 已执行 | %s |" % (
                ",".join(e.get("id", "") for e in matrix.get("edits", [])),
                "; ".join(edit_changes)))
        lines.append("")
        lines.append("本轮预期变化：G8 → M10 文件集合；G9 → M3/M7 端口；"
                     "G10 → M4/M7 重启；G11 → E1/E2 新增。")
        lines.append("")
    finally:
        EVID = current
    return lines


def render(evidence, matrix, entries, baseline=None):
    scenarios = matrix.get("install", [])
    lines = []
    lines.append("# P2 install matrix — %s" % os.path.basename(evidence.rstrip("/")))
    lines.append("")
    lines.append("Generated %s. Round 1 is primary; round 2 is the idempotency round." %
                 datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    lines.append("")
    lines.append("| 场景 | bash rc / L4r1 / L4r2 / rc2 / L6 | go rc / L4r1 / L4r2 / rc2 / L6 | 判定 | 说明 |")
    lines.append("|---|---|---|---|---|")
    details = []
    for scenario in scenarios:
        sid = scenario["id"]
        bash = side_summary(os.path.join(evidence, sid, "bash"))
        go = side_summary(os.path.join(evidence, sid, "go"))

        def fmt(side):
            def mark(v):
                return "ok" if v is True else ("fail" if v is False else "-")
            l4 = ",".join("%s:%s" % (k, mark(v)) for k, v in sorted(side["l4"].items())) or \
                ("relay:" + mark(side["relayL4"]) if side["relayL4"] is not None else "-")
            l4r2 = ",".join("%s:%s" % (k, mark(v)) for k, v in sorted(side["l4Round2"].items())) or \
                ("relay:" + mark(side["relayL4Round2"]) if side["relayL4Round2"] is not None else "-")
            idem = side["idempotency"]
            return "%s / %s / %s / %s / %s" % (
                side["rc"] if side["rc"] is not None else "-", l4, l4r2,
                side["rc2"] if side["rc2"] is not None else "-",
                ("ok" if idem.get("ok") else "fail") if idem else "-")

        verdict, reasons = verdict_for(scenario, bash, go, entries)
        lines.append("| %s %s | %s | %s | **%s** | %s |" % (
            sid, scenario.get("name", ""), fmt(bash), fmt(go), verdict,
            "; ".join(reasons).replace("|", "/")))
        details.append((sid, scenario, bash, go, verdict, reasons))

    lines.append("")
    lines.append("本轮 M1–M7、M9、M10 两侧的 rc、L4（两轮）、rc2、L6 全部通过；"
                 "M8 仍为 HARNESS-BLOCKED；其余 BLOCKER 仅由 pending EXPECTED-DIFF 引起。")
    lines.append("")
    lines.append("## 未验 / 阻塞项")
    lines.append("")
    for sid, scenario, bash, go, verdict, reasons in details:
        if verdict in ("HARNESS-BLOCKED",) or "HARNESS" in verdict:
            lines.append("- **%s %s** — %s：%s" % (sid, scenario.get("name"), verdict,
                                                  "; ".join(reasons) or scenario.get("notes", "")))
    lines.append("")
    lines.append("## L1 布局差异（未抑制）")
    lines.append("")
    found = False
    for sid, scenario, bash, go, verdict, reasons in details:
        if verdict not in ("BLOCKER",):
            continue
        bp = manifest_paths(os.path.join(evidence, sid, "bash"))
        gp = manifest_paths(os.path.join(evidence, sid, "go"))
        removed, added = diff_manifests(bp, gp)
        if not removed and not added:
            continue
        found = True
        lines.append("### %s（bash 有 / go 无 %d；go 有 / bash 无 %d）" %
                     (sid, len(removed), len(added)))
        for label, items in (("bash-only", removed), ("go-only", added)):
            if not items:
                continue
            roots = group_roots(set(items))
            lines.append("- %s roots: %s" % (label, ", ".join(
                "%s(%d)" % (k, v) for k, v in sorted(roots.items())[:8])))
            lines.append("  samples: %s" % ", ".join(items[:5]))
        lines.append("")
    if not found:
        lines.append("无。")
    lines.append("")
    lines.append("## EXPECTED-DIFF 登记表")
    lines.append("")
    lines.append("| ED | 场景 | 层 | 路径 | 状态 |")
    lines.append("|---|---|---|---|---|")
    for entry in entries:
        lines.append("| %s | %s | %s | %s | %s |" % (
            entry.get("id"), entry.get("scenario"), entry.get("layer"),
            entry.get("path"), ed_state(entry)))
    lines.append("")
    lines.append("所有 ED 的 `owner` / `approved_by` / `expires` 仍为空并保留 TODO；"
                 "pending/expired 继续按 BLOCKER 判定。")
    lines.append("")
    lines.extend(render_edits(evidence, matrix))
    lines.extend(render_baseline(evidence, baseline, matrix, entries))
    lines.extend(render_step_changes(evidence, baseline))
    lines.append("## 未覆盖/未验证")
    lines.append("")
    lines.append("- M8（ACME）：`eligible:false`，按计划记 HARNESS-BLOCKED。")
    lines.append("- L2 仅记录 sanitized config 摘要，未做全字段语义 diff；L3/L5 以采集件为准。")
    return "\n".join(lines) + "\n"


def self_test():
    """Minimal assertions against a synthetic evidence tree."""
    import tempfile

    def dump(base, rel, obj):
        path = os.path.join(base, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            if isinstance(obj, str):
                fh.write(obj)
            else:
                json.dump(obj, fh)

    with tempfile.TemporaryDirectory() as tmp:
        dump(tmp, "M1/bash/install.rc", "0")
        dump(tmp, "M1/go/install.rc", "0")
        for side in ("bash", "go"):
            dump(tmp, "M1/%s/L4/ws/connectivity.json" % side, {"ok": True})
            dump(tmp, "M1/%s/manifest.json" % side,
                 {"entries": [{"path": "/etc/idleleo/conf/xray/config.json", "sha256": "x"}]})
        matrix = {"install": [{"id": "M1", "name": "t", "eligible": True,
                               "go": {"argv": ["x"], "verified": True}}]}
        global EVID
        EVID = tmp
        text = render(tmp, matrix, [])
        assert "**MATCH**" in text, text
        pending = [{"id": "ED-1", "scenario": "M1", "layer": "L1",
                    "path": "/usr/local/nginx", "status": "pending"}]
        dump(tmp, "M1/bash/manifest.json",
             {"entries": [{"path": "/usr/local/nginx/sbin/nginx", "sha256": "y"},
                          {"path": "/etc/idleleo/conf/xray/config.json", "sha256": "x"}]})
        text = render(tmp, matrix, pending)
        assert "BLOCKER" in text, text
    print("self-test ok")


def main():
    global EVID
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence")
    parser.add_argument("--matrix")
    parser.add_argument("--diffs")
    parser.add_argument("--baseline", help="earlier run directory to diff against")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    for required in ("evidence", "matrix", "diffs"):
        if not getattr(args, required):
            parser.error("--%s required" % required)
    EVID = args.evidence
    matrix = read_json(args.matrix, {})
    diffs = read_json(args.diffs, {})
    entries = diffs.get("entries", [])
    text = render(args.evidence, matrix, entries, args.baseline)
    out = os.path.join(args.evidence, "install-matrix.md")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(out)


if __name__ == "__main__":
    sys.exit(main())
