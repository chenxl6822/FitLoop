#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SCRIPT="$(cd "${SCRIPT_DIR}/.." && pwd)/backup.sh"
TEST_ROOT="$(mktemp -d)"
REAL_GZIP="$(command -v gzip)"

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
if [ "${1:-}" = "ps" ]; then
    if [ "${FAKE_DOCKER_CONTAINER:-false}" = "true" ]; then
        printf '%s\n' 'fitloop-mysql'
    fi
    exit 0
fi
if [ "${1:-}" = "exec" ]; then
    printf '%s\n' "$@" > "${FAKE_DOCKER_ARGS_FILE}"
    shift
    if [ "${1:-}" = "-i" ]; then
        shift
    fi
    if [ "$#" -lt 2 ]; then
        echo 'docker exec did not receive a container and command' >&2
        exit 97
    fi
    shift
    "$@"
    exit $?
fi
exit 99
SCRIPT

cat > "${FAKE_BIN}/mysqldump" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" > "${FAKE_ARGS_FILE}"
for argument in "$@"; do
    case "${argument}" in
        --defaults-extra-file=*)
            printf '%s\n' "${argument#*=}" > "${FAKE_CLIENT_CONFIG_PATH_FILE}"
            cp "${argument#*=}" "${FAKE_CLIENT_CONFIG_COPY}"
            ;;
    esac
done
case "${FAKE_DUMP_MODE:-success}" in
    success)
        printf '%s\n' \
            '-- synthetic dump' \
            'CREATE TABLE regression_test (id INT);'
        ;;
    fail-empty)
        echo 'synthetic mysqldump failure' >&2
        exit 23
        ;;
    fail-partial)
        printf '%s\n' '-- partial dump'
        echo 'synthetic mysqldump partial failure' >&2
        exit 24
        ;;
    *)
        echo "unknown FAKE_DUMP_MODE" >&2
        exit 98
        ;;
esac
SCRIPT

cat > "${FAKE_BIN}/gzip" <<SCRIPT
#!/bin/bash
if [ "\${FAKE_GZIP_FAIL:-false}" = "true" ] && [ "\$#" -eq 0 ]; then
    echo 'synthetic gzip failure' >&2
    exit 17
fi
exec "${REAL_GZIP}" "\$@"
SCRIPT

chmod +x "${FAKE_BIN}/docker" "${FAKE_BIN}/mysqldump" "${FAKE_BIN}/gzip"

write_env() {
    local env_file="$1"
    local password_line="${2:-MYSQL_PASSWORD=literal-password}"
    printf '%s\n' \
        'MYSQL_DATABASE=fitloop_test' \
        'MYSQL_USER=fitloop_test' \
        "${password_line}" > "${env_file}"
}

run_backup() {
    local case_dir="$1"
    local dump_mode="$2"
    local gzip_fail="$3"
    local backup_mode="${4:-direct}"
    local docker_container="${5:-false}"

    mkdir -p "${case_dir}/backups"
    set +e
    PATH="${FAKE_BIN}:${PATH}" \
        FAKE_ARGS_FILE="${case_dir}/mysqldump.args" \
        FAKE_DUMP_MODE="${dump_mode}" \
        FAKE_GZIP_FAIL="${gzip_fail}" \
        FAKE_DOCKER_CONTAINER="${docker_container}" \
        FAKE_DOCKER_ARGS_FILE="${case_dir}/docker-exec.args" \
        FAKE_CLIENT_CONFIG_COPY="${case_dir}/mysql-client.cnf" \
        FAKE_CLIENT_CONFIG_PATH_FILE="${case_dir}/mysql-client.path" \
        FITLOOP_BACKUP_MODE="${backup_mode}" \
        FITLOOP_ENV_FILE="${case_dir}/fitloop.env" \
        FITLOOP_BACKUP_DIR="${case_dir}/backups" \
        bash "${BACKUP_SCRIPT}" >"${case_dir}/output.log" 2>&1
    local result=$?
    set -e
    return "${result}"
}

assert_failed_without_artifact() {
    local name="$1"
    local dump_mode="$2"
    local gzip_fail="$3"
    local case_dir="${TEST_ROOT}/${name}"

    mkdir -p "${case_dir}/backups"
    write_env "${case_dir}/fitloop.env"
    printf '%s\n' 'known-good-existing-backup' \
        > "${case_dir}/backups/fitloop_existing.sql.gz"
    local existing_hash
    existing_hash="$(
        sha256sum "${case_dir}/backups/fitloop_existing.sql.gz" | awk '{print $1}'
    )"
    if run_backup "${case_dir}" "${dump_mode}" "${gzip_fail}"; then
        fail "${name}: backup unexpectedly succeeded"
    fi
    if [ "$(
        sha256sum "${case_dir}/backups/fitloop_existing.sql.gz" | awk '{print $1}'
    )" != "${existing_hash}" ]; then
        fail "${name}: failed backup changed the existing backup"
    fi
    if [ -n "$(find "${case_dir}/backups" -type f \
        ! -name 'fitloop_existing.sql.gz' -print -quit)" ]; then
        find "${case_dir}/backups" -type f -print >&2
        fail "${name}: failed backup left a new artifact"
    fi
    echo "[PASS] ${name}"
}

