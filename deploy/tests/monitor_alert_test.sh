#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MONITOR_SCRIPT="$(cd "${SCRIPT_DIR}/.." && pwd)/monitor.sh"
TEST_ROOT="$(mktemp -d)"

cleanup() {
    case "${TEST_ROOT}" in
        ""|"/")
            echo "[FAIL] refusing unsafe test cleanup target" >&2
            return 1
            ;;
    esac
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT INT TERM

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

FAKE_BIN="${TEST_ROOT}/bin"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/top" <<'SCRIPT'
#!/bin/bash
echo 'Cpu(s): 1.0 us, 0.0 sy, 99.0 id'
SCRIPT

cat > "${FAKE_BIN}/free" <<'SCRIPT'
#!/bin/bash
printf '%s\n' \
    '              total        used        free' \
    'Mem:           1000         100         900'
SCRIPT

cat > "${FAKE_BIN}/df" <<'SCRIPT'
#!/bin/bash
printf '%s\n' \
    'Filesystem 1K-blocks Used Available Use% Mounted on' \
    '/dev/test      100000 1000     99000   1% /'
SCRIPT

cat > "${FAKE_BIN}/bc" <<'SCRIPT'
#!/bin/bash
cat >/dev/null
echo 0
SCRIPT

cat > "${FAKE_BIN}/uptime" <<'SCRIPT'
#!/bin/bash
echo '12:00:00 up 1 day, load average: 0.01, 0.02, 0.03'
SCRIPT

cat > "${FAKE_BIN}/nproc" <<'SCRIPT'
#!/bin/bash
echo 4
SCRIPT

cat > "${FAKE_BIN}/docker" <<'SCRIPT'
#!/bin/bash
if [ "${FAKE_DOCKER_AVAILABLE:-true}" != "true" ]; then
    exit 1
fi

service=''
previous=''
show_all=false
for argument in "$@"; do
    if [ "${previous}" = "--filter" ]; then
        service="${argument#name=}"
    fi
    if [ "${argument}" = "-a" ]; then
        show_all=true
    fi
    previous="${argument}"
done
if [ "${1:-}" != "ps" ]; then
    exit 99
fi
if [ -z "${service}" ]; then
    exit 0
fi
printf '%s\n' "${service}" >> "${FAKE_DOCKER_LOG}"
if [ "${show_all}" = true ]; then
    if [ "${FAKE_MISSING_SERVICE:-}" != "${service}" ]; then
        printf '%s\n' "${service}"
    fi
elif [ "${FAKE_MISSING_SERVICE:-}" = "${service}" ]; then
    exit 0
elif [ "${FAKE_DOWN_SERVICE:-}" = "${service}" ]; then
    exit 0
elif [ "${FAKE_UNHEALTHY_SERVICE:-}" = "${service}" ]; then
    echo 'Up 10 minutes (unhealthy)'
elif [ "${FAKE_STARTING_SERVICE:-}" = "${service}" ]; then
    echo 'Up 10 seconds (health: starting)'
elif [ "${FAKE_PAUSED_SERVICE:-}" = "${service}" ]; then
    echo 'Up 10 minutes (Paused)'
else
    echo 'Up 10 minutes (healthy)'
fi
SCRIPT

cat > "${FAKE_BIN}/curl" <<'SCRIPT'
#!/bin/bash
url=''
for argument in "$@"; do
    url="${argument}"
done
case "${url}" in
    *localhost:8080*)
        state="${FAKE_BACKEND_STATE:-up}"
        ;;
    *public.test*)
        state="${FAKE_PUBLIC_STATE:-up}"
        ;;
    *127.0.0.1:8090*)
        state="${FAKE_AGENT_STATE:-up}"
        ;;
    *)
        state="down"
        ;;
esac
if [ "${state}" = "up" ]; then
    printf '200'
    exit 0
fi
exit 22
SCRIPT

