#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DEPLOY_DIR}/.." && pwd)"
INSTALL_SCRIPT="${DEPLOY_DIR}/install-apk.sh"
BUILD_APK_SCRIPT="${DEPLOY_DIR}/build-apk.ps1"
DOWNLOAD_PAGE="${DEPLOY_DIR}/download.html"
NGINX_CONFIG="${DEPLOY_DIR}/nginx.conf"
NGINX_TLS_CONFIG="${DEPLOY_DIR}/nginx.tls.conf"
NGINX_HTTPS_ONLY_CONFIG="${DEPLOY_DIR}/nginx.https-only.conf"
TEST_ROOT="$(mktemp -d)"
ORIGINAL_PATH="${PATH}"
TEST_COMMAND_PATH="${PATH}"
REAL_MV="$(command -v mv)"
REAL_SYNC="$(command -v sync)"
INSTALL_EXIT=0
INSTALL_TIMEOUT_SECONDS=20
LOCK_HOLDER_PID=""
LOCK_RELEASE_FILE=""
SYNC_FAIL_CALLS=""
SYNC_COUNTER_FILE=""
SYNC_LOG_FILE=""
MV_FAIL_PARENT=""
BUILD_POLICY_EXIT=0
BUILD_POLICY_OUTPUT=""

COMPATIBILITY_SIGNER="69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a"
WRONG_SIGNER="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

cleanup() {
    if [ -n "${LOCK_HOLDER_PID}" ]; then
        if [ -n "${LOCK_RELEASE_FILE}" ]; then
            : > "${LOCK_RELEASE_FILE}"
        fi
        kill "${LOCK_HOLDER_PID}" 2>/dev/null || true
        wait "${LOCK_HOLDER_PID}" 2>/dev/null || true
    fi
    case "${TEST_ROOT}" in
        ""|"/")
            echo "[FAIL] refusing unsafe test cleanup target" >&2
            return 1
            ;;
    esac
    find -P "${TEST_ROOT}" \
        -type d \
        -exec chmod u+rwx -- {} + \
        2>/dev/null || true
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT INT TERM

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

sha256_of() {
    sha256sum "$1" | awk '{print $1}'
}

bundle_content_digest() {
    local bundle_dir="$1"
    local file
    for file in \
        app-release.apk \
        app-release.apk.sha256 \
        version.json
    do
        sha256_of "${bundle_dir}/${file}"
    done | sha256sum | awk '{print $1}'
}

write_metadata() {
    local target="$1"
    local sha256="$2"
    local api_base_url="${3:-https://app.fitloop-health.cn}"
    local signer_sha256="${4:-${COMPATIBILITY_SIGNER}}"
    local signing_mode="${5:-Compatibility}"
    local apk_path="${6:-$(dirname "${target}")/app-release.apk}"
    local version="${7:-0.1.9}"
    local version_code="${8:-11}"
    local apk_size
    apk_size="$(
        python3 - "${apk_path}" <<'PY'
import os
import sys

size_mb = round(os.path.getsize(sys.argv[1]) / (1024 * 1024), 1)
print(f"{size_mb:.1f} MB")
PY
    )"

    cat > "${target}" <<JSON
{
  "version": "${version}",
  "versionCode": ${version_code},
  "size": "${apk_size}",
  "buildDate": "2026-07-26",
  "minSdkVersion": "Android 8.0 (API 26)",
  "apiBaseUrl": "${api_base_url}",
  "sha256": "${sha256}",
  "signerSha256": "${signer_sha256}",
  "signingMode": "${signing_mode}"
}
JSON
}

create_release() {
    local apk_root="$1"
    local apk_content="$2"
    local scratch_file="${TEST_ROOT}/release-apk.$$"
    printf '%s\n' "${apk_content}" > "${scratch_file}"
    local sha256
    sha256="$(sha256_of "${scratch_file}")"
    local release_dir="${apk_root}/releases/${sha256}"

    mkdir -p "${release_dir}"
    cp "${scratch_file}" "${release_dir}/app-release.apk"
    printf '%s  app-release.apk\n' "${sha256}" \
        > "${release_dir}/app-release.apk.sha256"
    write_metadata "${release_dir}/version.json" "${sha256}"
    chmod 0444 \
        "${release_dir}/app-release.apk" \
        "${release_dir}/app-release.apk.sha256" \
        "${release_dir}/version.json"
    chmod 0555 "${release_dir}"
    rm -f -- "${scratch_file}"
    printf '%s\n' "${sha256}"
}

prepare_case() {
    local case_dir="$1"
    mkdir -p "${case_dir}/fixture/deploy" "${case_dir}/source"
    cp "${INSTALL_SCRIPT}" "${case_dir}/fixture/deploy/install-apk.sh"

    printf 'new-apk-content\n' > "${case_dir}/source/app-release.apk"
    local new_sha256
    new_sha256="$(sha256_of "${case_dir}/source/app-release.apk")"
    write_metadata "${case_dir}/source/version.json" "${new_sha256}"
    printf '%s\n' "${new_sha256}" > "${case_dir}/new.sha256"
}

seed_active_state() {
    local case_dir="$1"
    local apk_root="${case_dir}/fixture/deploy/apk"
    mkdir -p "${apk_root}/releases" "${apk_root}/states/seed-state"
    chmod 0755 \
        "${apk_root}" \
        "${apk_root}/releases" \
        "${apk_root}/states"

    local previous_sha256
    local current_sha256
    previous_sha256="$(
        create_release "${apk_root}" "previous-apk-content"
    )"
    current_sha256="$(
        create_release "${apk_root}" "current-apk-content"
    )"

    ln -s "../../releases/${current_sha256}" \
        "${apk_root}/states/seed-state/current"
    ln -s "../../releases/${previous_sha256}" \
        "${apk_root}/states/seed-state/previous"
    chmod 0555 "${apk_root}/states/seed-state"
    ln -s "states/seed-state" "${apk_root}/active"

    printf '%s\n' "${current_sha256}" > "${case_dir}/current.sha256"
    printf '%s\n' "${previous_sha256}" > "${case_dir}/previous.sha256"
}

make_existing_case() {
    local case_dir="$1"
    prepare_case "${case_dir}"
    seed_active_state "${case_dir}"
}

create_legacy_flat_bundle() {
    local case_dir="$1"
    local apk_root="${case_dir}/fixture/deploy/apk"
    local apk_path="${apk_root}/app-release.apk"
    local metadata_path="${apk_root}/version.json"
    local sha256

    printf 'legacy-flat-apk-content\n' > "${apk_path}"
    sha256="$(sha256_of "${apk_path}")"
    printf '%s  app-release.apk\n' "${sha256}" \
        > "${apk_root}/app-release.apk.sha256"

    local apk_size
    apk_size="$(
        python3 - "${apk_path}" <<'PY'
import os
import sys

size_mb = round(os.path.getsize(sys.argv[1]) / (1024 * 1024), 1)
print(f"{size_mb:.1f} MB")
PY
    )"
    cat > "${metadata_path}" <<JSON
{
  "version": "0.1.5",
  "versionCode": 6,
  "size": "${apk_size}",
  "buildDate": "2026-07-20",
  "minSdkVersion": "Android 8.0 (API 26)",
  "apiBaseUrl": "http://legacy.fitloop-health.cn"
}
JSON
    chmod 0644 \
        "${apk_path}" \
        "${apk_root}/app-release.apk.sha256" \
        "${metadata_path}"
    printf '%s\n' "${sha256}" > "${case_dir}/legacy.sha256"
}

damage_release_apk() {
    local release_dir="$1"
    chmod 0644 "${release_dir}/app-release.apk"
    printf 'damaged-apk-content\n' > "${release_dir}/app-release.apk"
    chmod 0444 "${release_dir}/app-release.apk"
}

run_install() {
    local case_dir="$1"
    shift

    set +e
    (
        cd "${case_dir}/fixture"
        umask 077
        PATH="${TEST_COMMAND_PATH}" \
            REAL_MV="${REAL_MV}" \
            REAL_SYNC="${REAL_SYNC}" \
            FAIL_MARKER="${case_dir}/mv-failed-once" \
            SYNC_FAIL_CALLS="${SYNC_FAIL_CALLS}" \
            SYNC_COUNTER_FILE="${SYNC_COUNTER_FILE}" \
            SYNC_LOG_FILE="${SYNC_LOG_FILE}" \
            MV_FAIL_PARENT="${MV_FAIL_PARENT}" \
            timeout "${INSTALL_TIMEOUT_SECONDS}" \
                bash deploy/install-apk.sh "$@"
    ) > "${case_dir}/output.log" 2>&1
    INSTALL_EXIT=$?
    set -e
    return "${INSTALL_EXIT}"
}

configure_sync_failures() {
    local case_dir="$1"
    local fail_calls="$2"
    local fake_bin="${case_dir}/bin"
    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/sync" <<'SCRIPT'
#!/bin/bash
count=0
if [ -f "${SYNC_COUNTER_FILE}" ]; then
    count="$(cat "${SYNC_COUNTER_FILE}")"
fi
count=$((count + 1))
printf '%s\n' "${count}" > "${SYNC_COUNTER_FILE}"
printf '%s\n' "${count}" >> "${SYNC_LOG_FILE}"
case ",${SYNC_FAIL_CALLS}," in
    *",${count},"*)
        exit 75
        ;;
esac
exec "${REAL_SYNC}" "$@"
SCRIPT
    chmod +x "${fake_bin}/sync"
    TEST_COMMAND_PATH="${fake_bin}:${ORIGINAL_PATH}"
    SYNC_FAIL_CALLS="${fail_calls}"
    SYNC_COUNTER_FILE="${case_dir}/sync-counter"
    SYNC_LOG_FILE="${case_dir}/sync.log"
}

configure_restore_mv_failure() {
    local case_dir="$1"
    local fake_bin="${case_dir}/bin"
    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/mv" <<'SCRIPT'
#!/bin/bash
fail_restore=false
last_argument=""
for argument in "$@"; do
    last_argument="${argument}"
    case "${argument}" in
        */active.restore)
            fail_restore=true
            ;;
    esac
done
last_argument="${last_argument%/}"
if [ "${fail_restore}" = true ]; then
    case "${last_argument}" in
        deploy/apk/active|*/deploy/apk/active)
            : > "${FAIL_MARKER}"
            exit 73
            ;;
    esac
fi
exec "${REAL_MV}" "$@"
SCRIPT
    chmod +x "${fake_bin}/mv"
    TEST_COMMAND_PATH="${fake_bin}:${ORIGINAL_PATH}"
}

configure_finalize_mv_failure() {
    local case_dir="$1"
    local fail_parent="$2"
    local fake_bin="${case_dir}/bin"

    case "${fail_parent}" in
        releases|states)
            ;;
        *)
            fail "unsupported finalize mv failure parent: ${fail_parent}"
            ;;
    esac

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/mv" <<'SCRIPT'
#!/bin/bash
last_argument=""
for argument in "$@"; do
    last_argument="${argument}"
done
last_argument="${last_argument%/}"
case "${last_argument}" in
    */deploy/apk/${MV_FAIL_PARENT}/*)
        : > "${FAIL_MARKER}"
        exit 73
        ;;
esac
exec "${REAL_MV}" "$@"
SCRIPT
    chmod +x "${fake_bin}/mv"
    TEST_COMMAND_PATH="${fake_bin}:${ORIGINAL_PATH}"
    MV_FAIL_PARENT="${fail_parent}"
}

configure_signal_after_active_mv() {
    local case_dir="$1"
    local fake_bin="${case_dir}/bin"
    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/mv" <<'SCRIPT'
#!/bin/bash
last_argument=""
for argument in "$@"; do
    last_argument="${argument}"
done
last_argument="${last_argument%/}"
"${REAL_MV}" "$@"
move_status=$?
if [ "${move_status}" -eq 0 ]; then
    case "${last_argument}" in
        deploy/apk/active|*/deploy/apk/active)
            : > "${FAIL_MARKER}"
            kill -TERM "${PPID}"
            ;;
    esac
fi
exit "${move_status}"
SCRIPT
    chmod +x "${fake_bin}/mv"
    TEST_COMMAND_PATH="${fake_bin}:${ORIGINAL_PATH}"
}

reset_fault_injection() {
    TEST_COMMAND_PATH="${ORIGINAL_PATH}"
    SYNC_FAIL_CALLS=""
    SYNC_COUNTER_FILE=""
    SYNC_LOG_FILE=""
    MV_FAIL_PARENT=""
}

active_snapshot() {
    local case_dir="$1"
    local apk_root="${case_dir}/fixture/deploy/apk"
    local slot
    local file

    if [ ! -L "${apk_root}/active" ]; then
        printf 'active:not-a-symlink\n'
        return
    fi

    printf 'active:%s\n' "$(readlink "${apk_root}/active")"
    for slot in current previous; do
        if [ -L "${apk_root}/active/${slot}" ]; then
            printf '%s:%s\n' \
                "${slot}" "$(readlink "${apk_root}/active/${slot}")"
            for file in \
                app-release.apk \
                app-release.apk.sha256 \
                version.json
            do
                if [ -f "${apk_root}/active/${slot}/${file}" ]; then
                    printf '%s/%s:%s\n' \
                        "${slot}" \
                        "${file}" \
                        "$(sha256_of \
                            "${apk_root}/active/${slot}/${file}")"
                else
                    printf '%s/%s:missing\n' "${slot}" "${file}"
                fi
            done
        else
            printf '%s:missing\n' "${slot}"
        fi
    done
}

