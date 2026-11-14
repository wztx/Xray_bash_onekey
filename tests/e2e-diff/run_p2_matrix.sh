#!/usr/bin/env bash
# P2 runner: M1-M10 x {bash,go} x 2 rounds (fresh + repeat install).
#
# Concurrency unit is one scenario (both sides run sequentially inside it), with
# a dedicated docker network per scenario. At most E2E_CONCURRENCY scenarios run
# at once.
#
# Round 1 is the primary evidence. Round 2 is the idempotency round and lives in
# <side>/round2. Go round 2 uses --keep-config explicitly; bash round 2 takes the
# interactive keep-config path. Both sides must report rc=0 for round 2.
#
# M3 and M10 are first-class Go scenarios: the Go installer now adds a
# transport alongside Reality and installs a real relay (managed Nginx stream)
# instead of being recorded as a capability gap.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROOT
SUITE="$ROOT/tests/e2e-diff"
RUN_ID="${E2E_RUN_ID:-$(date +%Y%m%d-%H%M)-$(git -C "$ROOT" rev-parse --short HEAD)}"
EVID="$SUITE/evidence/$RUN_ID/p2"
WORK="/tmp/e2e-$RUN_ID"
IMAGE_TAG="${E2E_IMAGE_TAG:-idleleo-e2e:24.04}"
GO_IMAGE="${E2E_GO_IMAGE:-golang:1.27.4}"
DOMAIN="${E2E_DOMAIN:-example.com}"
TARGET="${E2E_TARGET:-www.cloudflare.com}"
LOCAL_IP="${E2E_LOCAL_IP:-127.0.0.1}"
RELAY_HOST="${E2E_RELAY_HOST:-origin.example.com}"
RELAY_PORT="${E2E_RELAY_PORT:-443}"
CONCURRENCY="${E2E_CONCURRENCY:-5}"
ONLY="${E2E_ONLY:-}"

source "$ROOT/tests/go-parity/lib/docker_common.sh"

mkdir -p "$EVID" "$WORK/seed/cert" "$WORK/secret"
log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$EVID/run.log"; }

PIN_ARGS=()
pin_host() {
    local h=$1 ip
    while read -r ip; do
        [[ -n "$ip" ]] && PIN_ARGS+=(--add-host "$h:$ip")
    done < <(dscacheutil -q host -a name "$h" 2>/dev/null | awk '/^ip_address:/{print $2}')
}
for h in raw.githubusercontent.com cdn.jsdelivr.net \
         objects.githubusercontent.com release-assets.githubusercontent.com; do
    pin_host "$h"
done
if [[ -n "${E2E_GITHUB_IP:-}" ]]; then
    PIN_ARGS+=(--add-host "github.com:$E2E_GITHUB_IP")
else
    pin_host github.com
fi

matrix_get() {
    python3 - "$SUITE/matrix.json" "$1" "$2" <<'PY'
import json, sys
matrix = json.load(open(sys.argv[1]))
sid, path = sys.argv[2], sys.argv[3]
scenario = next(x for x in matrix['install'] if x['id'] == sid)
cur = scenario
for part in path.split('.'):
    if not isinstance(cur, dict):
        cur = None
        break
    cur = cur.get(part)
if cur is None or cur == "":
    print("")
elif isinstance(cur, bool):
    print("true" if cur else "false")
elif isinstance(cur, (list, dict)):
    print(json.dumps(cur, ensure_ascii=False))
else:
    print(cur)
PY
}

json_list() {
    python3 -c 'import json,sys; print("\n".join(str(x) for x in json.loads(sys.argv[1])))' "$1"
}

# --- prerequisites ---------------------------------------------------------
log "run_id=$RUN_ID"
docker build -q -t "$IMAGE_TAG" -f "$SUITE/image/Dockerfile" "$SUITE/image" >/dev/null || {
    log "FATAL: image build failed"; exit 2
}
IMAGE_ID=$(docker image inspect -f '{{.Id}}' "$IMAGE_TAG")
log "image_id=$IMAGE_ID"

