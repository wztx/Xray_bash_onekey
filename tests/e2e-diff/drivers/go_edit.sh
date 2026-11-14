#!/usr/bin/env bash
# Runs `idleleo xray config edit` after a real install and captures before/after
# evidence plus a machine-readable checks file.
#
# Usage:
#   bash go_edit.sh idleleo xray config edit --uuid <uuid> --yes --container --json
#
# Environment:
#   E2E_OUT       evidence directory for the scenario (required)
#   E2E_SCENARIO  E1 (before/after) | E2 (restart failure rollback)
#
# E2 injects a one-shot systemd failure: the first ExecStartPre creates the
# marker and exits non-zero, so the edit's restart fails but the rollback
# restart succeeds. That distinguishes a real rollback from a permanently
# broken service.
set -uo pipefail

OUT="${E2E_OUT:?E2E_OUT required}"
SCENARIO="${E2E_SCENARIO:?E2E_SCENARIO required}"
DIR="$OUT/edit"
CFG=/etc/idleleo/conf/xray/config.json
mkdir -p "$DIR"

log() { printf '%s\n' "$*" >>"$DIR/edit.log"; }
export IDLELEO_ALLOW_SYSTEM_WRITES=I_ACCEPT_CONTAINER_ONLY

sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

cp "$CFG" "$DIR/before-config.json" 2>/dev/null || log "missing $CFG"
sha_before=$(sha_of "$CFG")
idleleo show --json >"$DIR/before-show.json" 2>&1 || true
idleleo xray share --path "$CFG" --public-port 443 --json \
    >"$DIR/before-share.json" 2>&1 || true

if [[ "$SCENARIO" == "E2" ]]; then
    mkdir -p /etc/systemd/system/xray.service.d
    cat >/etc/systemd/system/xray.service.d/e2e-fail-once.conf <<'EOF'
[Service]
ExecStartPre=/bin/sh -c "if [ ! -f /tmp/e2e-xray-failed-once ]; then touch /tmp/e2e-xray-failed-once; exit 1; fi"
EOF
    rm -f /tmp/e2e-xray-failed-once
    systemctl daemon-reload
    log "injected one-shot restart failure"
fi

log "edit_argv=$*"
set +e
/usr/local/bin/idleleo xray config edit "${@:2}" >"$DIR/edit.json" 2>"$DIR/edit.err"
edit_rc=$?
set -e
log "edit_exit=$edit_rc"

# The rollback restart is asynchronous; give the unit a moment to settle.
for _ in $(seq 1 10); do
    [[ "$(systemctl is-active xray 2>/dev/null)" == "active" ]] && break
    sleep 1
done

sha_after=$(sha_of "$CFG")
state=$(systemctl is-active xray 2>/dev/null || true)
backups=$(find /etc/idleleo/backup -maxdepth 1 -type d -name 'edit-*' 2>/dev/null | wc -l | tr -d ' ')
cp "$CFG" "$DIR/after-config.json" 2>/dev/null || true
idleleo show --json >"$DIR/after-show.json" 2>&1 || true
idleleo xray share --path "$CFG" --public-port 443 --json \
    >"$DIR/after-share.json" 2>&1 || true

python3 - "$DIR" "$SCENARIO" "$edit_rc" "$sha_before" "$sha_after" "$state" "$backups" <<'PY'
import json
import os
import sys

(directory, scenario, edit_rc, sha_before, sha_after, state, backups) = sys.argv[1:8]
edit_rc = int(edit_rc)
backups = int(backups)


def read_json(name, default):
    try:
        with open(os.path.join(directory, name)) as fh:
            return json.load(fh)
    except Exception:
        return default


err = ""
try:
    with open(os.path.join(directory, "edit.err")) as fh:
        err = fh.read()
except Exception:
    pass

after_cfg = read_json("after-config.json", {})
clients = []
try:
    for inbound in after_cfg.get("inbounds", []):
        clients += inbound.get("settings", {}).get("clients", [])
except Exception:
    pass
uuids = {c.get("id") for c in clients if isinstance(c, dict)}
after_share = read_json("after-share.json", {})

checks = {
    "editRcZero": edit_rc == 0,
    "editRcNonZero": edit_rc != 0,
    "configChanged": bool(sha_before) and sha_before != sha_after,
    "configRestored": bool(sha_before) and sha_before == sha_after,
    "rollbackReported": "restored" in err,
    "serviceActive": state == "active",
    "backupExists": backups > 0,
    "uuidApplied": "99999999-8888-7777-6666-555555555555" in uuids,
    "shareUriUpdated": "99999999-8888-7777-6666-555555555555" in json.dumps(after_share),
}

wanted = {
    "E1": ["editRcZero", "configChanged", "uuidApplied", "shareUriUpdated", "serviceActive", "backupExists"],
    "E2": ["editRcNonZero", "rollbackReported", "configRestored", "serviceActive"],
}.get(scenario, [])

result = {
    "scenario": scenario,
    "editRc": edit_rc,
    "service": state,
    "backups": backups,
    "beforeSha": sha_before,
    "afterSha": sha_after,
    "checks": checks,
    "wanted": wanted,
    "allPassed": all(checks.get(name) for name in wanted) if wanted else False,
}
with open(os.path.join(directory, "checks.json"), "w") as fh:
    json.dump(result, fh, indent=2, sort_keys=True)
print(json.dumps(result, sort_keys=True))
PY

exit 0