publication_tree_snapshot() {
    local case_dir="$1"
    local apk_root="${case_dir}/fixture/deploy/apk"
    if [ ! -d "${apk_root}" ]; then
        printf 'apk:missing\n'
        return
    fi

    (
        cd "${apk_root}"
        for root in releases states active; do
            if [ -L "${root}" ]; then
                printf 'link:%s:%s\n' "${root}" "$(readlink "${root}")"
            elif [ -d "${root}" ]; then
                printf 'dir:%s\n' "${root}"
            elif [ -e "${root}" ]; then
                printf 'other:%s\n' "${root}"
            else
                printf 'missing:%s\n' "${root}"
            fi
        done
        if [ -d releases ] || [ -d states ]; then
            find releases states -mindepth 1 -print0 2>/dev/null |
                sort -z |
                while IFS= read -r -d '' path; do
                    if [ -L "${path}" ]; then
                        printf 'link:%s:%s\n' \
                            "${path}" "$(readlink "${path}")"
                    elif [ -d "${path}" ]; then
                        printf 'dir:%s\n' "${path}"
                    elif [ -f "${path}" ]; then
                        printf 'file:%s:%s\n' \
                            "${path}" "$(sha256_of "${path}")"
                    else
                        printf 'other:%s\n' "${path}"
                    fi
                done
        fi
    )
}

assert_no_managed_staging() {
    local case_name="$1"
    local case_dir="$2"
    local apk_root="${case_dir}/fixture/deploy/apk"
    local staging_path

    if [ ! -d "${apk_root}/releases" ] ||
       [ -L "${apk_root}/releases" ] ||
       [ ! -d "${apk_root}/states" ] ||
       [ -L "${apk_root}/states" ]
    then
        fail "${case_name}: managed release/state parents are unavailable"
    fi
    if ! staging_path="$(
        find \
            "${apk_root}/releases" \
            "${apk_root}/states" \
            -mindepth 1 \
            -maxdepth 1 \
            \( \
                -name '.release-staging.*' -o \
                -name '.state-staging.*' \
            \) \
            -print \
            -quit \
            2>/dev/null
    )"; then
        fail "${case_name}: could not inspect managed staging paths"
    fi
    if [ -n "${staging_path}" ]; then
        fail "${case_name}: managed staging path was not cleaned: ${staging_path}"
    fi
}

assert_install_not_timed_out() {
    local case_name="$1"

    if [ "${INSTALL_EXIT}" -eq 124 ]; then
        fail \
            "${case_name}: installer exceeded ${INSTALL_TIMEOUT_SECONDS}-second test timeout"
    fi
}

assert_failure_unchanged() {
    local case_name="$1"
    local case_dir="$2"
    local before_snapshot="$3"

    if [ "${INSTALL_EXIT}" -eq 0 ]; then
        fail "${case_name}: install unexpectedly succeeded"
    fi
    assert_install_not_timed_out "${case_name}"

    local after_snapshot
    after_snapshot="$(active_snapshot "${case_dir}")"
    if [ "${after_snapshot}" != "${before_snapshot}" ]; then
        echo "--- before active state ---" >&2
        printf '%s\n' "${before_snapshot}" >&2
        echo "--- after active state ---" >&2
        printf '%s\n' "${after_snapshot}" >&2
        fail "${case_name}: active current/previous bundle changed"
    fi
    if grep -E \
        '^(Activated verified APK bundle|Imported and activated trusted legacy APK release|Rolled back to managed APK release)([[:space:]]|$)' \
        "${case_dir}/output.log" >/dev/null; then
        fail "${case_name}: failure path printed a success message"
    fi
    assert_no_managed_staging "${case_name}" "${case_dir}"
    pass "${case_name}"
}