log "building idleleo"
docker run --rm -v "$ROOT:/src:ro" -v "$WORK/seed:/out" -w /src \
    -e CGO_ENABLED=0 -e GOFLAGS=-mod=vendor -e GOPROXY=off -e GOTOOLCHAIN=local \
    "$GO_IMAGE" go build -buildvcs=false -trimpath -o /out/idleleo ./cmd/idleleo || {
    log "FATAL: idleleo build failed"; exit 2
}

ARCH=$(docker_arch) || exit 2
if [[ -x "$ROOT/tests/go-parity/.cache/a2/xray" ]]; then
    XRAY_BIN="$ROOT/tests/go-parity/.cache/a2/xray"
else
    XRAY_BIN=$(ensure_xray_bin "$ARCH") || exit 2
fi
cp "$XRAY_BIN" "$WORK/seed/xray"
chmod 0755 "$WORK/seed/xray"
log "xray_sha256=$(host_sha256 "$WORK/seed/xray") idleleo_sha256=$(host_sha256 "$WORK/seed/idleleo")"

docker run --rm -v "$WORK/seed:/seed" "$IMAGE_TAG" bash -c \
    "openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj '/CN=$DOMAIN' \
     -addext 'subjectAltName=DNS:$DOMAIN' \
     -keyout /seed/cert/xray.key -out /seed/cert/xray.crt >/dev/null 2>&1" || {
    log "FATAL: certificate generation failed"; exit 2
}

python3 - "$SUITE/matrix.json" >"$EVID/run.json" <<PY
import json
matrix = json.load(open("$SUITE/matrix.json"))
print(json.dumps({
    "runId": "$RUN_ID",
    "commit": "$(git -C "$ROOT" rev-parse HEAD)",
    "branch": "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)",
    "imageId": "$IMAGE_ID",
    "matrixFrozenAt": matrix.get("frozenAt"),
    "decisions": matrix.get("decisions"),
}, indent=2, sort_keys=True))
PY

# --- argv verification evidence (T1) --------------------------------------
write_argv_verify() {
    local out="$EVID/argv-verify.md" tmpc="p2-argv-$RUN_ID"
    docker rm -f "$tmpc" >/dev/null 2>&1 || true
    docker run -d --name "$tmpc" -v "$WORK/seed:/seed:ro" "$IMAGE_TAG" sleep infinity >/dev/null || return 1
    docker exec "$tmpc" install -m 0755 /seed/idleleo /usr/local/bin/idleleo
    docker exec "$tmpc" mkdir -p /tmp/probe
    {
        echo "# Go argv verification ($RUN_ID)"
        echo
        echo "方法：\`idleleo <cmd> --help\` 只输出总览，无法逐 flag 核实。改用两条硬证据："
        echo "1) 未知 flag 会被 checkFlags 拒绝（rc=2, \`unknown flag: X\`）；"
        echo "2) \`idleleo xray generate\` 不写系统路径，能验证 mode/transport 组合。"
        echo
        for sid in M1 M2 M3 M4 M5 M6 M7 M9 M10; do
            local argv_json; argv_json=$(matrix_get "$sid" go.argv)
            echo "## $sid"
            echo
            echo '```'
            if [[ -z "$argv_json" ]]; then
                echo "install argv: null"
            else
                echo "install argv: $(json_list "$argv_json" | tr '\n' ' ')"
            fi
            echo '```'
            echo
        done
        echo "## generate probes"
        echo
        echo '```'
        while IFS='|' read -r label args; do
            echo "### $label"
            docker exec "$tmpc" sh -c "idleleo xray generate $args --out /tmp/g.json --force >/tmp/probe.out 2>&1; rc=\$?; tail -3 /tmp/probe.out; echo rc=\$rc" 2>&1
        done <<'PROBES'
M1|--mode reality --domain www.cloudflare.com --target www.cloudflare.com --port 443
M2|--mode reality-nginx --domain www.cloudflare.com --target www.cloudflare.com --port 443
M2-alias|--mode reality --nginx-bin /usr/local/nginx/sbin/nginx --domain www.cloudflare.com --target www.cloudflare.com --port 443
M3|--mode reality --transport ws --domain www.cloudflare.com --target www.cloudflare.com --port 443
M4|--mode tls --transport ws --domain example.com
M5|--mode tls --transport grpc --domain example.com
M6|--mode tls --transport xhttp --domain example.com
M7|--mode tls --transport ws+grpc+xhttp --domain example.com
M9|--mode none --transport ws --listen 0.0.0.0 --allow-non-loopback
PROBES
        echo '```'
        echo
        echo "## relay conf probe (M10)"
        echo
        echo '```'
        docker exec "$tmpc" sh -c "idleleo xray relay --target origin.example.com:443 --listen-port 443 --out /tmp/relay.conf" 2>&1 | tail -3
        docker exec "$tmpc" cat /tmp/relay.conf 2>/dev/null || true
        echo '```'
        echo
        echo "M10 install argv 走真实安装路径验证（见 M10/go/install.rc 与 L4），不在探针容器里拉取 Nginx。"
    } >"$out"
    docker rm -f "$tmpc" >/dev/null 2>&1 || true
    log "argv-verify written"
}
write_argv_verify

