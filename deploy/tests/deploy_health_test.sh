#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_SCRIPT="$(cd "${SCRIPT_DIR}/.." && pwd)/deploy.sh"
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

cat > "${FAKE_BIN}/docker" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_DOCKER_LOG}"
if [ "${1:-}" = "--version" ]; then
    echo 'Docker version test'
    exit 0
fi
if [ "${1:-}" = "compose" ]; then
    if [ "${2:-}" = "version" ]; then
        echo 'Docker Compose version test'
    fi
    if printf '%s\n' "$*" | grep -q ' up '; then
        if [ "${FAKE_COMPOSE_UP:-up}" != "up" ]; then
            exit 17
        fi
    fi
    exit 0
fi
if [ "${1:-}" = "image" ] && [ "${2:-}" = "prune" ]; then
    exit 0
fi
exit 0
SCRIPT

cat > "${FAKE_BIN}/curl" <<'SCRIPT'
#!/bin/bash
url=''
for argument in "$@"; do
    url="${argument}"
done

case "${url}" in
    http://localhost:8080/actuator/health)
        count_file="${FAKE_BACKEND_COUNT_FILE}"
        success_at="${FAKE_BACKEND_SUCCESS_AT:-0}"
        ;;
    http://public.test/actuator/health)
        count_file="${FAKE_PUBLIC_COUNT_FILE}"
        success_at="${FAKE_PUBLIC_SUCCESS_AT:-0}"
        ;;
    *)
        printf '%s\n' "${url}" >> "${FAKE_UNEXPECTED_CURL_LOG}"
        exit 64
        ;;
esac

count="$(cat "${count_file}")"
count=$((count + 1))
printf '%s\n' "${count}" > "${count_file}"
if [ "${success_at}" -gt 0 ] && [ "${count}" -ge "${success_at}" ]; then
    exit 0
fi
exit 22
SCRIPT

cat > "${FAKE_BIN}/sleep" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

chmod +x "${FAKE_BIN}/docker" "${FAKE_BIN}/curl" "${FAKE_BIN}/sleep"

write_env() {
    local env_file="$1"
    printf '%s\n' \
        'FITLOOP_TLS_ENABLED=false' \
        'FITLOOP_HTTP_COMPAT_ENABLED=true' \
        'FITLOOP_PUBLIC_BASE_URL=http://public.test' \
        'FITLOOP_AGENT_ENABLED=false' \
        'DEEPSEEK_API_KEY=' \
        'FITLOOP_JWT_SECRET=deploy-health-test-jwt-secret-32b-ok' \
        'FITLOOP_OTP_HASH_SECRET=deploy-health-test-otp-secret-32b-ok' \
        'FITLOOP_AGENT_SERVICE_KEY=deploy-health-test-agent-key-32b-ok' \
        'FITLOOP_AGENT_DELEGATION_SECRET=deploy-health-test-delegation-32b-ok' > "${env_file}"
}

run_deploy() {
    local case_dir="$1"
    local backend_success_at="$2"
    local public_success_at="$3"
    local compose_up="${4:-up}"

    mkdir -p "${case_dir}"
    write_env "${case_dir}/fitloop.env"
    : > "${case_dir}/docker.log"
    : > "${case_dir}/unexpected-curl.log"
    printf '0\n' > "${case_dir}/backend-curl.count"
    printf '0\n' > "${case_dir}/public-curl.count"
    set +e
    PATH="${FAKE_BIN}:${PATH}" \
        FAKE_DOCKER_LOG="${case_dir}/docker.log" \
        FAKE_BACKEND_COUNT_FILE="${case_dir}/backend-curl.count" \
        FAKE_PUBLIC_COUNT_FILE="${case_dir}/public-curl.count" \
        FAKE_UNEXPECTED_CURL_LOG="${case_dir}/unexpected-curl.log" \
        FAKE_BACKEND_SUCCESS_AT="${backend_success_at}" \
        FAKE_PUBLIC_SUCCESS_AT="${public_success_at}" \
        FAKE_COMPOSE_UP="${compose_up}" \
        FITLOOP_ENV_FILE="${case_dir}/fitloop.env" \
        FITLOOP_DEPLOY_HEALTH_ATTEMPTS=2 \
        FITLOOP_DEPLOY_HEALTH_INTERVAL_SECONDS=0 \
        bash "${DEPLOY_SCRIPT}" cn >"${case_dir}/output.log" 2>&1
    local result=$?
    set -e
    if [ -s "${case_dir}/unexpected-curl.log" ]; then
        cat "${case_dir}/unexpected-curl.log" >&2
        fail "deploy used an unexpected health URL"
    fi
    return "${result}"
}