assert_active_layout() {
    local case_name="$1"
    local case_dir="$2"
    local expected_current_sha256="$3"
    local expected_previous_sha256="${4:-}"
    local apk_root="${case_dir}/fixture/deploy/apk"

    if [ ! -L "${apk_root}/active" ]; then
        fail "${case_name}: active is not a symbolic link"
    fi
    local active_target
    active_target="$(readlink "${apk_root}/active")"
    case "${active_target}" in
        states/*)
            ;;
        *)
            fail "${case_name}: active does not point to states/<id>"
            ;;
    esac

    local state_dir="${apk_root}/${active_target}"
    if [ ! -d "${state_dir}" ]; then
        fail "${case_name}: active state directory is missing"
    fi
    if [ ! -L "${state_dir}/current" ]; then
        fail "${case_name}: current is not a symbolic link"
    fi
    if [ "$(readlink "${state_dir}/current")" \
         != "../../releases/${expected_current_sha256}" ]; then
        fail "${case_name}: current points to the wrong release"
    fi

    if [ -n "${expected_previous_sha256}" ]; then
        if [ ! -L "${state_dir}/previous" ]; then
            fail "${case_name}: previous is not a symbolic link"
        fi
        if [ "$(readlink "${state_dir}/previous")" \
             != "../../releases/${expected_previous_sha256}" ]; then
            fail "${case_name}: previous points to the wrong release"
        fi
    elif [ -e "${state_dir}/previous" ] || [ -L "${state_dir}/previous" ]; then
        fail "${case_name}: first install unexpectedly created previous"
    fi
    assert_no_managed_staging "${case_name}" "${case_dir}"
}

assert_published_bytes() {
    local case_name="$1"
    local case_dir="$2"
    local expected_sha256="$3"
    local current_dir="${case_dir}/fixture/deploy/apk/active/current"

    if ! cmp -s \
        "${case_dir}/source/app-release.apk" \
        "${current_dir}/app-release.apk"; then
        fail "${case_name}: published APK bytes differ from the source"
    fi
    if ! cmp -s \
        "${case_dir}/source/version.json" \
        "${current_dir}/version.json"; then
        fail "${case_name}: published metadata bytes differ from the source"
    fi
    if ! grep -Fx "${expected_sha256}  app-release.apk" \
        "${current_dir}/app-release.apk.sha256" >/dev/null; then
        fail "${case_name}: published checksum file is missing or wrong"
    fi
    if [ "$(sha256_of "${current_dir}/app-release.apk")" \
         != "${expected_sha256}" ]; then
        fail "${case_name}: published APK checksum is wrong"
    fi
}

assert_mode() {
    local path="$1"
    local expected_mode="$2"
    local actual_mode
    actual_mode="$(stat -c '%a' "${path}")"
    if [ "${actual_mode}" != "${expected_mode}" ]; then
        fail "${path}: expected mode ${expected_mode}, got ${actual_mode}"
    fi
}

missing_arguments_dir="${TEST_ROOT}/missing-arguments"
make_existing_case "${missing_arguments_dir}"
missing_arguments_before="$(active_snapshot "${missing_arguments_dir}")"
missing_arguments_sha="$(cat "${missing_arguments_dir}/new.sha256")"
run_install "${missing_arguments_dir}" \
    "file://${missing_arguments_dir}/source/app-release.apk" \
    "${missing_arguments_sha}" || true
if [ "${INSTALL_EXIT}" -ne 2 ]; then
    fail "missing-arguments: expected exit 2, got ${INSTALL_EXIT}"
fi
assert_failure_unchanged \
    "missing-arguments" \
    "${missing_arguments_dir}" \
    "${missing_arguments_before}"

empty_metadata_dir="${TEST_ROOT}/empty-metadata"
make_existing_case "${empty_metadata_dir}"
: > "${empty_metadata_dir}/source/version.json"
empty_metadata_before="$(active_snapshot "${empty_metadata_dir}")"
empty_metadata_sha="$(cat "${empty_metadata_dir}/new.sha256")"
run_install "${empty_metadata_dir}" \
    "file://${empty_metadata_dir}/source/app-release.apk" \
    "${empty_metadata_sha}" \
    "file://${empty_metadata_dir}/source/version.json" || true
assert_failure_unchanged \
    "empty-metadata" "${empty_metadata_dir}" "${empty_metadata_before}"

invalid_json_dir="${TEST_ROOT}/invalid-json"
make_existing_case "${invalid_json_dir}"
printf 'not-json\n' > "${invalid_json_dir}/source/version.json"
invalid_json_before="$(active_snapshot "${invalid_json_dir}")"
invalid_json_sha="$(cat "${invalid_json_dir}/new.sha256")"
run_install "${invalid_json_dir}" \
    "file://${invalid_json_dir}/source/app-release.apk" \
    "${invalid_json_sha}" \
    "file://${invalid_json_dir}/source/version.json" || true
assert_failure_unchanged \
    "invalid-json" "${invalid_json_dir}" "${invalid_json_before}"

missing_field_dir="${TEST_ROOT}/missing-field"
make_existing_case "${missing_field_dir}"
missing_field_sha="$(cat "${missing_field_dir}/new.sha256")"
cat > "${missing_field_dir}/source/version.json" <<JSON
{
  "version": "0.1.9",
  "versionCode": 11,
  "apiBaseUrl": "https://app.fitloop-health.cn",
  "sha256": "${missing_field_sha}"
}
JSON
missing_field_before="$(active_snapshot "${missing_field_dir}")"
run_install "${missing_field_dir}" \
    "file://${missing_field_dir}/source/app-release.apk" \
    "${missing_field_sha}" \
    "file://${missing_field_dir}/source/version.json" || true
assert_failure_unchanged \
    "missing-required-field" "${missing_field_dir}" "${missing_field_before}"

apk_checksum_dir="${TEST_ROOT}/apk-checksum-mismatch"
make_existing_case "${apk_checksum_dir}"
apk_checksum_before="$(active_snapshot "${apk_checksum_dir}")"
wrong_apk_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
write_metadata \
    "${apk_checksum_dir}/source/version.json" "${wrong_apk_sha}"
run_install "${apk_checksum_dir}" \
    "file://${apk_checksum_dir}/source/app-release.apk" \
    "${wrong_apk_sha}" \
    "file://${apk_checksum_dir}/source/version.json" || true
assert_failure_unchanged \
    "apk-checksum-mismatch" "${apk_checksum_dir}" "${apk_checksum_before}"

metadata_sha_dir="${TEST_ROOT}/metadata-sha-mismatch"
make_existing_case "${metadata_sha_dir}"
metadata_sha="$(cat "${metadata_sha_dir}/new.sha256")"
write_metadata \
    "${metadata_sha_dir}/source/version.json" \
    "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
metadata_sha_before="$(active_snapshot "${metadata_sha_dir}")"
run_install "${metadata_sha_dir}" \
    "file://${metadata_sha_dir}/source/app-release.apk" \
    "${metadata_sha}" \
    "file://${metadata_sha_dir}/source/version.json" || true
assert_failure_unchanged \
    "metadata-sha-mismatch" "${metadata_sha_dir}" "${metadata_sha_before}"

insecure_api_dir="${TEST_ROOT}/insecure-api"
make_existing_case "${insecure_api_dir}"
insecure_api_sha="$(cat "${insecure_api_dir}/new.sha256")"
write_metadata \
    "${insecure_api_dir}/source/version.json" \
    "${insecure_api_sha}" \
    "http://app.fitloop-health.cn"
insecure_api_before="$(active_snapshot "${insecure_api_dir}")"
run_install "${insecure_api_dir}" \
    "file://${insecure_api_dir}/source/app-release.apk" \
    "${insecure_api_sha}" \
    "file://${insecure_api_dir}/source/version.json" || true
assert_failure_unchanged \
    "api-base-url-requires-https" \
    "${insecure_api_dir}" \
    "${insecure_api_before}"

transition_without_approval_dir="${TEST_ROOT}/transition-without-approval"
make_existing_case "${transition_without_approval_dir}"
transition_without_approval_sha="$(
    cat "${transition_without_approval_dir}/new.sha256"
)"
write_metadata \
    "${transition_without_approval_dir}/source/version.json" \
    "${transition_without_approval_sha}" \
    "http://43.139.72.25"
transition_without_approval_before="$(
    active_snapshot "${transition_without_approval_dir}"
)"
run_install "${transition_without_approval_dir}" \
    "file://${transition_without_approval_dir}/source/app-release.apk" \
    "${transition_without_approval_sha}" \
    "file://${transition_without_approval_dir}/source/version.json" || true
assert_failure_unchanged \
    "http-transition-requires-explicit-approval" \
    "${transition_without_approval_dir}" \
    "${transition_without_approval_before}"

transition_verify_dir="${TEST_ROOT}/transition-verify"
make_existing_case "${transition_verify_dir}"
transition_verify_sha="$(cat "${transition_verify_dir}/new.sha256")"
write_metadata \
    "${transition_verify_dir}/source/version.json" \
    "${transition_verify_sha}" \
    "http://43.139.72.25"
transition_verify_before="$(
    publication_tree_snapshot "${transition_verify_dir}"
)"
if ! run_install "${transition_verify_dir}" \
    --verify-only \
    --allow-insecure-http-transition-release \
    "file://${transition_verify_dir}/source/app-release.apk" \
    "${transition_verify_sha}" \
    "file://${transition_verify_dir}/source/version.json"
then
    cat "${transition_verify_dir}/output.log" >&2
    fail "http-transition-verify: exact approved endpoint was rejected"
fi
transition_verify_after="$(
    publication_tree_snapshot "${transition_verify_dir}"
)"
if [ "${transition_verify_after}" != "${transition_verify_before}" ]; then
    fail "http-transition-verify: verify-only changed publication state"
fi
pass "http-transition-verify-only-exact-endpoint"

transition_activate_dir="${TEST_ROOT}/transition-activate"
make_existing_case "${transition_activate_dir}"
transition_activate_sha="$(cat "${transition_activate_dir}/new.sha256")"
transition_activate_previous_sha="$(
    cat "${transition_activate_dir}/current.sha256"
)"
write_metadata \
    "${transition_activate_dir}/source/version.json" \
    "${transition_activate_sha}" \
    "http://43.139.72.25"
if ! run_install "${transition_activate_dir}" \
    --allow-insecure-http-transition-release \
    "file://${transition_activate_dir}/source/app-release.apk" \
    "${transition_activate_sha}" \
    "file://${transition_activate_dir}/source/version.json"
then
    cat "${transition_activate_dir}/output.log" >&2
    fail "http-transition-activate: exact approved endpoint was rejected"
fi
assert_active_layout \
    "http-transition-activate" \
    "${transition_activate_dir}" \
    "${transition_activate_sha}" \
    "${transition_activate_previous_sha}"
assert_published_bytes \
    "http-transition-activate" \
    "${transition_activate_dir}" \
    "${transition_activate_sha}"
pass "http-transition-activate-exact-endpoint"

transition_policy_version_index=0
while IFS='|' read -r transition_policy_name version version_code; do
    transition_policy_version_index=$((transition_policy_version_index + 1))
    transition_policy_version_dir="$(
        printf '%s/http-transition-policy-version-%02d' \
            "${TEST_ROOT}" "${transition_policy_version_index}"
    )"
    make_existing_case "${transition_policy_version_dir}"
    transition_policy_version_sha="$(
        cat "${transition_policy_version_dir}/new.sha256"
    )"
    write_metadata \
        "${transition_policy_version_dir}/source/version.json" \
        "${transition_policy_version_sha}" \
        "http://43.139.72.25" \
        "${COMPATIBILITY_SIGNER}" \
        "Compatibility" \
        "${transition_policy_version_dir}/source/app-release.apk" \
        "${version}" \
        "${version_code}"
    transition_policy_version_before="$(
        active_snapshot "${transition_policy_version_dir}"
    )"
    run_install "${transition_policy_version_dir}" \
        --allow-insecure-http-transition-release \
        "file://${transition_policy_version_dir}/source/app-release.apk" \
        "${transition_policy_version_sha}" \
        "file://${transition_policy_version_dir}/source/version.json" || true
    assert_failure_unchanged \
        "http-transition-self-expires-${transition_policy_name}" \
        "${transition_policy_version_dir}" \
        "${transition_policy_version_before}"
done <<'TRANSITION_POLICY_VERSIONS'
version|0.1.8|11
version-code|0.1.9|10
TRANSITION_POLICY_VERSIONS

transition_http_download_index=0
while IFS='|' read -r transition_download_name apk_url version_url; do
    transition_http_download_index=$((transition_http_download_index + 1))
    transition_http_download_dir="$(
        printf '%s/http-transition-download-%02d' \
            "${TEST_ROOT}" "${transition_http_download_index}"
    )"
    make_existing_case "${transition_http_download_dir}"
    transition_http_download_sha="$(
        cat "${transition_http_download_dir}/new.sha256"
    )"
    write_metadata \
        "${transition_http_download_dir}/source/version.json" \
        "${transition_http_download_sha}" \
        "http://43.139.72.25"
    transition_http_download_before="$(
        active_snapshot "${transition_http_download_dir}"
    )"
    apk_url="${apk_url//CASE_DIR/${transition_http_download_dir}}"
    version_url="${version_url//CASE_DIR/${transition_http_download_dir}}"
    run_install "${transition_http_download_dir}" \
        --allow-insecure-http-transition-release \
        "${apk_url}" \
        "${transition_http_download_sha}" \
        "${version_url}" || true
    assert_failure_unchanged \
        "http-transition-rejects-${transition_download_name}" \
        "${transition_http_download_dir}" \
        "${transition_http_download_before}"
done <<'TRANSITION_HTTP_DOWNLOADS'
http-apk-download|http://43.139.72.25/apk/app-release.apk|file://CASE_DIR/source/version.json
http-metadata-download|file://CASE_DIR/source/app-release.apk|http://43.139.72.25/apk/version.json
TRANSITION_HTTP_DOWNLOADS

transition_variant_index=0
while IFS='|' read -r transition_variant_name transition_variant_url; do
    transition_variant_index=$((transition_variant_index + 1))
    transition_variant_dir="$(
        printf '%s/http-transition-variant-%02d' \
            "${TEST_ROOT}" "${transition_variant_index}"
    )"
    make_existing_case "${transition_variant_dir}"
    transition_variant_sha="$(cat "${transition_variant_dir}/new.sha256")"
    write_metadata \
        "${transition_variant_dir}/source/version.json" \
        "${transition_variant_sha}" \
        "${transition_variant_url}"
    transition_variant_before="$(
        active_snapshot "${transition_variant_dir}"
    )"
    run_install "${transition_variant_dir}" \
        --allow-insecure-http-transition-release \
        "file://${transition_variant_dir}/source/app-release.apk" \
        "${transition_variant_sha}" \
        "file://${transition_variant_dir}/source/version.json" || true
    assert_failure_unchanged \
        "http-transition-rejects-${transition_variant_name}" \
        "${transition_variant_dir}" \
        "${transition_variant_before}"
done <<'TRANSITION_VARIANTS'
trailing-slash|http://43.139.72.25/
explicit-port|http://43.139.72.25:80
path|http://43.139.72.25/api
query|http://43.139.72.25?source=test
fragment|http://43.139.72.25#test
credentials|http://user:password@43.139.72.25
other-public-ip|http://43.139.72.26
private-ip|http://192.168.1.10
localhost|http://localhost
hostname|http://app.fitloop-health.cn
https-with-transition-flag|https://43.139.72.25
TRANSITION_VARIANTS

transition_reverse_order_dir="${TEST_ROOT}/transition-reverse-order"
make_existing_case "${transition_reverse_order_dir}"
transition_reverse_order_before="$(
    active_snapshot "${transition_reverse_order_dir}"
)"
transition_reverse_order_sha="$(
    cat "${transition_reverse_order_dir}/new.sha256"
)"
run_install "${transition_reverse_order_dir}" \
    --allow-insecure-http-transition-release \
    --verify-only \
    "file://${transition_reverse_order_dir}/source/app-release.apk" \
    "${transition_reverse_order_sha}" \
    "file://${transition_reverse_order_dir}/source/version.json" || true
if [ "${INSTALL_EXIT}" -ne 2 ]; then
    cat "${transition_reverse_order_dir}/output.log" >&2
    fail "http-transition-reverse-option-order: expected exit 2"
fi
assert_failure_unchanged \
    "http-transition-reverse-option-order" \
    "${transition_reverse_order_dir}" \
    "${transition_reverse_order_before}"

transition_duplicate_flag_dir="${TEST_ROOT}/transition-duplicate-flag"
make_existing_case "${transition_duplicate_flag_dir}"
transition_duplicate_flag_before="$(
    active_snapshot "${transition_duplicate_flag_dir}"
)"
transition_duplicate_flag_sha="$(
    cat "${transition_duplicate_flag_dir}/new.sha256"
)"
run_install "${transition_duplicate_flag_dir}" \
    --verify-only \
    --allow-insecure-http-transition-release \
    --allow-insecure-http-transition-release \
    "file://${transition_duplicate_flag_dir}/source/app-release.apk" \
    "${transition_duplicate_flag_sha}" \
    "file://${transition_duplicate_flag_dir}/source/version.json" || true
if [ "${INSTALL_EXIT}" -ne 2 ]; then
    cat "${transition_duplicate_flag_dir}/output.log" >&2
    fail "http-transition-duplicate-flag: expected exit 2"
fi
assert_failure_unchanged \
    "http-transition-duplicate-flag" \
    "${transition_duplicate_flag_dir}" \
    "${transition_duplicate_flag_before}"

transition_rollback_flag_dir="${TEST_ROOT}/transition-rollback-flag"
make_existing_case "${transition_rollback_flag_dir}"
transition_rollback_flag_before="$(
    active_snapshot "${transition_rollback_flag_dir}"
)"
transition_rollback_flag_sha="$(
    cat "${transition_rollback_flag_dir}/previous.sha256"
)"
run_install "${transition_rollback_flag_dir}" \
    --rollback \
    --allow-insecure-http-transition-release \
    "${transition_rollback_flag_sha}" || true
if [ "${INSTALL_EXIT}" -ne 2 ]; then
    cat "${transition_rollback_flag_dir}/output.log" >&2
    fail "http-transition-rollback-flag: expected exit 2"
fi
assert_failure_unchanged \
    "http-transition-rollback-flag" \
    "${transition_rollback_flag_dir}" \
    "${transition_rollback_flag_before}"

transition_import_flag_dir="${TEST_ROOT}/transition-import-flag"
make_existing_case "${transition_import_flag_dir}"
transition_import_flag_before="$(
    active_snapshot "${transition_import_flag_dir}"
)"
transition_import_flag_sha="$(
    cat "${transition_import_flag_dir}/previous.sha256"
)"
run_install "${transition_import_flag_dir}" \
    --import-legacy \
    --allow-insecure-http-transition-release \
    "${transition_import_flag_sha}" || true
if [ "${INSTALL_EXIT}" -ne 2 ]; then
    cat "${transition_import_flag_dir}/output.log" >&2
    fail "http-transition-import-flag: expected exit 2"
fi
assert_failure_unchanged \
    "http-transition-import-flag" \
    "${transition_import_flag_dir}" \
    "${transition_import_flag_before}"

reserved_api_dir="${TEST_ROOT}/reserved-api"
make_existing_case "${reserved_api_dir}"
reserved_api_sha="$(cat "${reserved_api_dir}/new.sha256")"
write_metadata \
    "${reserved_api_dir}/source/version.json" \
    "${reserved_api_sha}" \
    "https://example.invalid"
reserved_api_before="$(active_snapshot "${reserved_api_dir}")"
run_install "${reserved_api_dir}" \
    "file://${reserved_api_dir}/source/app-release.apk" \
    "${reserved_api_sha}" \
    "file://${reserved_api_dir}/source/version.json" || true
assert_failure_unchanged \
    "reserved-api-domain" "${reserved_api_dir}" "${reserved_api_before}"

private_ip_api_dir="${TEST_ROOT}/private-ip-api"
make_existing_case "${private_ip_api_dir}"
private_ip_api_sha="$(cat "${private_ip_api_dir}/new.sha256")"
write_metadata \
    "${private_ip_api_dir}/source/version.json" \
    "${private_ip_api_sha}" \
    "https://192.168.1.10"
private_ip_api_before="$(active_snapshot "${private_ip_api_dir}")"
run_install "${private_ip_api_dir}" \
    "file://${private_ip_api_dir}/source/app-release.apk" \
    "${private_ip_api_sha}" \
    "file://${private_ip_api_dir}/source/version.json" || true
assert_failure_unchanged \
    "private-ip-api" "${private_ip_api_dir}" "${private_ip_api_before}"

public_ip_api_dir="${TEST_ROOT}/public-ip-api"
make_existing_case "${public_ip_api_dir}"
public_ip_api_sha="$(cat "${public_ip_api_dir}/new.sha256")"
write_metadata \
    "${public_ip_api_dir}/source/version.json" \
    "${public_ip_api_sha}" \
    "https://43.139.72.25"
public_ip_api_before="$(
    publication_tree_snapshot "${public_ip_api_dir}"
)"
if ! run_install "${public_ip_api_dir}" \
    --verify-only \
    "file://${public_ip_api_dir}/source/app-release.apk" \
    "${public_ip_api_sha}" \
    "file://${public_ip_api_dir}/source/version.json"; then
    cat "${public_ip_api_dir}/output.log" >&2
    fail "public-ip-api: valid public IP endpoint was rejected"
fi
public_ip_api_after="$(
    publication_tree_snapshot "${public_ip_api_dir}"
)"
if [ "${public_ip_api_after}" != "${public_ip_api_before}" ]; then
    fail "public-ip-api: verify-only changed publication state"
fi
pass "public-ip-api-accepted"

wrong_signer_dir="${TEST_ROOT}/wrong-signer"
make_existing_case "${wrong_signer_dir}"
wrong_signer_sha="$(cat "${wrong_signer_dir}/new.sha256")"
write_metadata \
    "${wrong_signer_dir}/source/version.json" \
    "${wrong_signer_sha}" \
    "https://app.fitloop-health.cn" \
    "${WRONG_SIGNER}"
wrong_signer_before="$(active_snapshot "${wrong_signer_dir}")"
run_install "${wrong_signer_dir}" \
    "file://${wrong_signer_dir}/source/app-release.apk" \
    "${wrong_signer_sha}" \
    "file://${wrong_signer_dir}/source/version.json" || true
assert_failure_unchanged \
    "wrong-compatibility-signer" \
    "${wrong_signer_dir}" \
    "${wrong_signer_before}"

malformed_signer_dir="${TEST_ROOT}/malformed-signer"
make_existing_case "${malformed_signer_dir}"
malformed_signer_sha="$(cat "${malformed_signer_dir}/new.sha256")"
write_metadata \
    "${malformed_signer_dir}/source/version.json" \
    "${malformed_signer_sha}" \
    "https://app.fitloop-health.cn" \
    "not-a-fingerprint"
malformed_signer_before="$(active_snapshot "${malformed_signer_dir}")"
run_install "${malformed_signer_dir}" \
    "file://${malformed_signer_dir}/source/app-release.apk" \
    "${malformed_signer_sha}" \
    "file://${malformed_signer_dir}/source/version.json" || true
assert_failure_unchanged \
    "malformed-signer" \
    "${malformed_signer_dir}" \
    "${malformed_signer_before}"

official_signing_dir="${TEST_ROOT}/official-signing"
make_existing_case "${official_signing_dir}"
official_signing_sha="$(cat "${official_signing_dir}/new.sha256")"
write_metadata \
    "${official_signing_dir}/source/version.json" \
    "${official_signing_sha}" \
    "https://app.fitloop-health.cn" \
    "${COMPATIBILITY_SIGNER}" \
    "Official"
official_signing_before="$(active_snapshot "${official_signing_dir}")"
run_install "${official_signing_dir}" \
    "file://${official_signing_dir}/source/app-release.apk" \
    "${official_signing_sha}" \
    "file://${official_signing_dir}/source/version.json" || true
assert_failure_unchanged \
    "official-signing-rejected" \
    "${official_signing_dir}" \
    "${official_signing_before}"

lock_dir="${TEST_ROOT}/concurrent-lock"
make_existing_case "${lock_dir}"
lock_before="$(active_snapshot "${lock_dir}")"
lock_sha="$(cat "${lock_dir}/new.sha256")"
lock_file="${lock_dir}/fixture/deploy/apk/.install.lock"
lock_ready="${lock_dir}/lock-ready"
LOCK_RELEASE_FILE="${lock_dir}/lock-release"
(
    exec 9> "${lock_file}"
    flock -x 9
    : > "${lock_ready}"
    while [ ! -f "${LOCK_RELEASE_FILE}" ]; do
        sleep 0.05
    done
) &
LOCK_HOLDER_PID=$!
for _ in {1..100}; do
    if [ -f "${lock_ready}" ]; then
        break
    fi
    sleep 0.05
done
if [ ! -f "${lock_ready}" ]; then
    fail "concurrent-lock: failed to acquire the external test lock"
fi
run_install "${lock_dir}" \
    "file://${lock_dir}/source/app-release.apk" \
    "${lock_sha}" \
    "file://${lock_dir}/source/version.json" || true
: > "${LOCK_RELEASE_FILE}"
wait "${LOCK_HOLDER_PID}"
LOCK_HOLDER_PID=""
LOCK_RELEASE_FILE=""
assert_failure_unchanged \
    "concurrent-install-is-rejected" "${lock_dir}" "${lock_before}"

lock_symlink_dir="${TEST_ROOT}/lock-symlink"
prepare_case "${lock_symlink_dir}"
mkdir -p "${lock_symlink_dir}/fixture/deploy/apk"
printf 'lock-target-sentinel\n' \
    > "${lock_symlink_dir}/fixture/deploy/apk/lock-target"
ln -s "lock-target" \
    "${lock_symlink_dir}/fixture/deploy/apk/.install.lock"
lock_symlink_sha="$(cat "${lock_symlink_dir}/new.sha256")"
run_install \
    "${lock_symlink_dir}" \
    "file://${lock_symlink_dir}/source/app-release.apk" \
    "${lock_symlink_sha}" \
    "file://${lock_symlink_dir}/source/version.json" || true
if [ "${INSTALL_EXIT}" -eq 0 ]; then
    fail "lock-symlink: install unexpectedly succeeded"
fi
if [ ! -L "${lock_symlink_dir}/fixture/deploy/apk/.install.lock" ] ||
   [ "$(cat "${lock_symlink_dir}/fixture/deploy/apk/lock-target")" \
     != "lock-target-sentinel" ]; then
    fail "lock-symlink: lock symlink target was changed"
fi
if ! grep -F \
    'Installer lock must not be a symbolic link' \
    "${lock_symlink_dir}/output.log" >/dev/null; then
    fail "lock-symlink: rejection was not logged"
fi
pass "lock-symlink-rejected"

lock_hardlink_dir="${TEST_ROOT}/lock-hardlink"
prepare_case "${lock_hardlink_dir}"
mkdir -p "${lock_hardlink_dir}/fixture/deploy/apk"
printf 'lock-hardlink-sentinel\n' > "${lock_hardlink_dir}/lock-source"
ln \
    "${lock_hardlink_dir}/lock-source" \
    "${lock_hardlink_dir}/fixture/deploy/apk/.install.lock"
lock_hardlink_sha="$(cat "${lock_hardlink_dir}/new.sha256")"
run_install \
    "${lock_hardlink_dir}" \
    "file://${lock_hardlink_dir}/source/app-release.apk" \
    "${lock_hardlink_sha}" \
    "file://${lock_hardlink_dir}/source/version.json" || true
if [ "${INSTALL_EXIT}" -eq 0 ]; then
    fail "lock-hardlink: install unexpectedly succeeded"
fi
if [ "$(stat -c '%h' "${lock_hardlink_dir}/lock-source")" -ne 2 ] ||
   [ "$(cat "${lock_hardlink_dir}/lock-source")" \
     != "lock-hardlink-sentinel" ]; then
    fail "lock-hardlink: hardlinked lock source was changed"
fi
if ! grep -F \
    'Existing installer lock must be singly linked and owned by the installer user' \
    "${lock_hardlink_dir}/output.log" >/dev/null; then
    fail "lock-hardlink: rejection was not logged"
fi
pass "lock-hardlink-rejected"

lock_owner_dir="${TEST_ROOT}/lock-non-owner"
prepare_case "${lock_owner_dir}"
mkdir -p "${lock_owner_dir}/fixture/deploy/apk"
printf 'lock-owner-sentinel\n' \
    > "${lock_owner_dir}/fixture/deploy/apk/.install.lock"
foreign_uid=65534
if [ "$(id -u)" -eq "${foreign_uid}" ]; then
    foreign_uid=65533
fi
lock_owner_test_ready=false
if [ "$(id -u)" -eq 0 ]; then
    chown "${foreign_uid}" \
        "${lock_owner_dir}/fixture/deploy/apk/.install.lock"
    lock_owner_test_ready=true
elif command -v sudo >/dev/null 2>&1 &&
     sudo -n true >/dev/null 2>&1; then
    sudo -n chown "${foreign_uid}" \
        "${lock_owner_dir}/fixture/deploy/apk/.install.lock"
    lock_owner_test_ready=true
fi
if [ "${lock_owner_test_ready}" = true ]; then
    lock_owner_sha="$(cat "${lock_owner_dir}/new.sha256")"
    run_install \
        "${lock_owner_dir}" \
        "file://${lock_owner_dir}/source/app-release.apk" \
        "${lock_owner_sha}" \
        "file://${lock_owner_dir}/source/version.json" || true
    if [ "${INSTALL_EXIT}" -eq 0 ]; then
        fail "lock-non-owner: install unexpectedly succeeded"
    fi
    if [ "$(cat "${lock_owner_dir}/fixture/deploy/apk/.install.lock")" \
         != "lock-owner-sentinel" ]; then
        fail "lock-non-owner: foreign lock file was changed"
    fi
    if ! grep -F \
        'Existing installer lock must be singly linked and owned by the installer user' \
        "${lock_owner_dir}/output.log" >/dev/null; then
        fail "lock-non-owner: rejection was not logged"
    fi
    pass "lock-non-owner-rejected"
else
    echo "[SKIP] lock-non-owner-rejected (chown is unavailable)"
fi

active_directory_dir="${TEST_ROOT}/active-directory"
prepare_case "${active_directory_dir}"
mkdir -p "${active_directory_dir}/fixture/deploy/apk/active"
printf 'do-not-delete\n' \
    > "${active_directory_dir}/fixture/deploy/apk/active/sentinel"
active_directory_sha="$(cat "${active_directory_dir}/new.sha256")"
run_install "${active_directory_dir}" \
    "file://${active_directory_dir}/source/app-release.apk" \
    "${active_directory_sha}" \
    "file://${active_directory_dir}/source/version.json" || true
if [ "${INSTALL_EXIT}" -eq 0 ]; then
    fail "active-is-directory: install unexpectedly succeeded"
fi
if [ "${INSTALL_EXIT}" -eq 124 ]; then
    fail "active-is-directory: install hung until the test timeout"
fi
if [ ! -d "${active_directory_dir}/fixture/deploy/apk/active" ] ||
   [ -L "${active_directory_dir}/fixture/deploy/apk/active" ] ||
   [ "$(cat \
        "${active_directory_dir}/fixture/deploy/apk/active/sentinel")" \
     != "do-not-delete" ]; then
    fail "active-is-directory: existing directory was changed"
fi
pass "active-is-directory"

release_finalize_failure_dir="${TEST_ROOT}/release-finalize-failure"
make_existing_case "${release_finalize_failure_dir}"
release_finalize_before="$(
    active_snapshot "${release_finalize_failure_dir}"
)"
release_finalize_sha="$(
    cat "${release_finalize_failure_dir}/new.sha256"
)"
configure_finalize_mv_failure \
    "${release_finalize_failure_dir}" \
    "releases"
run_install "${release_finalize_failure_dir}" \
    "file://${release_finalize_failure_dir}/source/app-release.apk" \
    "${release_finalize_sha}" \
    "file://${release_finalize_failure_dir}/source/version.json" || true
reset_fault_injection
assert_install_not_timed_out "release-finalize-move-failure"
if [ ! -f "${release_finalize_failure_dir}/mv-failed-once" ]; then
    cat "${release_finalize_failure_dir}/output.log" >&2
    fail "release-finalize-move-failure: injected mv failure did not run"
fi
if ! grep -F \
    'Could not finalize content-addressed release directory' \
    "${release_finalize_failure_dir}/output.log" >/dev/null; then
    cat "${release_finalize_failure_dir}/output.log" >&2
    fail "release-finalize-move-failure: failure was not logged"
fi
assert_failure_unchanged \
    "release-finalize-move-failure" \
    "${release_finalize_failure_dir}" \
    "${release_finalize_before}"
pass "release-finalize-move-failure-marker-and-log"

state_finalize_failure_dir="${TEST_ROOT}/state-finalize-failure"
make_existing_case "${state_finalize_failure_dir}"
state_finalize_before="$(active_snapshot "${state_finalize_failure_dir}")"
state_finalize_sha="$(cat "${state_finalize_failure_dir}/new.sha256")"
configure_finalize_mv_failure \
    "${state_finalize_failure_dir}" \
    "states"
run_install "${state_finalize_failure_dir}" \
    "file://${state_finalize_failure_dir}/source/app-release.apk" \
    "${state_finalize_sha}" \
    "file://${state_finalize_failure_dir}/source/version.json" || true
reset_fault_injection
assert_install_not_timed_out "state-finalize-move-failure"
if [ ! -f "${state_finalize_failure_dir}/mv-failed-once" ]; then
    cat "${state_finalize_failure_dir}/output.log" >&2
    fail "state-finalize-move-failure: injected mv failure did not run"
fi
if ! grep -F \
    'Could not finalize release state' \
    "${state_finalize_failure_dir}/output.log" >/dev/null; then
    cat "${state_finalize_failure_dir}/output.log" >&2
    fail "state-finalize-move-failure: failure was not logged"
fi
assert_failure_unchanged \
    "state-finalize-move-failure" \
    "${state_finalize_failure_dir}" \
    "${state_finalize_before}"
pass "state-finalize-move-failure-marker-and-log"

activation_failure_dir="${TEST_ROOT}/activation-failure"
make_existing_case "${activation_failure_dir}"
activation_before="$(active_snapshot "${activation_failure_dir}")"
activation_sha="$(cat "${activation_failure_dir}/new.sha256")"
fake_bin="${activation_failure_dir}/bin"
mkdir -p "${fake_bin}"
cat > "${fake_bin}/mv" <<'SCRIPT'
#!/bin/bash
last_argument=""
for argument in "$@"; do
    last_argument="${argument}"
done
last_argument="${last_argument%/}"
case "${last_argument}" in
    deploy/apk/active|*/deploy/apk/active)
        : > "${FAIL_MARKER}"
        exit 73
        ;;