# --- helpers ---------------------------------------------------------------
start_server() {
    local name=$1 sid=$2 side=$3 out=$4 net=$5
    docker rm -f "$name" >/dev/null 2>&1 || true
    mkdir -p "$out"
    # shellcheck disable=SC2046
    docker run -d --name "$name" --hostname "$name" --network "$net" \
        --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock \
        "${PIN_ARGS[@]+"${PIN_ARGS[@]}"}" $(cgroup_mount_args) \
        -v "$ROOT:/src:ro" -v "$WORK/seed:/seed:ro" -v "$out:/out" \
        --label "e2e.run=$RUN_ID" --label "e2e.scenario=$sid" --label "e2e.side=$side" \
        "$IMAGE_TAG" /usr/lib/systemd/systemd >/dev/null
}

l4_transports() {
    case $1 in
        M1|M2) echo "reality" ;;
        M3) echo "reality ws" ;;
        M4) echo "ws" ;;
        M5) echo "grpc" ;;
        M6) echo "xhttp" ;;
        M7) echo "ws grpc xhttp" ;;
        M9) echo "ws" ;;
        *) echo "" ;;
    esac
}

run_l4() {
    local sid=$1 side=$2 server=$3 out=$4 net=$5 profile=$6 round=$7
    if [[ "$round" == "2" ]]; then
        out="$out/round2"
        mkdir -p "$out"
    fi
    local transport
    for transport in $(l4_transports "$sid"); do
        local client="e2e-$RUN_ID-$sid-$side-r$round-$transport"
        local secret="$WORK/secret/$sid-$side-r$round-$transport"
        E2E_L4_URL="http://example.com/" E2E_L4_MARKER="Example Domain" \
            bash "$SUITE/collect/l4.sh" "$server" "$client" "$IMAGE_TAG" "$net" \
                "$profile" "$DOMAIN" "$WORK/seed/xray" "$secret" "$out/L4/$transport" \
                "$transport" >"$out/L4-$transport.log" 2>&1
        local rc=$?
        echo "{\"transport\":\"$transport\",\"rc\":$rc}" >>"$out/L4/round$round.jsonl" \
            || true
    done
}

start_relay_origin() {
    local sid=$1 net=$2 origin="e2e-$RUN_ID-$sid-origin"
    docker rm -f "$origin" >/dev/null 2>&1 || true
    # The origin must be up before the relay install: Nginx resolves the
    # backend hostname when it loads the config, and origin.example.com would
    # otherwise resolve to a public address instead of the docker alias.
    docker run -d --name "$origin" --network "$net" --network-alias "$RELAY_HOST" \
        "$IMAGE_TAG" bash -c \
        "mkdir -p /origin && printf 'Example Domain relay-ok\n' >/origin/index.html && cd /origin && python3 -m http.server $RELAY_PORT --bind 0.0.0.0" \
        >/dev/null
    sleep 2
}

relay_l4() {
    local sid=$1 side=$2 server=$3 out=$4 net=$5 round=$6
    if [[ "$round" == "2" ]]; then
        out="$out/round2"
        mkdir -p "$out"
    fi
    local client="e2e-$RUN_ID-$sid-$side-r$round-relay"
    docker rm -f "$client" >/dev/null 2>&1 || true
    docker run --rm --network "$net" --name "$client" "$IMAGE_TAG" \
        bash -c "curl -fsS --max-time 10 http://$server:$RELAY_PORT/" \
        >"$out/L4-relay.out" 2>"$out/L4-relay.err"
    local rc=$?
    if ! grep -q "relay-ok" "$out/L4-relay.out" 2>/dev/null; then
        rc=3
    fi
    echo "{\"transport\":\"relay\",\"rc\":$rc}" >"$out/L4-relay.json"
}