assert_failed_without_artifact "empty-dump-failure" "fail-empty" "false"
assert_failed_without_artifact "partial-dump-failure" "fail-partial" "false"
assert_failed_without_artifact "gzip-failure" "success" "true"

missing_password_dir="${TEST_ROOT}/missing-password"
mkdir -p "${missing_password_dir}"
printf '%s\n' \
    'MYSQL_DATABASE=fitloop_test' \
    'MYSQL_USER=fitloop_test' > "${missing_password_dir}/fitloop.env"
if run_backup "${missing_password_dir}" "success" "false"; then
    fail "missing-password: backup unexpectedly succeeded"
fi
if [ -e "${missing_password_dir}/mysqldump.args" ]; then
    fail "missing-password: mysqldump ran before configuration validation"
fi
echo "[PASS] missing-password"

docker_missing_dir="${TEST_ROOT}/docker-missing"
mkdir -p "${docker_missing_dir}"
write_env "${docker_missing_dir}/fitloop.env"
if run_backup "${docker_missing_dir}" "success" "false" "docker" "false"; then
    fail "docker-missing: backup unexpectedly fell back to a direct connection"
fi
if [ -e "${docker_missing_dir}/mysqldump.args" ]; then
    fail "docker-missing: mysqldump ran without the required container"
fi
echo "[PASS] docker-missing-refuses-fallback"

success_dir="${TEST_ROOT}/success"
marker_file="${success_dir}/dotenv-command-ran"
mkdir -p "${success_dir}"
write_env \
    "${success_dir}/fitloop.env" \
    "MYSQL_PASSWORD=\$(touch ${marker_file})"
if ! run_backup "${success_dir}" "success" "false"; then
    cat "${success_dir}/output.log" >&2
    fail "success: backup failed"
fi
if [ -e "${marker_file}" ]; then
    fail "success: dotenv command substitution was executed"
fi

mapfile -t backup_files < <(
    find "${success_dir}/backups" -maxdepth 1 -type f -name 'fitloop_*.sql.gz'
)
if [ "${#backup_files[@]}" -ne 1 ]; then
    fail "success: expected exactly one final backup"
fi
"${REAL_GZIP}" -t "${backup_files[0]}"
if ! "${REAL_GZIP}" -cd "${backup_files[0]}" |
    grep -F 'CREATE TABLE regression_test' >/dev/null; then
    fail "success: backup content is missing"
fi
if ! grep -F -- "password=\"\$(touch ${marker_file})\"" \
    "${success_dir}/mysql-client.cnf" >/dev/null; then
    fail "success: dotenv value was not written literally"
fi
if grep -F -- "touch ${marker_file}" \
    "${success_dir}/mysqldump.args" >/dev/null; then
    fail "success: password leaked into mysqldump arguments"
fi
success_client_config_path="$(cat "${success_dir}/mysql-client.path")"
if [ -e "${success_client_config_path}" ]; then
    fail "success: temporary MySQL client config was not removed"
fi
if ! grep -F -- '--no-tablespaces' \
    "${success_dir}/mysqldump.args" >/dev/null; then
    fail "success: mysqldump did not disable tablespace metadata"
fi
echo "[PASS] success-and-literal-dotenv"

docker_success_dir="${TEST_ROOT}/docker-success"
mkdir -p "${docker_success_dir}"
write_env "${docker_success_dir}/fitloop.env"
if ! run_backup "${docker_success_dir}" "success" "false" "docker" "true"; then
    cat "${docker_success_dir}/output.log" >&2
    fail "docker-success: backup failed"
fi
if ! grep -F -- '--databases' "${docker_success_dir}/mysqldump.args" >/dev/null; then
    fail "docker-success: container mysqldump was not invoked"
fi
if ! grep -F -- 'exec' "${docker_success_dir}/docker-exec.args" >/dev/null; then
    fail "docker-success: docker exec was not invoked"
fi
if grep -F -- '-hlocalhost' "${docker_success_dir}/mysqldump.args" >/dev/null; then
    fail "docker-success: test unexpectedly used the direct connection path"
fi
if ! grep -F -- '--no-tablespaces' \
    "${docker_success_dir}/mysqldump.args" >/dev/null; then
    fail "docker-success: mysqldump did not disable tablespace metadata"
fi
if grep -F -- 'literal-password' \
    "${docker_success_dir}/docker-exec.args" >/dev/null; then
    fail "docker-success: password leaked into docker exec arguments"
fi
if ! grep -F -- 'password="literal-password"' \
    "${docker_success_dir}/mysql-client.cnf" >/dev/null; then
    fail "docker-success: container did not receive the client config"
fi
docker_client_config_path="$(cat "${docker_success_dir}/mysql-client.path")"
if [ -e "${docker_client_config_path}" ]; then
    fail "docker-success: container client config was not removed"
fi
if [ "$(find "${docker_success_dir}/backups" -maxdepth 1 -type f \
    -name 'fitloop_*.sql.gz' | wc -l | tr -d '[:space:]')" -ne 1 ]; then
    fail "docker-success: expected exactly one final backup"
fi
echo "[PASS] docker-success"

echo "All backup regression tests passed."