esac
exec "${REAL_MV}" "$@"
SCRIPT
chmod +x "${fake_bin}/mv"
TEST_COMMAND_PATH="${fake_bin}:${ORIGINAL_PATH}"
run_install "${activation_failure_dir}" \
    "file://${activation_failure_dir}/source/app-release.apk" \
    "${activation_sha}" \
    "file://${activation_failure_dir}/source/version.json" || true
TEST_COMMAND_PATH="${ORIGINAL_PATH}"
assert_install_not_timed_out "active-link-move-failure"
if [ ! -f "${activation_failure_dir}/mv-failed-once" ]; then
    cat "${activation_failure_dir}/output.log" >&2
    fail "active-link-move-failure: injected mv failure did not run"
fi
if ! grep -F \
    'Could not atomically activate the verified APK bundle' \
    "${activation_failure_dir}/output.log"; then
    cat "${activation_failure_dir}/output.log" >&2
    fail "active-link-move-failure: rollback/activation failure was not logged"
fi
assert_failure_unchanged \
    "active-link-move-failure" \
    "${activation_failure_dir}" \
    "${activation_before}"
pass "active-link-move-failure-marker-and-log"

release_sync_dir="${TEST_ROOT}/release-sync-failure"
make_existing_case "${release_sync_dir}"
release_sync_before="$(active_snapshot "${release_sync_dir}")"
release_sync_sha="$(cat "${release_sync_dir}/new.sha256")"
configure_sync_failures "${release_sync_dir}" "1"
run_install \
    "${release_sync_dir}" \
    "file://${release_sync_dir}/source/app-release.apk" \
    "${release_sync_sha}" \
    "file://${release_sync_dir}/source/version.json" || true
reset_fault_injection
assert_failure_unchanged \
    "release-sync-failure" \
    "${release_sync_dir}" \
    "${release_sync_before}"
if ! grep -F \
    'Could not durably synchronize the finalized release' \
    "${release_sync_dir}/output.log" >/dev/null; then
    fail "release-sync-failure: durability failure was not logged"
fi

state_sync_dir="${TEST_ROOT}/state-sync-failure"
make_existing_case "${state_sync_dir}"
state_sync_before="$(active_snapshot "${state_sync_dir}")"
state_sync_sha="$(cat "${state_sync_dir}/new.sha256")"
configure_sync_failures "${state_sync_dir}" "2"
run_install \
    "${state_sync_dir}" \
    "file://${state_sync_dir}/source/app-release.apk" \
    "${state_sync_sha}" \
    "file://${state_sync_dir}/source/version.json" || true
reset_fault_injection
assert_failure_unchanged \
    "state-sync-failure" \
    "${state_sync_dir}" \
    "${state_sync_before}"
if ! grep -F \
    'Could not durably synchronize the finalized release state' \
    "${state_sync_dir}/output.log" >/dev/null; then
    fail "state-sync-failure: durability failure was not logged"
fi