run_bash_round() {
    local sid=$1 net=$2 server=$3 out=$4 round=$5 prev=$6 profile=$7 arg=$8 menu=$9 transport=${10}
    local target_out="/out"
    if [[ "$round" == "2" ]]; then
        target_out="/out/round2"
        out="$out/round2"
        mkdir -p "$out"
    fi
    local envs=(-e E2E_OUT="$target_out" -e E2E_ROUND="$round" -e E2E_SCENARIO="$sid"
                -e E2E_PROFILE="$profile" -e E2E_ARG="$arg" -e E2E_MENU="$menu"
                -e E2E_TRANSPORT="$transport" -e E2E_DOMAIN="$DOMAIN" -e E2E_TARGET="$TARGET"
                -e E2E_PORT=443 -e E2E_LOCAL_IP="$LOCAL_IP" -e E2E_RELAY_HOST="$RELAY_HOST"
                -e E2E_RELAY_PORT="$RELAY_PORT" -e E2E_PREV_OUT="/out"
                -e E2E_TIMEOUT="${E2E_TIMEOUT:-900}")
    # Round 2 tests config idempotency, not live takeover. Bash reinstall
    # replaces the binary before its port guard, so the still-running service
    # is no longer recognised and the guard rejects its own port. Stop the
    # services first on both sides so round 2 starts from a clean service state.
    if [[ "$round" == "2" ]]; then
        docker exec "$server" sh -c 'systemctl stop xray >/dev/null 2>&1; systemctl stop nginx >/dev/null 2>&1; true'
    fi
    docker exec "${envs[@]}" "$server" bash /src/tests/e2e-diff/drivers/bash_install.sh
    echo $? >"$out/install.rc"
}

run_go_round() {
    local sid=$1 server=$2 out=$3 round=$4 prev=$5 profile=$6; shift 6
    local -a argv=("$@")
    local target_out="/out"
    if [[ "$round" == "2" ]]; then
        target_out="/out/round2"
        out="$out/round2"
        mkdir -p "$out"
    fi
    if [[ "$round" == "2" ]]; then
        docker exec "$server" sh -c 'systemctl stop xray >/dev/null 2>&1; systemctl stop nginx >/dev/null 2>&1; true'
    fi
    docker exec -e E2E_OUT="$target_out" -e E2E_ROUND="$round" -e E2E_SCENARIO="$sid" \
        -e E2E_PROFILE="$profile" -e E2E_PREV_OUT=/out \
        "$server" bash /src/tests/e2e-diff/drivers/go_install.sh "${argv[@]}"
    echo $? >"$out/install.rc"
}