chmod +x "${FAKE_BIN}"/*

write_env() {
    local env_file="$1"
    local agent_enabled="$2"
    printf '%s\n' \
        "FITLOOP_AGENT_ENABLED=${agent_enabled}" \
        'FITLOOP_PUBLIC_BASE_URL=http://public.test' > "${env_file}"
}

run_monitor() {
    local case_dir="$1"
    local agent_enabled="$2"
    local backend_state="$3"
    local public_state="$4"
    local agent_state="${5:-up}"
    local docker_available="${6:-true}"
    local missing_service="${7:-}"
    local down_service="${8:-}"
    local unhealthy_service="${9:-}"
    local starting_service="${10:-}"
    local paused_service="${11:-}"

    mkdir -p "${case_dir}"
    write_env "${case_dir}/fitloop.env" "${agent_enabled}"
    : > "${case_dir}/docker.log"
    set +e
    PATH="${FAKE_BIN}:${PATH}" \
        FAKE_BACKEND_STATE="${backend_state}" \
        FAKE_PUBLIC_STATE="${public_state}" \
        FAKE_AGENT_STATE="${agent_state}" \
        FAKE_DOCKER_AVAILABLE="${docker_available}" \
        FAKE_MISSING_SERVICE="${missing_service}" \
        FAKE_DOWN_SERVICE="${down_service}" \
        FAKE_UNHEALTHY_SERVICE="${unhealthy_service}" \
        FAKE_STARTING_SERVICE="${starting_service}" \
        FAKE_PAUSED_SERVICE="${paused_service}" \
        FAKE_DOCKER_LOG="${case_dir}/docker.log" \
        FITLOOP_ENV_FILE="${case_dir}/fitloop.env" \
        bash "${MONITOR_SCRIPT}" --alert >"${case_dir}/output.log" 2>&1
    local result=$?
    set -e
    MONITOR_EXIT="${result}"
    return "${result}"
}

assert_alert_exit() {
    local case_name="$1"
    if [ "${MONITOR_EXIT}" -ne 2 ]; then
        fail "${case_name}: expected alert exit 2, got ${MONITOR_EXIT}"
    fi
}

healthy_dir="${TEST_ROOT}/healthy"
if ! run_monitor "${healthy_dir}" "false" "up" "up" "up" "true" \
    "fitloop-agent-service"; then
    cat "${healthy_dir}/output.log" >&2
    fail "healthy: disabled and absent Agent triggered an alert"
fi
for service in fitloop-mysql fitloop-redis fitloop-backend fitloop-nginx; do
    if ! grep -Fx "${service}" "${healthy_dir}/docker.log" >/dev/null; then
        fail "healthy: core service was not checked: ${service}"
    fi
done
if grep -Fx "fitloop-agent-service" "${healthy_dir}/docker.log" >/dev/null; then
    fail "healthy: disabled Agent container was checked"
fi
echo "[PASS] healthy-agent-disabled"

backend_down_dir="${TEST_ROOT}/backend-down"
if run_monitor "${backend_down_dir}" "false" "down" "up"; then
    fail "backend-down: monitor unexpectedly succeeded"
fi
assert_alert_exit "backend-down"
if ! grep -F 'BACKEND:UNHEALTHY' "${backend_down_dir}/output.log" >/dev/null; then
    fail "backend-down: missing backend alert"
fi
echo "[PASS] backend-down"

public_down_dir="${TEST_ROOT}/public-down"
if run_monitor "${public_down_dir}" "false" "up" "down"; then
    fail "public-down: monitor unexpectedly succeeded"
fi
assert_alert_exit "public-down"
if ! grep -F 'PUBLIC:UNHEALTHY' "${public_down_dir}/output.log" >/dev/null; then
    fail "public-down: missing public alert"
fi
echo "[PASS] public-down"

container_down_dir="${TEST_ROOT}/container-down"
if run_monitor "${container_down_dir}" "false" "up" "up" "up" "true" \
    "" "fitloop-backend"; then
    fail "container-down: monitor unexpectedly succeeded"
fi
assert_alert_exit "container-down"
if ! grep -F 'CONTAINER:fitloop-backend:DOWN' \
    "${container_down_dir}/output.log" >/dev/null; then
    fail "container-down: missing container alert"
fi
echo "[PASS] container-down"

container_unhealthy_dir="${TEST_ROOT}/container-unhealthy"
if run_monitor "${container_unhealthy_dir}" "false" "up" "up" "up" "true" \
    "" "" "fitloop-backend"; then
    fail "container-unhealthy: monitor unexpectedly succeeded"
fi
assert_alert_exit "container-unhealthy"
if ! grep -F 'CONTAINER:fitloop-backend:UNHEALTHY' \
    "${container_unhealthy_dir}/output.log" >/dev/null; then
    fail "container-unhealthy: missing container alert"
fi
echo "[PASS] container-unhealthy"

container_starting_dir="${TEST_ROOT}/container-starting"
if run_monitor "${container_starting_dir}" "false" "up" "up" "up" "true" \
    "" "" "" "fitloop-mysql"; then
    fail "container-starting: monitor unexpectedly succeeded"
fi
assert_alert_exit "container-starting"
if ! grep -F 'CONTAINER:fitloop-mysql:UNHEALTHY' \
    "${container_starting_dir}/output.log" >/dev/null; then
    fail "container-starting: missing container alert"
fi
echo "[PASS] container-health-starting"

container_paused_dir="${TEST_ROOT}/container-paused"
if run_monitor "${container_paused_dir}" "false" "up" "up" "up" "true" \
    "" "" "" "" "fitloop-nginx"; then
    fail "container-paused: monitor unexpectedly succeeded"
fi
assert_alert_exit "container-paused"
if ! grep -F 'CONTAINER:fitloop-nginx:UNHEALTHY' \
    "${container_paused_dir}/output.log" >/dev/null; then
    fail "container-paused: missing container alert"
fi
echo "[PASS] container-paused"

agent_down_dir="${TEST_ROOT}/agent-down"
if run_monitor "${agent_down_dir}" "true" "up" "up" "down"; then
    fail "agent-down: monitor unexpectedly succeeded"
fi
assert_alert_exit "agent-down"
if ! grep -F 'AGENT:NOT_READY' "${agent_down_dir}/output.log" >/dev/null; then
    fail "agent-down: missing Agent readiness alert"
fi
echo "[PASS] agent-enabled-not-ready"

docker_unavailable_dir="${TEST_ROOT}/docker-unavailable"
if run_monitor "${docker_unavailable_dir}" "false" "up" "up" "up" "false"; then
    fail "docker-unavailable: monitor unexpectedly succeeded"
fi
assert_alert_exit "docker-unavailable"
if ! grep -F 'DOCKER:UNAVAILABLE' \
    "${docker_unavailable_dir}/output.log" >/dev/null; then
    fail "docker-unavailable: missing Docker alert"
fi
echo "[PASS] docker-unavailable"

echo "All monitoring alert gate tests passed."