active_sync_dir="${TEST_ROOT}/active-sync-failure"
make_existing_case "${active_sync_dir}"
active_sync_before="$(active_snapshot "${active_sync_dir}")"
active_sync_sha="$(cat "${active_sync_dir}/new.sha256")"
configure_sync_failures "${active_sync_dir}" "3"
run_install \
    "${active_sync_dir}" \
    "file://${active_sync_dir}/source/app-release.apk" \
    "${active_sync_sha}" \
    "file://${active_sync_dir}/source/version.json" || true
reset_fault_injection
assert_failure_unchanged \
    "active-sync-failure-restores-previous" \
    "${active_sync_dir}" \
    "${active_sync_before}"
if ! grep -F \
    'Previous active release was restored' \
    "${active_sync_dir}/output.log" >/dev/null; then
    fail "active-sync-failure: successful restoration was not logged"
fi
if [ "$(tail -n 1 "${active_sync_dir}/sync.log")" != "4" ]; then
    fail "active-sync-failure: restore durability sync did not run"
fi

restore_failure_dir="${TEST_ROOT}/postverify-restore-failure"
make_existing_case "${restore_failure_dir}"
restore_failure_sha="$(cat "${restore_failure_dir}/new.sha256")"
restore_failure_old_sha="$(cat "${restore_failure_dir}/current.sha256")"
configure_sync_failures "${restore_failure_dir}" "3"
configure_restore_mv_failure "${restore_failure_dir}"
run_install \
    "${restore_failure_dir}" \
    "file://${restore_failure_dir}/source/app-release.apk" \
    "${restore_failure_sha}" \
    "file://${restore_failure_dir}/source/version.json" || true
reset_fault_injection
if [ "${INSTALL_EXIT}" -eq 0 ]; then
    fail "postverify-restore-failure: install unexpectedly succeeded"
fi
if [ ! -f "${restore_failure_dir}/mv-failed-once" ]; then
    fail "postverify-restore-failure: restore mv fault did not run"
fi
assert_active_layout \
    "postverify-restore-failure" \
    "${restore_failure_dir}" \
    "${restore_failure_sha}" \
    "${restore_failure_old_sha}"
if ! grep -F \
    'Automatic rollback failed; write-protected release and state directories were retained for recovery' \
    "${restore_failure_dir}/output.log" >/dev/null; then
    fail "postverify-restore-failure: manual recovery state was not logged"
fi
pass "postverify-restore-failure-retains-new-active-for-recovery"

signal_after_rename_dir="${TEST_ROOT}/signal-after-active-rename"
make_existing_case "${signal_after_rename_dir}"
signal_after_rename_sha="$(cat "${signal_after_rename_dir}/new.sha256")"
signal_after_rename_old_sha="$(
    cat "${signal_after_rename_dir}/current.sha256"
)"
configure_sync_failures "${signal_after_rename_dir}" ""
configure_signal_after_active_mv "${signal_after_rename_dir}"
run_install \
    "${signal_after_rename_dir}" \
    "file://${signal_after_rename_dir}/source/app-release.apk" \
    "${signal_after_rename_sha}" \
    "file://${signal_after_rename_dir}/source/version.json" || true
if [ "${INSTALL_EXIT}" -ne 143 ]; then
    fail "signal-after-active-rename: expected exit 143, got ${INSTALL_EXIT}"
fi
if [ ! -f "${signal_after_rename_dir}/mv-failed-once" ]; then
    fail "signal-after-active-rename: signal injection did not run"
fi
if [ "$(cat "${signal_after_rename_dir}/sync-counter")" != "2" ]; then
    fail "signal-after-active-rename: signal did not occur immediately after the active rename"
fi
if ! grep -F \
    'WARNING: received TERM during an active-pointer change; inspect deploy/apk/active and rerun the intended command' \
    "${signal_after_rename_dir}/output.log" >/dev/null; then
    fail "signal-after-active-rename: inspect/rerun warning was not logged"
fi
if grep -F \
    'Activated verified APK bundle' \
    "${signal_after_rename_dir}/output.log" >/dev/null; then
    fail "signal-after-active-rename: interrupted activation printed success"
fi
assert_active_layout \
    "signal-after-active-rename" \
    "${signal_after_rename_dir}" \
    "${signal_after_rename_sha}" \
    "${signal_after_rename_old_sha}"
assert_published_bytes \
    "signal-after-active-rename" \
    "${signal_after_rename_dir}" \
    "${signal_after_rename_sha}"
signal_rerun_before="$(
    publication_tree_snapshot "${signal_after_rename_dir}"
)"
SYNC_FAIL_CALLS="3"
run_install \
    "${signal_after_rename_dir}" \
    "file://${signal_after_rename_dir}/source/app-release.apk" \
    "${signal_after_rename_sha}" \
    "file://${signal_after_rename_dir}/source/version.json" || true
if [ "${INSTALL_EXIT}" -eq 0 ]; then
    fail "signal-after-active-rename: durability-failing rerun unexpectedly succeeded"
fi
if [ "${INSTALL_EXIT}" -eq 124 ]; then
    fail "signal-after-active-rename: durability-failing rerun timed out"
fi
if [ "$(cat "${signal_after_rename_dir}/sync-counter")" != "3" ]; then
    fail "signal-after-active-rename: rerun did not attempt durability sync"
fi
if ! grep -F \
    'Could not durably synchronize the already-active APK release' \
    "${signal_after_rename_dir}/output.log" >/dev/null; then
    fail "signal-after-active-rename: rerun durability failure was not logged"
fi
if grep -E \
    '^(Candidate bundle is already active; no state switch was needed|Durability of the active release pointer was confirmed|Activated verified APK bundle)([[:space:]]|$)' \
    "${signal_after_rename_dir}/output.log" >/dev/null; then
    fail "signal-after-active-rename: failed rerun printed a success message"
fi
signal_failed_rerun_after="$(
    publication_tree_snapshot "${signal_after_rename_dir}"
)"
if [ "${signal_failed_rerun_after}" != "${signal_rerun_before}" ]; then
    fail "signal-after-active-rename: failed rerun changed managed publication state"
fi

SYNC_FAIL_CALLS=""
if ! run_install \
    "${signal_after_rename_dir}" \
    "file://${signal_after_rename_dir}/source/app-release.apk" \
    "${signal_after_rename_sha}" \
    "file://${signal_after_rename_dir}/source/version.json"; then
    cat "${signal_after_rename_dir}/output.log" >&2
    fail "signal-after-active-rename: successful durability rerun failed"
fi
signal_rerun_after="$(
    publication_tree_snapshot "${signal_after_rename_dir}"
)"
if [ "${signal_rerun_after}" != "${signal_rerun_before}" ]; then
    fail "signal-after-active-rename: rerun changed managed publication state"
fi
if [ "$(cat "${signal_after_rename_dir}/sync-counter")" != "4" ] ||
   [ "$(tail -n 1 "${signal_after_rename_dir}/sync.log")" != "4" ]; then
    fail "signal-after-active-rename: successful rerun did not complete durability sync"
fi
if ! grep -F \
    'Candidate bundle is already active; no state switch was needed' \
    "${signal_after_rename_dir}/output.log" >/dev/null; then
    fail "signal-after-active-rename: rerun did not converge idempotently"
fi
reset_fault_injection
pass "signal-after-active-rename-rerun-converges"

import_signal_dir="${TEST_ROOT}/import-signal-after-active-rename"
prepare_case "${import_signal_dir}"
mkdir -p "${import_signal_dir}/fixture/deploy/apk"
create_legacy_flat_bundle "${import_signal_dir}"
import_signal_sha="$(cat "${import_signal_dir}/legacy.sha256")"
import_signal_apk_root="${import_signal_dir}/fixture/deploy/apk"
import_signal_flat_digest="$(
    bundle_content_digest "${import_signal_apk_root}"
)"
configure_sync_failures "${import_signal_dir}" ""
configure_signal_after_active_mv "${import_signal_dir}"
run_install \
    "${import_signal_dir}" \
    --import-legacy \
    "${import_signal_sha}" || true
if [ "${INSTALL_EXIT}" -ne 143 ]; then
    fail "import-signal-after-active-rename: expected exit 143, got ${INSTALL_EXIT}"
fi
if [ ! -f "${import_signal_dir}/mv-failed-once" ]; then
    fail "import-signal-after-active-rename: signal injection did not run"
fi
if [ "$(cat "${import_signal_dir}/sync-counter")" != "2" ]; then
    fail "import-signal-after-active-rename: signal did not occur immediately after the active rename"
fi
if ! grep -F \
    'WARNING: received TERM during an active-pointer change; inspect deploy/apk/active and rerun the intended command' \
    "${import_signal_dir}/output.log" >/dev/null; then
    fail "import-signal-after-active-rename: inspect/rerun warning was not logged"
fi
if grep -E \
    '^(Imported and activated trusted legacy APK release|Trusted legacy APK release is already managed and active|Durability of the active release pointer was confirmed)([[:space:]]|$)' \
    "${import_signal_dir}/output.log" >/dev/null; then
    fail "import-signal-after-active-rename: interrupted import printed a success message"
fi
assert_active_layout \
    "import-signal-after-active-rename" \
    "${import_signal_dir}" \
    "${import_signal_sha}"
if [ "$(
        bundle_content_digest "${import_signal_apk_root}/active/current"
    )" != "${import_signal_flat_digest}" ]; then
    fail "import-signal-after-active-rename: active bundle differs from the trusted flat source"
fi
import_signal_rerun_before="$(
    publication_tree_snapshot "${import_signal_dir}"
)"

SYNC_FAIL_CALLS="3"
run_install \
    "${import_signal_dir}" \
    --import-legacy \
    "${import_signal_sha}" || true
if [ "${INSTALL_EXIT}" -eq 0 ]; then
    fail "import-signal-after-active-rename: durability-failing rerun unexpectedly succeeded"
fi
if [ "${INSTALL_EXIT}" -eq 124 ]; then
    fail "import-signal-after-active-rename: durability-failing rerun timed out"
fi
if [ "$(cat "${import_signal_dir}/sync-counter")" != "3" ]; then
    fail "import-signal-after-active-rename: rerun did not attempt durability sync"
fi
if ! grep -F \
    'Could not durably synchronize the already-active APK release' \
    "${import_signal_dir}/output.log" >/dev/null; then
    fail "import-signal-after-active-rename: rerun durability failure was not logged"
fi
if grep -E \
    '^(Imported and activated trusted legacy APK release|Trusted legacy APK release is already managed and active|Durability of the active release pointer was confirmed)([[:space:]]|$)' \
    "${import_signal_dir}/output.log" >/dev/null; then
    fail "import-signal-after-active-rename: failed rerun printed a success message"
fi
import_signal_failed_rerun_after="$(
    publication_tree_snapshot "${import_signal_dir}"
)"
if [ "${import_signal_failed_rerun_after}" != "${import_signal_rerun_before}" ]; then
    fail "import-signal-after-active-rename: failed rerun changed managed publication state"
fi

SYNC_FAIL_CALLS=""
if ! run_install \
    "${import_signal_dir}" \
    --import-legacy \
    "${import_signal_sha}"; then
    cat "${import_signal_dir}/output.log" >&2
    fail "import-signal-after-active-rename: successful durability rerun failed"
fi
import_signal_rerun_after="$(
    publication_tree_snapshot "${import_signal_dir}"
)"
if [ "${import_signal_rerun_after}" != "${import_signal_rerun_before}" ]; then
    fail "import-signal-after-active-rename: successful rerun changed managed publication state"
fi
if [ "$(cat "${import_signal_dir}/sync-counter")" != "4" ] ||
   [ "$(tail -n 1 "${import_signal_dir}/sync.log")" != "4" ]; then
    fail "import-signal-after-active-rename: successful rerun did not complete durability sync"
fi
if ! grep -F \
    'Trusted legacy APK release is already managed and active' \
    "${import_signal_dir}/output.log" >/dev/null; then
    fail "import-signal-after-active-rename: rerun did not converge idempotently"
fi
assert_active_layout \
    "import-signal-after-active-rename-rerun" \
    "${import_signal_dir}" \
    "${import_signal_sha}"
reset_fault_injection
pass "import-signal-after-active-rename-rerun-converges"

rollback_signal_dir="${TEST_ROOT}/rollback-signal-after-active-rename"
make_existing_case "${rollback_signal_dir}"
rollback_signal_target_sha="$(
    cat "${rollback_signal_dir}/previous.sha256"
)"
rollback_signal_old_sha="$(
    cat "${rollback_signal_dir}/current.sha256"
)"
configure_sync_failures "${rollback_signal_dir}" ""
configure_signal_after_active_mv "${rollback_signal_dir}"
run_install \
    "${rollback_signal_dir}" \
    --rollback \
    "${rollback_signal_target_sha}" || true
if [ "${INSTALL_EXIT}" -ne 143 ]; then
    fail "rollback-signal-after-active-rename: expected exit 143, got ${INSTALL_EXIT}"
fi
if [ ! -f "${rollback_signal_dir}/mv-failed-once" ]; then
    fail "rollback-signal-after-active-rename: signal injection did not run"
fi
if [ "$(cat "${rollback_signal_dir}/sync-counter")" != "1" ]; then
    fail "rollback-signal-after-active-rename: signal did not occur immediately after the active rename"
fi
if ! grep -F \
    'WARNING: received TERM during an active-pointer change; inspect deploy/apk/active and rerun the intended command' \
    "${rollback_signal_dir}/output.log" >/dev/null; then
    fail "rollback-signal-after-active-rename: inspect/rerun warning was not logged"
fi
if grep -E \
    '^(Rolled back to managed APK release|Trusted rollback target is already active|Durability of the active release pointer was confirmed)([[:space:]]|$)' \
    "${rollback_signal_dir}/output.log" >/dev/null; then
    fail "rollback-signal-after-active-rename: interrupted rollback printed a success message"
fi
assert_active_layout \
    "rollback-signal-after-active-rename" \
    "${rollback_signal_dir}" \
    "${rollback_signal_target_sha}" \
    "${rollback_signal_old_sha}"