failure_dir="${TEST_ROOT}/backend-down"
if run_deploy "${failure_dir}" 0 1; then
    fail "backend-down: deploy unexpectedly succeeded"
fi
if grep -F '部署完成' "${failure_dir}/output.log" >/dev/null; then
    fail "backend-down: deploy printed a success message"
fi
if ! grep -F 'logs --tail=100 backend' \
    "${failure_dir}/docker.log" >/dev/null; then
    fail "backend-down: deploy did not collect backend diagnostics"
fi
if grep -F 'image prune' "${failure_dir}/docker.log" >/dev/null; then
    fail "backend-down: deploy pruned images after a failed release"
fi
if [ "$(cat "${failure_dir}/backend-curl.count")" -ne 2 ]; then
    fail "backend-down: unexpected health retry count"
fi
if [ "$(cat "${failure_dir}/public-curl.count")" -ne 0 ]; then
    fail "backend-down: deploy checked the public endpoint after backend failure"
fi
echo "[PASS] backend-down-fails-closed"

success_dir="${TEST_ROOT}/backend-up"
if ! run_deploy "${success_dir}" 1 1; then
    cat "${success_dir}/output.log" >&2
    fail "backend-up: deploy failed"
fi
if ! grep -F '部署完成' "${success_dir}/output.log" >/dev/null; then
    fail "backend-up: deploy did not print the success message"
fi
if ! grep -F 'image prune' "${success_dir}/docker.log" >/dev/null; then
    fail "backend-up: deploy did not reach post-success cleanup"
fi
if [ "$(cat "${success_dir}/backend-curl.count")" -ne 1 ]; then
    fail "backend-up: first-success path performed extra health checks"
fi
if [ "$(cat "${success_dir}/public-curl.count")" -ne 1 ]; then
    fail "backend-up: public endpoint was not checked exactly once"
fi
echo "[PASS] backend-and-public-first-check-succeed"

delayed_success_dir="${TEST_ROOT}/backend-delayed"
if ! run_deploy "${delayed_success_dir}" 2 1; then
    cat "${delayed_success_dir}/output.log" >&2
    fail "backend-delayed: deploy failed"
fi
if [ "$(cat "${delayed_success_dir}/backend-curl.count")" -ne 2 ]; then
    fail "backend-delayed: unexpected health retry count"
fi
if grep -F '部署判定失败' "${delayed_success_dir}/output.log" >/dev/null; then
    fail "backend-delayed: deploy reported a timeout after success"
fi
echo "[PASS] backend-delayed-succeeds"

public_failure_dir="${TEST_ROOT}/public-failure"
if run_deploy "${public_failure_dir}" 1 0; then
    fail "public-failure: deploy unexpectedly succeeded"
fi
if ! grep -F 'logs --tail=100 nginx' \
    "${public_failure_dir}/docker.log" >/dev/null; then
    fail "public-failure: deploy did not collect Nginx diagnostics"
fi
if grep -F 'image prune' "${public_failure_dir}/docker.log" >/dev/null; then
    fail "public-failure: deploy pruned images after a failed release"
fi
if grep -F '部署完成' "${public_failure_dir}/output.log" >/dev/null; then
    fail "public-failure: deploy printed a success message"
fi
if [ "$(cat "${public_failure_dir}/public-curl.count")" -ne 2 ]; then
    fail "public-failure: unexpected public health retry count"
fi
echo "[PASS] public-down-fails-closed"

compose_failure_dir="${TEST_ROOT}/compose-failure"
if run_deploy "${compose_failure_dir}" 1 1 "fail"; then
    fail "compose-failure: deploy unexpectedly succeeded"
fi
if [ "$(cat "${compose_failure_dir}/backend-curl.count")" -ne 0 ] ||
   [ "$(cat "${compose_failure_dir}/public-curl.count")" -ne 0 ]; then
    fail "compose-failure: deploy performed a health check after startup failed"
fi
if grep -F '部署完成' "${compose_failure_dir}/output.log" >/dev/null; then
    fail "compose-failure: deploy printed a success message"
fi
echo "[PASS] compose-up-failure-stops"

echo "All deployment health gate tests passed."
