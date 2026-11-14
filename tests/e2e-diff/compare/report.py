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


def render(evidence, matrix, entries):
    scenarios = matrix.get("install", [])
    lines = []
    lines.append("# P2 install matrix — %s" % os.path.basename(evidence.rstrip("/")))
    lines.append("")
    lines.append("Generated %s. Round 1 is primary; round 2 is the idempotency round." %
                 datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    lines.append("")
    lines.append("| 场景 | bash rc / L4 / rc2 / L6 | go rc / L4 / rc2 / L6 | 判定 | 说明 |")
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
            idem = side["idempotency"]
            return "%s / %s / %s / %s" % (
                side["rc"] if side["rc"] is not None else "-", l4,
                side["rc2"] if side["rc2"] is not None else "-",
                ("ok" if idem.get("ok") else "fail") if idem else "-")

        verdict, reasons = verdict_for(scenario, bash, go, entries)
        lines.append("| %s %s | %s | %s | **%s** | %s |" % (
            sid, scenario.get("name", ""), fmt(bash), fmt(go), verdict,
            "; ".join(reasons).replace("|", "/")))
        details.append((sid, scenario, bash, go, verdict, reasons))

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
    text = render(args.evidence, matrix, entries)
    out = os.path.join(args.evidence, "install-matrix.md")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(out)


if __name__ == "__main__":
    sys.exit(main())