rollback_signal_rerun_before="$(
    publication_tree_snapshot "${rollback_signal_dir}"
)"

SYNC_FAIL_CALLS="2"
run_install \
    "${rollback_signal_dir}" \
    --rollback \
    "${rollback_signal_target_sha}" || true
if [ "${INSTALL_EXIT}" -eq 0 ]; then
    fail "rollback-signal-after-active-rename: durability-failing rerun unexpectedly succeeded"
fi
if [ "${INSTALL_EXIT}" -eq 124 ]; then
    fail "rollback-signal-after-active-rename: durability-failing rerun timed out"
fi
if [ "$(cat "${rollback_signal_dir}/sync-counter")" != "2" ]; then
    fail "rollback-signal-after-active-rename: rerun did not attempt durability sync"
fi
if ! grep -F \
    'Could not durably synchronize the already-active APK release' \
    "${rollback_signal_dir}/output.log" >/dev/null; then
    fail "rollback-signal-after-active-rename: rerun durability failure was not logged"
fi
if grep -E \
    '^(Rolled back to managed APK release|Trusted rollback target is already active|Durability of the active release pointer was confirmed)([[:space:]]|$)' \
    "${rollback_signal_dir}/output.log" >/dev/null; then
    fail "rollback-signal-after-active-rename: failed rerun printed a success message"
fi
rollback_signal_failed_rerun_after="$(
    publication_tree_snapshot "${rollback_signal_dir}"
)"
if [ "${rollback_signal_failed_rerun_after}" \
     != "${rollback_signal_rerun_before}" ]; then
    fail "rollback-signal-after-active-rename: failed rerun changed managed publication state"
fi
assert_active_layout \
    "rollback-signal-after-active-rename-failed-rerun" \
    "${rollback_signal_dir}" \
    "${rollback_signal_target_sha}" \
    "${rollback_signal_old_sha}"

SYNC_FAIL_CALLS=""
if ! run_install \
    "${rollback_signal_dir}" \
    --rollback \
    "${rollback_signal_target_sha}"; then
    cat "${rollback_signal_dir}/output.log" >&2
    fail "rollback-signal-after-active-rename: successful durability rerun failed"
fi
rollback_signal_rerun_after="$(
    publication_tree_snapshot "${rollback_signal_dir}"
)"
if [ "${rollback_signal_rerun_after}" \
     != "${rollback_signal_rerun_before}" ]; then
    fail "rollback-signal-after-active-rename: successful rerun changed managed publication state"
fi
if [ "$(cat "${rollback_signal_dir}/sync-counter")" != "3" ] ||
   [ "$(tail -n 1 "${rollback_signal_dir}/sync.log")" != "3" ]; then
    fail "rollback-signal-after-active-rename: successful rerun did not complete durability sync"
fi
if ! grep -F \
    'Trusted rollback target is already active' \
    "${rollback_signal_dir}/output.log" >/dev/null; then
    fail "rollback-signal-after-active-rename: rerun did not converge idempotently"
fi
assert_active_layout \
    "rollback-signal-after-active-rename-successful-rerun" \
    "${rollback_signal_dir}" \
    "${rollback_signal_target_sha}" \
    "${rollback_signal_old_sha}"
reset_fault_injection
pass "rollback-signal-after-active-rename-rerun-converges"

verify_only_dir="${TEST_ROOT}/verify-only"
make_existing_case "${verify_only_dir}"
verify_only_before="$(
    publication_tree_snapshot "${verify_only_dir}"
)"
verify_only_sha="$(cat "${verify_only_dir}/new.sha256")"
if ! run_install "${verify_only_dir}" \
    --verify-only \
    "file://${verify_only_dir}/source/app-release.apk" \
    "${verify_only_sha}" \
    "file://${verify_only_dir}/source/version.json"; then
    cat "${verify_only_dir}/output.log" >&2
    fail "verify-only: valid bundle verification failed"
fi
verify_only_after="$(
    publication_tree_snapshot "${verify_only_dir}"
)"
if [ "${verify_only_after}" != "${verify_only_before}" ]; then
    fail "verify-only: releases, states, or active changed"
fi
pass "verify-only-does-not-change-publication-state"

success_dir="${TEST_ROOT}/successful-update"
make_existing_case "${success_dir}"
success_sha="$(cat "${success_dir}/new.sha256")"
old_current_sha="$(cat "${success_dir}/current.sha256")"
old_previous_sha="$(cat "${success_dir}/previous.sha256")"
old_current_digest="$(
    bundle_content_digest \
        "${success_dir}/fixture/deploy/apk/active/current"
)"
old_previous_digest="$(
    bundle_content_digest \
        "${success_dir}/fixture/deploy/apk/active/previous"
)"
if ! run_install "${success_dir}" \
    "file://${success_dir}/source/app-release.apk" \
    "${success_sha}" \
    "file://${success_dir}/source/version.json"; then
    cat "${success_dir}/output.log" >&2
    fail "successful-update: install failed"
fi
assert_active_layout \
    "successful-update" \
    "${success_dir}" \
    "${success_sha}" \
    "${old_current_sha}"
assert_published_bytes \
    "successful-update" "${success_dir}" "${success_sha}"
new_previous_digest="$(
    bundle_content_digest \
        "${success_dir}/fixture/deploy/apk/active/previous"
)"
if [ "${new_previous_digest}" != "${old_current_digest}" ]; then
    fail "successful-update: previous does not preserve the old current bundle"
fi
preserved_old_previous_digest="$(
    bundle_content_digest \
        "${success_dir}/fixture/deploy/apk/releases/${old_previous_sha}"
)"
if [ "${preserved_old_previous_digest}" != "${old_previous_digest}" ]; then
    fail "successful-update: older immutable release was changed"
fi

success_apk_root="${success_dir}/fixture/deploy/apk"
success_state_target="$(readlink "${success_apk_root}/active")"
assert_mode "${success_apk_root}" 755
assert_mode "${success_apk_root}/.install.lock" 600
assert_mode "${success_apk_root}/releases" 755
assert_mode "${success_apk_root}/releases/${success_sha}" 555
assert_mode \
    "${success_apk_root}/releases/${success_sha}/app-release.apk" 444
assert_mode \
    "${success_apk_root}/releases/${success_sha}/app-release.apk.sha256" 444
assert_mode \
    "${success_apk_root}/releases/${success_sha}/version.json" 444
assert_mode "${success_apk_root}/states" 755
assert_mode "${success_apk_root}/${success_state_target}" 555
pass "successful-update-explicit-permissions-and-byte-integrity"

first_install_dir="${TEST_ROOT}/first-install"
prepare_case "${first_install_dir}"
first_install_sha="$(cat "${first_install_dir}/new.sha256")"
if ! run_install "${first_install_dir}" \
    "file://${first_install_dir}/source/app-release.apk" \
    "${first_install_sha}" \
    "file://${first_install_dir}/source/version.json"; then
    cat "${first_install_dir}/output.log" >&2
    fail "first-install: install failed"
fi
assert_active_layout \
    "first-install" "${first_install_dir}" "${first_install_sha}"
assert_published_bytes \
    "first-install" "${first_install_dir}" "${first_install_sha}"
pass "first-install-has-current-without-previous"

metadata_bom_dir="${TEST_ROOT}/metadata-utf8-bom"
make_existing_case "${metadata_bom_dir}"
python3 - "${metadata_bom_dir}/source/version.json" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.write_bytes(b"\xef\xbb\xbf" + path.read_bytes())
PY
metadata_bom_sha="$(cat "${metadata_bom_dir}/new.sha256")"
if ! run_install \
    "${metadata_bom_dir}" \
    "file://${metadata_bom_dir}/source/app-release.apk" \
    "${metadata_bom_sha}" \
    "file://${metadata_bom_dir}/source/version.json"; then
    cat "${metadata_bom_dir}/output.log" >&2
    fail "metadata-utf8-bom: valid BOM metadata was rejected"
fi
assert_active_layout \
    "metadata-utf8-bom" \
    "${metadata_bom_dir}" \
    "${metadata_bom_sha}" \
    "$(cat "${metadata_bom_dir}/current.sha256")"
assert_published_bytes \
    "metadata-utf8-bom" "${metadata_bom_dir}" "${metadata_bom_sha}"
pass "metadata-utf8-bom-accepted"

rollback_arguments_dir="${TEST_ROOT}/rollback-arguments"
make_existing_case "${rollback_arguments_dir}"
rollback_arguments_before="$(
    active_snapshot "${rollback_arguments_dir}"
)"
run_install "${rollback_arguments_dir}" --rollback || true
if [ "${INSTALL_EXIT}" -ne 2 ]; then
    fail "rollback-missing-sha: expected exit 2, got ${INSTALL_EXIT}"
fi
assert_failure_unchanged \
    "rollback-missing-sha" \
    "${rollback_arguments_dir}" \
    "${rollback_arguments_before}"

wrong_rollback_sha="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
run_install \
    "${rollback_arguments_dir}" \
    --rollback \
    "${wrong_rollback_sha}" || true
assert_failure_unchanged \
    "rollback-wrong-trusted-sha" \
    "${rollback_arguments_dir}" \
    "${rollback_arguments_before}"
if ! grep -F \
    'Managed previous APK does not match the trusted rollback checksum' \
    "${rollback_arguments_dir}/output.log" >/dev/null; then
    fail "rollback-wrong-trusted-sha: trust-anchor rejection was not logged"
fi

managed_rollback_dir="${TEST_ROOT}/managed-rollback"
make_existing_case "${managed_rollback_dir}"
managed_current_sha="$(cat "${managed_rollback_dir}/current.sha256")"
managed_previous_sha="$(cat "${managed_rollback_dir}/previous.sha256")"
managed_current_digest="$(
    bundle_content_digest \
        "${managed_rollback_dir}/fixture/deploy/apk/active/current"
)"
managed_previous_digest="$(
    bundle_content_digest \
        "${managed_rollback_dir}/fixture/deploy/apk/active/previous"
)"
if ! run_install \
    "${managed_rollback_dir}" \
    --rollback \
    "${managed_previous_sha}"; then
    cat "${managed_rollback_dir}/output.log" >&2
    fail "managed-rollback: rollback failed"
fi
assert_active_layout \
    "managed-rollback" \
    "${managed_rollback_dir}" \
    "${managed_previous_sha}" \
    "${managed_current_sha}"
if [ "$(
        bundle_content_digest \
            "${managed_rollback_dir}/fixture/deploy/apk/active/current"
    )" != "${managed_previous_digest}" ]; then
    fail "managed-rollback: previous bundle did not become current"
fi
if [ "$(
        bundle_content_digest \
            "${managed_rollback_dir}/fixture/deploy/apk/active/previous"
    )" != "${managed_current_digest}" ]; then
    fail "managed-rollback: old current bundle did not become previous"
fi
managed_rollback_state="$(
    readlink "${managed_rollback_dir}/fixture/deploy/apk/active"
)"
assert_mode \
    "${managed_rollback_dir}/fixture/deploy/apk/${managed_rollback_state}" \
    555
if ! grep -F \
    "Rolled back to managed APK release ${managed_previous_sha}" \
    "${managed_rollback_dir}/output.log" >/dev/null; then
    fail "managed-rollback: success was not logged"
fi
pass "managed-rollback-swaps-current-and-previous"

rollback_state_sync_dir="${TEST_ROOT}/rollback-state-sync-failure"
make_existing_case "${rollback_state_sync_dir}"
rollback_state_sync_before="$(
    active_snapshot "${rollback_state_sync_dir}"
)"
rollback_state_sync_sha="$(
    cat "${rollback_state_sync_dir}/previous.sha256"
)"
configure_sync_failures "${rollback_state_sync_dir}" "1"
run_install \
    "${rollback_state_sync_dir}" \
    --rollback \
    "${rollback_state_sync_sha}" || true
reset_fault_injection
assert_failure_unchanged \
    "rollback-state-sync-failure" \
    "${rollback_state_sync_dir}" \
    "${rollback_state_sync_before}"
if ! grep -F \
    'Could not durably synchronize the rollback state' \
    "${rollback_state_sync_dir}/output.log" >/dev/null; then
    fail "rollback-state-sync-failure: durability failure was not logged"
fi

rollback_active_sync_dir="${TEST_ROOT}/rollback-active-sync-failure"
make_existing_case "${rollback_active_sync_dir}"
rollback_active_sync_before="$(
    active_snapshot "${rollback_active_sync_dir}"
)"
rollback_active_sync_sha="$(
    cat "${rollback_active_sync_dir}/previous.sha256"
)"
configure_sync_failures "${rollback_active_sync_dir}" "2"
run_install \
    "${rollback_active_sync_dir}" \
    --rollback \
    "${rollback_active_sync_sha}" || true
reset_fault_injection
assert_failure_unchanged \
    "rollback-active-sync-failure-restores-original" \
    "${rollback_active_sync_dir}" \
    "${rollback_active_sync_before}"
if ! grep -F \
    'Original active APK pointer was restored' \
    "${rollback_active_sync_dir}/output.log" >/dev/null; then
    fail "rollback-active-sync-failure: restoration was not logged"
fi
if [ "$(tail -n 1 "${rollback_active_sync_dir}/sync.log")" != "3" ]; then
    fail "rollback-active-sync-failure: restore durability sync did not run"
fi

damaged_current_dir="${TEST_ROOT}/rollback-damaged-current"
make_existing_case "${damaged_current_dir}"
damaged_current_sha="$(cat "${damaged_current_dir}/current.sha256")"
damaged_current_previous_sha="$(
    cat "${damaged_current_dir}/previous.sha256"
)"
damage_release_apk \
    "${damaged_current_dir}/fixture/deploy/apk/releases/${damaged_current_sha}"