scenario_job() {
    local sid=$1
    local net="e2e-$RUN_ID-$sid"
    local eligible; eligible=$(matrix_get "$sid" eligible)
    local base="$EVID/$sid"
    mkdir -p "$base"
    if [[ "$eligible" != "true" ]]; then
        { echo "# $sid: HARNESS-BLOCKED"; echo; echo "$(matrix_get "$sid" notes)"; } >"$base/HARNESS-BLOCKED.md"
        log "[$sid] HARNESS-BLOCKED (ineligible)"
        return
    fi
    docker network create "$net" >/dev/null 2>&1 || true
    log "[$sid] start"

    local profile go_argv_json bash_arg bash_menu bash_transport
    go_argv_json=$(matrix_get "$sid" go.argv)
    bash_arg=""; bash_menu=""; bash_transport="1"
    case $sid in
        M1) profile=reality; bash_arg="-2" ;;
        M2|M3) profile=reality ;;
        M4|M5|M6|M7) profile=tls; bash_arg="-1" ;;
        M9) profile=none ;;
        M10) profile=relay; bash_arg="--install-relay" ;;
        *) profile=reality ;;
    esac
    case $sid in
        M4) bash_transport=1 ;;
        M5) bash_transport=2 ;;
        M6) bash_transport=3 ;;
        M7) bash_transport=5 ;;
        M3) bash_transport=1 ;;
    esac
    bash_menu=$(matrix_get "$sid" bash.menu)
    [[ -n "$(matrix_get "$sid" bash.transport)" ]] && bash_transport=$(matrix_get "$sid" bash.transport)

    if [[ "$profile" == "relay" ]]; then
        start_relay_origin "$sid" "$net"
    fi

    # ---- bash side ----
    local bserver="e2e-$RUN_ID-$sid-bash" bout="$base/bash"
    if start_server "$bserver" "$sid" bash "$bout" "$net"; then
        run_bash_round "$sid" "$net" "$bserver" "$bout" 1 "" "$profile" "$bash_arg" "$bash_menu" "$bash_transport"
        if [[ "$profile" == "relay" ]]; then relay_l4 "$sid" bash "$bserver" "$bout" "$net" 1; else
            run_l4 "$sid" bash "$bserver" "$bout" "$net" "$profile" 1
        fi
        run_bash_round "$sid" "$net" "$bserver" "$bout" 2 "$bout" "$profile" "$bash_arg" "$bash_menu" "$bash_transport"
        if [[ "$profile" == "relay" ]]; then relay_l4 "$sid" bash "$bserver" "$bout" "$net" 2; else
            run_l4 "$sid" bash "$bserver" "$bout" "$net" "$profile" 2
        fi
    else
        echo '{"status":"harness-error","reason":"container start failed"}' >"$bout/result.json"
    fi
    [[ "${E2E_KEEP:-0}" == "1" ]] || docker rm -f "$bserver" >/dev/null 2>&1 || true

    # ---- go side ----
    local gserver="e2e-$RUN_ID-$sid-go" gout="$base/go"
    if [[ -z "$go_argv_json" ]]; then
        mkdir -p "$gout"; echo '{"status":"harness-error","reason":"no go argv"}' >"$gout/result.json"
    elif start_server "$gserver" "$sid" go "$gout" "$net"; then
        GO_ARGV=()
        while IFS= read -r line; do GO_ARGV+=("$line"); done < <(json_list "$go_argv_json")
        run_go_round "$sid" "$gserver" "$gout" 1 "" "$profile" "${GO_ARGV[@]}"
        if [[ "$profile" == "relay" ]]; then relay_l4 "$sid" go "$gserver" "$gout" "$net" 1; else
            run_l4 "$sid" go "$gserver" "$gout" "$net" "$profile" 1
        fi
        run_go_round "$sid" "$gserver" "$gout" 2 "$gout" "$profile" "${GO_ARGV[@]}"
        if [[ "$profile" == "relay" ]]; then relay_l4 "$sid" go "$gserver" "$gout" "$net" 2; else
            run_l4 "$sid" go "$gserver" "$gout" "$net" "$profile" 2
        fi
    else
        mkdir -p "$gout"; echo '{"status":"harness-error","reason":"container start failed"}' >"$gout/result.json"
    fi
    [[ "${E2E_KEEP:-0}" == "1" ]] || docker rm -f "$gserver" >/dev/null 2>&1 || true
    docker rm -f "e2e-$RUN_ID-$sid-origin" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
    log "[$sid] done"
}

# --- scheduler -------------------------------------------------------------
SIDS=()
for sid in M1 M2 M3 M4 M5 M6 M7 M8 M9 M10; do
    if [[ -n "$ONLY" ]]; then
        case ",$ONLY," in *,${sid},*) ;; *) continue ;; esac
    fi
    SIDS+=("$sid")
done

# Batches of at most CONCURRENCY scenarios; macOS ships bash 3.2, which has no
# `wait -n`, so batches are the portable equivalent.
i=0
while (( i < ${#SIDS[@]} )); do
    batch=("${SIDS[@]:i:CONCURRENCY}")
    for sid in "${batch[@]}"; do
        scenario_job "$sid" &
    done
    wait
    i=$((i + CONCURRENCY))
done

python3 "$SUITE/compare/report.py" --evidence "$EVID" --matrix "$SUITE/matrix.json" \
    --diffs "$SUITE/expected_diffs.json" >/dev/null 2>&1 || \
    log "report generation failed"

log "P2 finished: $EVID"