if ! run_install \
    "${damaged_current_dir}" \
    --rollback \
    "${damaged_current_previous_sha}"; then
    cat "${damaged_current_dir}/output.log" >&2
    fail "rollback-damaged-current: rollback failed"
fi
assert_active_layout \
    "rollback-damaged-current" \
    "${damaged_current_dir}" \
    "${damaged_current_previous_sha}"
if [ -e "${damaged_current_dir}/fixture/deploy/apk/active/previous" ] ||
   [ -L "${damaged_current_dir}/fixture/deploy/apk/active/previous" ]; then
    fail "rollback-damaged-current: damaged current was preserved as previous"
fi
if ! grep -F \
    'current APK bundle is damaged; it will not become the next previous release' \
    "${damaged_current_dir}/output.log" >/dev/null; then
    fail "rollback-damaged-current: damage warning was not logged"
fi
pass "rollback-skips-damaged-current"

unrelated_previous_dir="${TEST_ROOT}/forward-with-damaged-old-previous"
make_existing_case "${unrelated_previous_dir}"
unrelated_current_sha="$(cat "${unrelated_previous_dir}/current.sha256")"
unrelated_previous_sha="$(cat "${unrelated_previous_dir}/previous.sha256")"
damage_release_apk \
    "${unrelated_previous_dir}/fixture/deploy/apk/releases/${unrelated_previous_sha}"
unrelated_candidate_sha="$(cat "${unrelated_previous_dir}/new.sha256")"
if ! run_install \
    "${unrelated_previous_dir}" \
    "file://${unrelated_previous_dir}/source/app-release.apk" \
    "${unrelated_candidate_sha}" \
    "file://${unrelated_previous_dir}/source/version.json"; then
    cat "${unrelated_previous_dir}/output.log" >&2
    fail "forward-with-damaged-old-previous: install failed"
fi
assert_active_layout \
    "forward-with-damaged-old-previous" \
    "${unrelated_previous_dir}" \
    "${unrelated_candidate_sha}" \
    "${unrelated_current_sha}"
pass "damaged-unrelated-previous-does-not-block-forward-install"

import_sync_names=(release state active)
import_sync_calls=(1 2 3)
import_sync_messages=(
    "Could not durably synchronize the managed legacy release"
    "Could not durably synchronize the managed legacy state"
    "Failed imported active pointer was removed"
)
for import_sync_index in 0 1 2; do
    import_sync_name="${import_sync_names[${import_sync_index}]}"
    import_sync_dir="${TEST_ROOT}/legacy-import-${import_sync_name}-sync-failure"
    prepare_case "${import_sync_dir}"
    mkdir -p "${import_sync_dir}/fixture/deploy/apk"
    create_legacy_flat_bundle "${import_sync_dir}"
    import_sync_sha="$(cat "${import_sync_dir}/legacy.sha256")"
    import_sync_flat_before="$(
        bundle_content_digest "${import_sync_dir}/fixture/deploy/apk"
    )"
    configure_sync_failures \
        "${import_sync_dir}" \
        "${import_sync_calls[${import_sync_index}]}"
    run_install \
        "${import_sync_dir}" \
        --import-legacy \
        "${import_sync_sha}" || true
    reset_fault_injection
    if [ "${INSTALL_EXIT}" -eq 0 ]; then
        fail "legacy-import-${import_sync_name}-sync-failure unexpectedly succeeded"
    fi
    if [ -e "${import_sync_dir}/fixture/deploy/apk/active" ] ||
       [ -L "${import_sync_dir}/fixture/deploy/apk/active" ]; then
        fail "legacy-import-${import_sync_name}-sync-failure left active behind"
    fi
    if [ "$(
            bundle_content_digest "${import_sync_dir}/fixture/deploy/apk"
        )" != "${import_sync_flat_before}" ]; then
        fail "legacy-import-${import_sync_name}-sync-failure changed flat source"
    fi
    if ! grep -F \
        "${import_sync_messages[${import_sync_index}]}" \
        "${import_sync_dir}/output.log" >/dev/null; then
        fail "legacy-import-${import_sync_name}-sync-failure was not logged"
    fi
    if [ "${import_sync_name}" = "active" ] &&
       [ "$(tail -n 1 "${import_sync_dir}/sync.log")" != "4" ]; then
        fail "legacy-import-active-sync-failure did not sync pointer removal"
    fi
    pass "legacy-import-${import_sync_name}-sync-failure"
done

legacy_import_dir="${TEST_ROOT}/legacy-flat-import"
prepare_case "${legacy_import_dir}"
mkdir -p "${legacy_import_dir}/fixture/deploy/apk"
create_legacy_flat_bundle "${legacy_import_dir}"
legacy_sha="$(cat "${legacy_import_dir}/legacy.sha256")"
legacy_apk_root="${legacy_import_dir}/fixture/deploy/apk"
legacy_before_digest="$(bundle_content_digest "${legacy_apk_root}")"

run_install "${legacy_import_dir}" --import-legacy || true
if [ "${INSTALL_EXIT}" -ne 2 ]; then
    fail "legacy-import-missing-sha: expected exit 2, got ${INSTALL_EXIT}"
fi
if [ -e "${legacy_apk_root}/active" ] ||
   [ -L "${legacy_apk_root}/active" ]; then
    fail "legacy-import-missing-sha: active was created"
fi
pass "legacy-import-missing-sha"

run_install \
    "${legacy_import_dir}" \
    --import-legacy \
    "${wrong_rollback_sha}" || true
if [ "${INSTALL_EXIT}" -eq 0 ]; then
    fail "legacy-import-wrong-sha: import unexpectedly succeeded"
fi
if [ -e "${legacy_apk_root}/active" ] ||
   [ -L "${legacy_apk_root}/active" ]; then
    fail "legacy-import-wrong-sha: active was created"
fi
if [ "$(bundle_content_digest "${legacy_apk_root}")" \
     != "${legacy_before_digest}" ]; then
    fail "legacy-import-wrong-sha: flat bundle changed"
fi
pass "legacy-import-wrong-trusted-sha"

if ! run_install \
    "${legacy_import_dir}" \
    --import-legacy \
    "${legacy_sha}"; then
    cat "${legacy_import_dir}/output.log" >&2
    fail "legacy-import: import failed"
fi
assert_active_layout \
    "legacy-import" "${legacy_import_dir}" "${legacy_sha}"
if ! cmp -s \
    "${legacy_apk_root}/app-release.apk" \
    "${legacy_apk_root}/active/current/app-release.apk" ||
   ! cmp -s \
    "${legacy_apk_root}/app-release.apk.sha256" \
    "${legacy_apk_root}/active/current/app-release.apk.sha256" ||
   ! cmp -s \
    "${legacy_apk_root}/version.json" \
    "${legacy_apk_root}/active/current/version.json"
then
    fail "legacy-import: managed three-file bundle differs from flat source"
fi
if [ "$(bundle_content_digest "${legacy_apk_root}")" \
     != "${legacy_before_digest}" ]; then
    fail "legacy-import: source flat bundle changed"
fi
assert_mode "${legacy_apk_root}/releases/${legacy_sha}" 555
assert_mode \
    "${legacy_apk_root}/releases/${legacy_sha}/app-release.apk" 444
assert_mode \
    "${legacy_apk_root}/releases/${legacy_sha}/app-release.apk.sha256" 444
assert_mode \
    "${legacy_apk_root}/releases/${legacy_sha}/version.json" 444
legacy_import_state="$(readlink "${legacy_apk_root}/active")"
assert_mode "${legacy_apk_root}/${legacy_import_state}" 555
pass "legacy-flat-bundle-imported-into-managed-state"

legacy_no_previous_before="$(active_snapshot "${legacy_import_dir}")"
run_install \
    "${legacy_import_dir}" \
    --rollback \
    "${legacy_sha}" || true
assert_failure_unchanged \
    "rollback-without-managed-previous" \
    "${legacy_import_dir}" \
    "${legacy_no_previous_before}"

legacy_forward_sha="$(cat "${legacy_import_dir}/new.sha256")"
if ! run_install \
    "${legacy_import_dir}" \
    "file://${legacy_import_dir}/source/app-release.apk" \
    "${legacy_forward_sha}" \
    "file://${legacy_import_dir}/source/version.json"; then
    cat "${legacy_import_dir}/output.log" >&2
    fail "legacy-import-forward: candidate activation failed"
fi
assert_active_layout \
    "legacy-import-forward" \
    "${legacy_import_dir}" \
    "${legacy_forward_sha}" \
    "${legacy_sha}"
pass "forward-activation-preserves-imported-legacy-as-previous"

if ! run_install \
    "${legacy_import_dir}" \
    --rollback \
    "${legacy_sha}"; then
    cat "${legacy_import_dir}/output.log" >&2
    fail "legacy-import-managed-rollback: rollback failed"
fi
assert_active_layout \
    "legacy-import-managed-rollback" \
    "${legacy_import_dir}" \
    "${legacy_sha}" \
    "${legacy_forward_sha}"
pass "import-forward-rollback-chain"

damaged_previous_dir="${TEST_ROOT}/rollback-damaged-previous"
make_existing_case "${damaged_previous_dir}"
damaged_previous_sha="$(cat "${damaged_previous_dir}/previous.sha256")"
damage_release_apk \
    "${damaged_previous_dir}/fixture/deploy/apk/releases/${damaged_previous_sha}"
damaged_previous_before="$(
    active_snapshot "${damaged_previous_dir}"
)"
run_install \
    "${damaged_previous_dir}" \
    --rollback \
    "${damaged_previous_sha}" || true
assert_failure_unchanged \
    "rollback-rejects-damaged-previous" \
    "${damaged_previous_dir}" \
    "${damaged_previous_before}"
if ! grep -F \
    'Managed previous APK bundle is not safe to activate' \
    "${damaged_previous_dir}/output.log" >/dev/null; then
    fail "rollback-rejects-damaged-previous: rejection was not logged"
fi

extra_member_dir="${TEST_ROOT}/release-extra-member"
make_existing_case "${extra_member_dir}"
extra_member_current_sha="$(cat "${extra_member_dir}/current.sha256")"
extra_member_release="${extra_member_dir}/fixture/deploy/apk/releases/${extra_member_current_sha}"
chmod 0755 "${extra_member_release}"
printf 'unexpected\n' > "${extra_member_release}/unexpected.txt"
chmod 0444 "${extra_member_release}/unexpected.txt"
chmod 0555 "${extra_member_release}"
extra_member_before="$(active_snapshot "${extra_member_dir}")"
extra_member_candidate_sha="$(cat "${extra_member_dir}/new.sha256")"
run_install \
    "${extra_member_dir}" \
    "file://${extra_member_dir}/source/app-release.apk" \
    "${extra_member_candidate_sha}" \
    "file://${extra_member_dir}/source/version.json" || true
assert_failure_unchanged \
    "release-extra-member-rejected" \
    "${extra_member_dir}" \
    "${extra_member_before}"
if [ ! -f "${extra_member_release}/unexpected.txt" ]; then
    fail "release-extra-member-rejected: installer changed the invalid release"
fi
if ! grep -F \
    'Release directory members differ from the required three-file bundle' \
    "${extra_member_dir}/output.log" >/dev/null; then
    fail "release-extra-member-rejected: rejection was not logged"
fi

hardlink_dir="${TEST_ROOT}/release-hardlink"
make_existing_case "${hardlink_dir}"
hardlink_current_sha="$(cat "${hardlink_dir}/current.sha256")"
hardlink_release="${hardlink_dir}/fixture/deploy/apk/releases/${hardlink_current_sha}"
ln \
    "${hardlink_release}/app-release.apk" \
    "${hardlink_dir}/outside-hardlink.apk"
hardlink_before="$(active_snapshot "${hardlink_dir}")"
hardlink_candidate_sha="$(cat "${hardlink_dir}/new.sha256")"
run_install \
    "${hardlink_dir}" \
    "file://${hardlink_dir}/source/app-release.apk" \
    "${hardlink_candidate_sha}" \
    "file://${hardlink_dir}/source/version.json" || true
assert_failure_unchanged \
    "release-hardlink-rejected" \
    "${hardlink_dir}" \
    "${hardlink_before}"
if [ "$(stat -c '%h' "${hardlink_release}/app-release.apk")" -ne 2 ]; then
    fail "release-hardlink-rejected: installer changed the invalid hardlink"
fi
if ! grep -F \
    'Release member must be owned and non-hardlinked' \
    "${hardlink_dir}/output.log" >/dev/null; then
    fail "release-hardlink-rejected: rejection was not logged"
fi

idempotent_dir="${TEST_ROOT}/idempotent-candidate"
make_existing_case "${idempotent_dir}"
idempotent_apk_root="${idempotent_dir}/fixture/deploy/apk"
idempotent_sha="$(cat "${idempotent_dir}/current.sha256")"
cp \
    "${idempotent_apk_root}/active/current/app-release.apk" \
    "${idempotent_dir}/source/app-release.apk"
cp \
    "${idempotent_apk_root}/active/current/version.json" \
    "${idempotent_dir}/source/version.json"
idempotent_before="$(publication_tree_snapshot "${idempotent_dir}")"
if ! run_install \
    "${idempotent_dir}" \
    "file://${idempotent_dir}/source/app-release.apk" \
    "${idempotent_sha}" \
    "file://${idempotent_dir}/source/version.json"; then
    cat "${idempotent_dir}/output.log" >&2
    fail "idempotent-candidate: install failed"
fi
idempotent_after="$(publication_tree_snapshot "${idempotent_dir}")"
if [ "${idempotent_after}" != "${idempotent_before}" ]; then
    fail "idempotent-candidate: active, releases, or states changed"
fi
if ! grep -F \
    'Candidate bundle is already active; no state switch was needed' \
    "${idempotent_dir}/output.log" >/dev/null; then
    fail "idempotent-candidate: idempotent outcome was not logged"
fi
pass "same-candidate-is-idempotent"

size_schema_dir="${TEST_ROOT}/metadata-size-schema"
make_existing_case "${size_schema_dir}"
size_schema_sha="$(cat "${size_schema_dir}/new.sha256")"
sed -i \
    's/"size": "0.0 MB"/"size": "1.0 MB"/' \
    "${size_schema_dir}/source/version.json"
size_schema_before="$(active_snapshot "${size_schema_dir}")"
run_install \
    "${size_schema_dir}" \
    "file://${size_schema_dir}/source/app-release.apk" \
    "${size_schema_sha}" \
    "file://${size_schema_dir}/source/version.json" || true
assert_failure_unchanged \
    "metadata-size-must-match-apk" \
    "${size_schema_dir}" \
    "${size_schema_before}"

fixed_schema_dir="${TEST_ROOT}/metadata-fixed-schema"
make_existing_case "${fixed_schema_dir}"
fixed_schema_sha="$(cat "${fixed_schema_dir}/new.sha256")"
python3 - "${fixed_schema_dir}/source/version.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
metadata = json.loads(path.read_text(encoding="utf-8"))
metadata["unexpected"] = "not-allowed"
path.write_text(json.dumps(metadata), encoding="utf-8")
PY
fixed_schema_before="$(active_snapshot "${fixed_schema_dir}")"
run_install \
    "${fixed_schema_dir}" \
    "file://${fixed_schema_dir}/source/app-release.apk" \
    "${fixed_schema_sha}" \
    "file://${fixed_schema_dir}/source/version.json" || true
assert_failure_unchanged \
    "metadata-unexpected-field-rejected" \
    "${fixed_schema_dir}" \
    "${fixed_schema_before}"

ignored_runtime_paths=(
    "deploy/apk/.install.lock"
    "deploy/apk/active"
    "deploy/apk/releases/aaaaaaaa/app-release.apk"
    "deploy/apk/states/test-state/current"
    "deploy/apk/.install.test123/app-release.apk"
)
for ignored_runtime_path in "${ignored_runtime_paths[@]}"; do
    if ! ignore_evidence="$(
        git -c "safe.directory=${REPO_ROOT}" \
            -C "${REPO_ROOT}" \
            check-ignore \
            --verbose \
            --no-index \
            -- "${ignored_runtime_path}"
    )"; then
        fail ".gitignore does not cover ${ignored_runtime_path}"
    fi
    case "${ignore_evidence}" in
        .gitignore:*)
            ;;
        *)
            fail \
                "${ignored_runtime_path} is not ignored by the repository .gitignore"
            ;;
    esac
done
pass "gitignore-covers-apk-runtime-state"

if ! python3 - \
    "${NGINX_CONFIG}" \
    "${NGINX_TLS_CONFIG}" \
    "${NGINX_HTTPS_ONLY_CONFIG}" <<'PY'
import pathlib
import re
import sys

configs = {
    pathlib.Path(path).name: pathlib.Path(path).read_text(encoding="utf-8")
    for path in sys.argv[1:]
}

def extract_server_blocks(config):
    blocks = []
    for match in re.finditer(r"(?m)^\s*server\s*\{", config):
        opening_brace = config.find("{", match.start())
        depth = 0
        for index in range(opening_brace, len(config)):
            if config[index] == "{":
                depth += 1
            elif config[index] == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(config[match.start() : index + 1])
                    break
        else:
            raise ValueError("unterminated server block")
    return blocks


def exact_location_body(server, public_file):
    match = re.search(
        rf"location\s*=\s*/apk/{re.escape(public_file)}\s*\{{"
        r"(?P<body>[^}]*)\}",
        server,
        flags=re.MULTILINE,
    )
    return None if match is None else match.group("body")


def generic_location_body(server):
    match = re.search(
        r"location\s+(?:\^~\s+)?/apk/\s*\{(?P<body>[^}]*)\}",
        server,
        flags=re.MULTILINE,
    )
    return None if match is None else match.group("body")


expected_apk_servers = {
    "nginx.conf": 1,
    "nginx.tls.conf": 2,
    "nginx.https-only.conf": 1,
}
public_files = (
    "app-release.apk",
    "app-release.apk.sha256",
    "version.json",
)
errors = []

for config_name, config in configs.items():
    apk_servers = []
    for server_number, server in enumerate(
        extract_server_blocks(config),
        start=1,
    ):
        has_apk_location = re.search(
            r"location\s+(?:=|\^~)?\s*/apk(?:/|\s)",
            server,
        )
        if has_apk_location:
            apk_servers.append((server_number, server))

    expected_count = expected_apk_servers[config_name]
    if len(apk_servers) != expected_count:
        errors.append(
            f"{config_name}: expected {expected_count} APK server(s), "
            f"found {len(apk_servers)}"
        )

    for server_number, server in apk_servers:
        label = f"{config_name} server {server_number}"
        for public_file in public_files:
            body = exact_location_body(server, public_file)
            if body is None:
                errors.append(
                    f"{label}: missing exact /apk/{public_file} location"
                )
                continue
            ordered_try_files = re.compile(
                rf"try_files\s+"
                rf"/apk/active/current/{re.escape(public_file)}\s+"
                r"=404\s*;"
            )
            if ordered_try_files.search(body) is None:
                errors.append(
                    f"{label}: /apk/{public_file} must serve only "
                    "active/current and then return 404"
                )

        generic_body = generic_location_body(server)
        if generic_body is None:
            errors.append(f"{label}: missing generic /apk/ location")
        else:
            if re.search(r"\breturn\s+404\s*;", generic_body) is None:
                errors.append(
                    f"{label}: generic /apk/ location must return 404"
                )
            if re.search(r"\balias\b", generic_body) is not None:
                errors.append(
                    f"{label}: generic /apk/ location must not use alias"
                )

        if re.search(
            r"location[^{;]*"
            r"/apk/(?:active|releases|states|previous)(?:/|\s)",
            server,
        ):
            errors.append(
                f"{label}: internal APK release paths are directly exposed"
            )

if errors:
    print(
        "Nginx APK publication path assertions failed:\n- "
        + "\n- ".join(errors),
        file=sys.stderr,
    )
    sys.exit(1)
PY
then
    fail "nginx-managed-active-only"
fi
pass "nginx-managed-active-only"

if ! python3 - "${NGINX_TLS_CONFIG}" <<'PY'
import pathlib
import re
import sys

config_path = pathlib.Path(sys.argv[1])
config = config_path.read_text(encoding="utf-8")
health_locations = re.findall(
    r"location\s+/actuator/health\s*\{(?P<body>[^}]*)\}",
    config,
    flags=re.MULTILINE,
)

errors = []
if len(health_locations) != 2:
    errors.append(
        f"expected two /actuator/health locations, found {len(health_locations)}"
    )
for index, body in enumerate(health_locations, start=1):
    if re.search(r"proxy_pass\s+http://fitloop_backend\s*;", body) is None:
        errors.append(f"health location {index} must proxy to fitloop_backend")
    if re.search(r"proxy_set_header\s+Host\s+\$host\s*;", body) is None:
        errors.append(
            f"health location {index} must pass a valid client Host header"
        )

if errors:
    print(
        "Nginx TLS health proxy assertions failed:\n- " + "\n- ".join(errors),
        file=sys.stderr,
    )
    sys.exit(1)
PY
then
    fail "nginx-tls-health-host-header"
fi
pass "nginx-tls-health-host-header"

if grep -Fq 'http://43.139.72.25' "${DOWNLOAD_PAGE}" \
    || ! grep -Fq '当前 API 地址：https://43.139.72.25' "${DOWNLOAD_PAGE}" \
    || ! grep -Fq 'apiBaseUrl: "https://43.139.72.25"' "${DOWNLOAD_PAGE}"
then
    fail "download-page-defaults-to-https"
fi
pass "download-page-defaults-to-https"

if ! grep -Fq '$canonicalChecksum = "$sha256  app-release.apk`n"' "${BUILD_APK_SCRIPT}" \
    || ! grep -Fq '[System.IO.File]::WriteAllText(' "${BUILD_APK_SCRIPT}" \
    || ! grep -Fq '[System.IO.File]::ReadAllText(' "${BUILD_APK_SCRIPT}" \
    || grep -Fq 'Set-Content -Encoding ASCII $checksumTarget' "${BUILD_APK_SCRIPT}"; then
    fail "build-apk-canonical-checksum"
fi
pass "build-apk-canonical-checksum"

run_build_policy_case() {
    local script_path="$1"
    shift

    set +e
    BUILD_POLICY_OUTPUT="$(
        ANDROID_SDK_ROOT= \
        ANDROID_HOME= \
        pwsh -NoLogo -NoProfile -File "${script_path}" "$@" 2>&1
    )"
    BUILD_POLICY_EXIT=$?
    set -e
}

normalize_build_policy_output() {
    printf '%s' "${BUILD_POLICY_OUTPUT}" |
        sed $'s/\033\\[[0-9;]*m//g' |
        tr '\r\n\t' '   ' |
        sed \
            -e 's/[[:space:]][[:space:]]*/ /g' \
            -e 's/[[:space:]]*|[[:space:]]*/ /g'
}

assert_build_policy_rejection() {
    local case_name="$1"
    local expected_message="$2"
    local normalized_output

    if [ "${BUILD_POLICY_EXIT}" -eq 0 ]; then
        printf '%s\n' "${BUILD_POLICY_OUTPUT}" >&2
        fail "${case_name}: build policy unexpectedly succeeded"
    fi
    normalized_output="$(normalize_build_policy_output)"
    if ! grep -Fq "${expected_message}" <<<"${normalized_output}"; then
        printf '%s\n' "${BUILD_POLICY_OUTPUT}" >&2
        fail "${case_name}: expected policy message was not emitted"
    fi
    pass "${case_name}"
}

if command -v pwsh >/dev/null 2>&1; then
    run_build_policy_case \
        "${BUILD_APK_SCRIPT}" \
        -ApiBaseUrl "http://43.139.72.25" \
        -SigningMode Compatibility
    assert_build_policy_rejection \
        "build-http-transition-requires-explicit-switch" \
        "Release APK API base URL must use HTTPS."

    run_build_policy_case \
        "${BUILD_APK_SCRIPT}" \
        -ApiBaseUrl "http://43.139.72.25/" \
        -SigningMode Compatibility \
        -AllowInsecureHttpTransitionRelease
    assert_build_policy_rejection \
        "build-http-transition-rejects-url-variant" \
        "The HTTP transition release only accepts API base URL http://43.139.72.25."

    run_build_policy_case \
        "${BUILD_APK_SCRIPT}" \
        -ApiBaseUrl "http://43.139.72.25" \
        -SigningMode Compatibility \
        -AllowInsecureApiForDevelopment \
        -AllowInsecureHttpTransitionRelease
    assert_build_policy_rejection \
        "build-http-transition-rejects-ambiguous-switches" \
        "cannot be combined."

    run_build_policy_case \
        "${BUILD_APK_SCRIPT}" \
        -ApiBaseUrl "http://43.139.72.25" \
        -SigningMode Official \
        -AllowInsecureHttpTransitionRelease
    assert_build_policy_rejection \
        "build-http-transition-requires-compatibility-signing" \
        "The HTTP transition release requires Compatibility signing."

    run_build_policy_case \
        "${BUILD_APK_SCRIPT}" \
        -ApiBaseUrl "http://43.139.72.25" \
        -SigningMode Compatibility \
        -ExpectedSignerSha256 \
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
        -AllowInsecureHttpTransitionRelease
    assert_build_policy_rejection \
        "build-http-transition-requires-approved-signer" \
        "The HTTP transition release requires the approved compatibility signer."

    build_version_fixture="${TEST_ROOT}/build-version-fixture"
    mkdir -p \
        "${build_version_fixture}/deploy" \
        "${build_version_fixture}/mobile"
    cp "${BUILD_APK_SCRIPT}" \
        "${build_version_fixture}/deploy/build-apk.ps1"
    printf 'name: fitloop\nversion: 0.1.9+10\n' \
        > "${build_version_fixture}/mobile/pubspec.yaml"
    run_build_policy_case \
        "${build_version_fixture}/deploy/build-apk.ps1" \
        -ApiBaseUrl "http://43.139.72.25" \
        -SigningMode Compatibility \
        -AllowInsecureHttpTransitionRelease
    assert_build_policy_rejection \
        "build-http-transition-self-expires-after-approved-version" \
        "The HTTP transition release is restricted to version 0.1.9+11."

    run_build_policy_case \
        "${BUILD_APK_SCRIPT}" \
        -ApiBaseUrl "http://43.139.72.25" \
        -SigningMode Compatibility \
        -AllowInsecureHttpTransitionRelease
    if [ "${BUILD_POLICY_EXIT}" -eq 0 ]; then
        printf '%s\n' "${BUILD_POLICY_OUTPUT}" >&2
        fail "build-http-transition-exact-policy: build unexpectedly completed"
    fi
    if ! grep -Fq \
        "Android apksigner.bat was not found." \
        <<<"${BUILD_POLICY_OUTPUT}"
    then
        printf '%s\n' "${BUILD_POLICY_OUTPUT}" >&2
        fail "build-http-transition-exact-policy: policy did not reach the post-policy SDK gate"
    fi
    normalized_build_policy_output="$(normalize_build_policy_output)"
    if ! grep -Fq \
        "API traffic is not encrypted." \
        <<<"${normalized_build_policy_output}"
    then
        printf '%s\n' "${BUILD_POLICY_OUTPUT}" >&2
        fail "build-http-transition-exact-policy: warning was not emitted"
    fi
    pass "build-http-transition-exact-policy"
elif [ "${CI:-}" = "true" ]; then
    fail "build HTTP transition policy tests require pwsh in CI"
else
    printf '%s\n' \
        "[SKIP] build HTTP transition policy tests require pwsh; CI must run them." \
        >&2
fi

echo "All APK bundle installation tests passed."
