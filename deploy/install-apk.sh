#!/bin/bash
# Verify and atomically activate a trusted FitLoop APK release bundle.
# Usage:
#   bash deploy/install-apk.sh <apk-url> <sha256> <version-json-url>
#   bash deploy/install-apk.sh --allow-insecure-http-transition-release <apk-url> <sha256> <version-json-url>
#   bash deploy/install-apk.sh --verify-only <apk-url> <sha256> <version-json-url>
#   bash deploy/install-apk.sh --verify-only --allow-insecure-http-transition-release <apk-url> <sha256> <version-json-url>
#   bash deploy/install-apk.sh --import-legacy <trusted-legacy-sha256>
#   bash deploy/install-apk.sh --rollback <expected-previous-sha256>

set -euo pipefail

readonly APPROVED_VERSION="0.1.6"
readonly APPROVED_VERSION_CODE="7"
readonly APPROVED_SIGNING_MODE="Compatibility"
readonly APPROVED_SIGNER_SHA256="69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a"
readonly APPROVED_HTTP_TRANSITION_API_BASE_URL="http://43.139.72.25"
readonly MAX_APK_BYTES="536870912"
readonly MAX_METADATA_BYTES="1048576"

usage() {
    cat >&2 <<USAGE
Usage:
  $0 <apk-url> <sha256> <version-json-url>
  $0 --allow-insecure-http-transition-release <apk-url> <sha256> <version-json-url>
  $0 --verify-only <apk-url> <sha256> <version-json-url>
  $0 --verify-only --allow-insecure-http-transition-release <apk-url> <sha256> <version-json-url>
  $0 --import-legacy <trusted-legacy-sha256>
  $0 --rollback <expected-previous-sha256>
USAGE
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        fail "Required command is not installed: ${command_name}"
    fi
}

INSTALL_MODE="activate"
if [ "${1:-}" = "--verify-only" ]; then
    INSTALL_MODE="verify"
    shift
elif [ "${1:-}" = "--rollback" ]; then
    INSTALL_MODE="rollback"
    shift
elif [ "${1:-}" = "--import-legacy" ]; then
    INSTALL_MODE="import-legacy"
    shift
fi

ALLOW_INSECURE_HTTP_TRANSITION_RELEASE=false
if [ "${1:-}" = "--allow-insecure-http-transition-release" ]; then
    if [ "${INSTALL_MODE}" != "activate" ] &&
       [ "${INSTALL_MODE}" != "verify" ]
    then
        echo "--allow-insecure-http-transition-release is valid only for activate or verify-only" >&2
        exit 2
    fi
    ALLOW_INSECURE_HTTP_TRANSITION_RELEASE=true
    shift
fi

HISTORICAL_EXPECTED_SHA256=""
if [ "${INSTALL_MODE}" = "rollback" ] ||
   [ "${INSTALL_MODE}" = "import-legacy" ]
then
    if [ "$#" -ne 1 ]; then
        usage
        exit 2
    fi
    HISTORICAL_EXPECTED_SHA256="$(
        printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
    )"
    if [[ ! "${HISTORICAL_EXPECTED_SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Historical SHA-256 must contain exactly 64 hexadecimal characters" >&2
        exit 2
    fi
elif [ "$#" -ne 3 ]; then
    usage
    exit 2
fi

APK_URL=""
EXPECTED_SHA256=""
VERSION_URL=""
if [ "${INSTALL_MODE}" = "activate" ] ||
   [ "${INSTALL_MODE}" = "verify" ]
then
    APK_URL="$1"
    EXPECTED_SHA256="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
    VERSION_URL="$3"
fi

if { [ "${INSTALL_MODE}" = "activate" ] ||
     [ "${INSTALL_MODE}" = "verify" ]; } &&
   [[ ! "${EXPECTED_SHA256}" =~ ^[0-9a-f]{64}$ ]]
then
    echo "Expected SHA-256 must contain exactly 64 hexadecimal characters" >&2
    exit 2
fi

validate_download_url() {
    local label="$1"
    local url="$2"

    case "${url}" in
        https://*|file://*)
            return 0
            ;;
        *)
            echo "${label} URL must use https:// or file://" >&2
            return 1
            ;;
    esac
}

if [ "${INSTALL_MODE}" = "activate" ] ||
   [ "${INSTALL_MODE}" = "verify" ]
then
    validate_download_url "APK" "${APK_URL}" || exit 2
    validate_download_url "version.json" "${VERSION_URL}" || exit 2
fi

for required_command in \
    awk cat chmod cmp cp curl date dirname flock id ln mkdir mktemp mv python3 \
    readlink rm sha256sum stat sync tr
do
    require_command "${required_command}"
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
APK_DIR="${REPO_ROOT}/deploy/apk"
RELEASES_DIR="${APK_DIR}/releases"
STATES_DIR="${APK_DIR}/states"
ACTIVE_LINK="${APK_DIR}/active"
LOCK_FILE="${APK_DIR}/.install.lock"
TMP_DIR=""
CURRENT_PROCESS_UID="$(id -u)"
ACTIVE_SWITCH_UNCERTAIN=false

ensure_managed_directory() {
    local directory="$1"

    if [ -L "${directory}" ]; then
        echo "Managed directory must not be a symbolic link: ${directory}" >&2
        return 1
    fi
    if [ -e "${directory}" ] && [ ! -d "${directory}" ]; then
        echo "Managed path is not a directory: ${directory}" >&2
        return 1
    fi
    if [ ! -d "${directory}" ]; then
        mkdir -p -- "${directory}" || {
            echo "Could not create managed directory: ${directory}" >&2
            return 1
        }
    fi
    chmod 0755 -- "${directory}" || {
        echo "Could not set managed directory permissions: ${directory}" >&2
        return 1
    }
    if [ "$(stat -c '%u' "${directory}")" != "${CURRENT_PROCESS_UID}" ]; then
        echo "Managed directory is not owned by the installer user: ${directory}" >&2
        return 1
    fi
}

ensure_managed_directory "${APK_DIR}" || exit 1
ensure_managed_directory "${RELEASES_DIR}" || exit 1
ensure_managed_directory "${STATES_DIR}" || exit 1

if [ -e "${ACTIVE_LINK}" ] && [ ! -L "${ACTIVE_LINK}" ]; then
    fail "Managed active path exists but is not a symbolic link: ${ACTIVE_LINK}"
fi
if [ -L "${LOCK_FILE}" ]; then
    fail "Installer lock must not be a symbolic link: ${LOCK_FILE}"
fi
if [ -e "${LOCK_FILE}" ] && [ ! -f "${LOCK_FILE}" ]; then
    fail "Installer lock is not a regular file: ${LOCK_FILE}"
fi
if [ -e "${LOCK_FILE}" ]; then
    if [ "$(stat -c '%h' "${LOCK_FILE}")" != "1" ] ||
       [ "$(stat -c '%u' "${LOCK_FILE}")" != "${CURRENT_PROCESS_UID}" ]
    then
        fail "Existing installer lock must be singly linked and owned by the installer user"
    fi
fi

exec 9>>"${LOCK_FILE}"
chmod 0600 -- "${LOCK_FILE}"
LOCK_PATH_STAT="$(stat -Lc '%d:%i:%h:%u' "${LOCK_FILE}")"
LOCK_FD_STAT="$(stat -Lc '%d:%i:%h:%u' "/proc/$$/fd/9")"
if [ "${LOCK_PATH_STAT}" != "${LOCK_FD_STAT}" ]; then
    fail "Installer lock path changed while it was opened"
fi
IFS=: read -r _ _ LOCK_LINK_COUNT LOCK_OWNER_UID <<<"${LOCK_FD_STAT}"
if [ "${LOCK_LINK_COUNT}" != "1" ] ||
   [ "${LOCK_OWNER_UID}" != "${CURRENT_PROCESS_UID}" ]
then
    fail "Installer lock must be singly linked and owned by the installer user"
fi
if ! flock -n 9; then
    fail "Another APK installation is already running"
fi

TMP_DIR="$(mktemp -d "${APK_DIR}/.install.XXXXXX")"
chmod 0700 -- "${TMP_DIR}"

MANAGED_STAGING_DIRS=()
CREATED_STAGING_DIR=""

create_managed_staging() {
    local staging_kind="$1"
    local staging_template

    case "${staging_kind}" in
        release)
            staging_template="${RELEASES_DIR}/.release-staging.XXXXXX"
            ;;
        state)
            staging_template="${STATES_DIR}/.state-staging.XXXXXX"
            ;;
        *)
            echo "Unknown managed staging kind: ${staging_kind}" >&2
            return 1
            ;;
    esac

    if ! CREATED_STAGING_DIR="$(
        mktemp -d "${staging_template}"
    )"; then
        return 1
    fi
    MANAGED_STAGING_DIRS+=("${CREATED_STAGING_DIR}")
}

cleanup_managed_staging() {
    local staging_directory="$1"
    local staging_parent
    local staging_name

    staging_parent="${staging_directory%/*}"
    staging_name="${staging_directory##*/}"
    if ! {
        [ "${staging_parent}" = "${RELEASES_DIR}" ] &&
        [[ "${staging_name}" = .release-staging.?* ]]
    } && ! {
        [ "${staging_parent}" = "${STATES_DIR}" ] &&
        [[ "${staging_name}" = .state-staging.?* ]]
    }; then
        echo "Refusing to clean unexpected managed staging path: ${staging_directory}" >&2
        return 1
    fi

    if [ ! -e "${staging_directory}" ] &&
       [ ! -L "${staging_directory}" ]
    then
        return 0
    fi
    if [ -L "${staging_directory}" ] ||
       [ ! -d "${staging_directory}" ]
    then
        echo "Refusing to clean unsafe managed staging path: ${staging_directory}" >&2
        return 1
    fi
    if [ "$(stat -c '%u' "${staging_directory}")" != "${CURRENT_PROCESS_UID}" ]; then
        echo "Refusing to clean managed staging owned by another user: ${staging_directory}" >&2
        return 1
    fi
    if ! chmod u+rwx -- "${staging_directory}"; then
        echo "Could not restore managed staging permissions: ${staging_directory}" >&2
        return 1
    fi
    if ! rm -rf -- "${staging_directory}"; then
        echo "Could not remove managed staging directory: ${staging_directory}" >&2
        return 1
    fi
}

cleanup() {
    local staging_directory

    for staging_directory in "${MANAGED_STAGING_DIRS[@]}"; do
        cleanup_managed_staging "${staging_directory}" || true
    done

    if [ -n "${TMP_DIR:-}" ]; then
        case "${TMP_DIR}" in
            "${APK_DIR}"/.install.*)
                if [ -d "${TMP_DIR}" ] && [ ! -L "${TMP_DIR}" ]; then
                    if ! rm -rf -- "${TMP_DIR}"; then
                        echo "WARNING: could not remove installer temporary directory: ${TMP_DIR}" >&2
                    fi
                fi
                ;;
            *)
                echo "Refusing to clean unexpected installer path: ${TMP_DIR}" >&2
                ;;
        esac
    fi
}

trap cleanup EXIT
handle_signal() {
    local exit_code="$1"
    local signal_name="$2"

    if [ "${ACTIVE_SWITCH_UNCERTAIN}" = true ]; then
        echo "WARNING: received ${signal_name} during an active-pointer change; inspect deploy/apk/active and rerun the intended command" >&2
    fi
    exit "${exit_code}"
}
trap 'handle_signal 130 INT' INT
trap 'handle_signal 143 TERM' TERM

TMP_APK="${TMP_DIR}/app-release.apk"
TMP_METADATA="${TMP_DIR}/version.json"

if [ "${INSTALL_MODE}" = "activate" ] ||
   [ "${INSTALL_MODE}" = "verify" ]
then
if ! curl -q \
    --fail \
    --location \
    --silent \
    --show-error \
    --connect-timeout 15 \
    --max-time 600 \
    --max-filesize "${MAX_APK_BYTES}" \
    --proto '=https,file' \
    --proto-redir '=https' \
    --output "${TMP_APK}" \
    --url "${APK_URL}"
then
    fail "Could not download APK"
fi

if [ ! -f "${TMP_APK}" ] || [ -L "${TMP_APK}" ] || [ ! -s "${TMP_APK}" ]; then
    fail "Downloaded APK is missing, empty, or not a regular file"
fi
APK_BYTES="$(stat -c '%s' "${TMP_APK}")"
if [ "${APK_BYTES}" -gt "${MAX_APK_BYTES}" ]; then
    fail "Downloaded APK exceeds ${MAX_APK_BYTES} bytes"
fi

ACTUAL_SHA256="$(sha256sum "${TMP_APK}" | awk '{print $1}')"
if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then
    fail "APK checksum mismatch; active release was not changed"
fi

if ! curl -q \
    --fail \
    --location \
    --silent \
    --show-error \
    --connect-timeout 15 \
    --max-time 60 \
    --max-filesize "${MAX_METADATA_BYTES}" \
    --proto '=https,file' \
    --proto-redir '=https' \
    --output "${TMP_METADATA}" \
    --url "${VERSION_URL}"
then
    fail "Could not download version.json"
fi

if [ ! -f "${TMP_METADATA}" ] || [ -L "${TMP_METADATA}" ] || [ ! -s "${TMP_METADATA}" ]; then
    fail "Downloaded version.json is missing, empty, or not a regular file"
fi
METADATA_BYTES="$(stat -c '%s' "${TMP_METADATA}")"
if [ "${METADATA_BYTES}" -gt "${MAX_METADATA_BYTES}" ]; then
    fail "Downloaded version.json exceeds ${MAX_METADATA_BYTES} bytes"
fi
fi

validate_metadata() {
    local metadata_path="$1"
    local apk_path="$2"
    local expected_sha256="$3"
    local validation_mode="$4"

    python3 - \
        "${metadata_path}" \
        "${apk_path}" \
        "${expected_sha256}" \
        "${validation_mode}" \
        "${APPROVED_VERSION}" \
        "${APPROVED_VERSION_CODE}" \
        "${APPROVED_SIGNING_MODE}" \
        "${APPROVED_SIGNER_SHA256}" \
        "${ALLOW_INSECURE_HTTP_TRANSITION_RELEASE}" \
        "${APPROVED_HTTP_TRANSITION_API_BASE_URL}" <<'PY'
import datetime
import ipaddress
import json
import os
import re
import sys
from urllib.parse import urlsplit

(
    metadata_path,
    apk_path,
    expected_sha256,
    validation_mode,
    approved_version,
    approved_version_code,
    approved_signing_mode,
    approved_signer_sha256,
    allow_insecure_http_transition_release,
    approved_http_transition_api_base_url,
) = sys.argv[1:]


def load_object_without_duplicates(path):
    def reject_duplicates(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate field: {key}")
            result[key] = value
        return result

    with open(path, "r", encoding="utf-8-sig") as handle:
        value = json.load(handle, object_pairs_hook=reject_duplicates)
    if not isinstance(value, dict):
        raise ValueError("top-level JSON value must be an object")
    return value


def require_string(metadata, field):
    value = metadata.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} must be a non-empty string")
    if value != value.strip():
        raise ValueError(f"{field} must not have surrounding whitespace")
    return value


def validate_api_base_url(
    value,
    strict,
    allow_insecure_http_transition,
    approved_http_transition_url,
):
    if any(character.isspace() for character in value):
        raise ValueError("apiBaseUrl must not contain whitespace")
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as error:
        raise ValueError("apiBaseUrl is invalid") from error
    if allow_insecure_http_transition not in ("true", "false"):
        raise ValueError("invalid HTTP transition policy flag")
    if strict and allow_insecure_http_transition == "true":
        if value != approved_http_transition_url:
            raise ValueError(
                "apiBaseUrl must exactly match the approved HTTP transition URL"
            )
        allowed_schemes = ("http",)
    else:
        allowed_schemes = ("https",) if strict else ("http", "https")
    if (
        parsed.scheme not in allowed_schemes
        or not parsed.netloc
        or parsed.hostname is None
    ):
        required_scheme = "HTTPS" if strict else "HTTP or HTTPS"
        raise ValueError(
            f"apiBaseUrl must be an absolute {required_scheme} URL"
        )
    if parsed.username is not None or parsed.password is not None:
        raise ValueError("apiBaseUrl must not contain credentials")
    if parsed.query or parsed.fragment:
        raise ValueError("apiBaseUrl must not contain a query or fragment")
    if port is not None and not 1 <= port <= 65535:
        raise ValueError("apiBaseUrl port is invalid")

    host = parsed.hostname.rstrip(".").lower()
    if parsed.hostname.endswith("."):
        raise ValueError("apiBaseUrl hostname must not end with a dot")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        try:
            ascii_host = host.encode("idna").decode("ascii")
        except UnicodeError as error:
            raise ValueError("apiBaseUrl hostname is invalid") from error
        if len(ascii_host) > 253:
            raise ValueError("apiBaseUrl hostname is too long")
        for label in ascii_host.split("."):
            if (
                not label
                or len(label) > 63
                or label.startswith("-")
                or label.endswith("-")
                or re.fullmatch(r"[a-z0-9-]+", label) is None
            ):
                raise ValueError("apiBaseUrl hostname is invalid")
        if strict and "." not in ascii_host:
            raise ValueError("apiBaseUrl must use a fully qualified hostname")
    else:
        if strict and not address.is_global:
            raise ValueError("apiBaseUrl must not use a non-public IP address")

    if strict:
        if host == "localhost" or host.endswith((".localhost", ".local")):
            raise ValueError("apiBaseUrl must not use a local hostname")
        reserved_suffixes = (
            "invalid",
            "example",
            "test",
            "example.com",
            "example.net",
            "example.org",
        )
        if any(
            host == suffix or host.endswith("." + suffix)
            for suffix in reserved_suffixes
        ):
            raise ValueError(
                "apiBaseUrl must not use a reserved example hostname"
            )


try:
    metadata = load_object_without_duplicates(metadata_path)
    if validation_mode not in (
        "legacy-flat",
        "managed",
        "schema",
        "policy",
    ):
        raise ValueError("unknown metadata validation mode")

    base_fields = {
        "version",
        "versionCode",
        "size",
        "buildDate",
        "minSdkVersion",
        "apiBaseUrl",
    }
    attestation_fields = {"sha256", "signerSha256", "signingMode"}
    required_fields = (
        base_fields
        if validation_mode in ("legacy-flat", "managed")
        else base_fields | attestation_fields
    )
    allowed_fields = (
        base_fields | attestation_fields
        if validation_mode in ("legacy-flat", "managed")
        else required_fields
    )
    missing_fields = sorted(required_fields - set(metadata))
    unexpected_fields = sorted(set(metadata) - allowed_fields)
    if missing_fields:
        raise ValueError(
            "missing required fields: " + ", ".join(missing_fields)
        )
    if unexpected_fields:
        raise ValueError(
            "unexpected fields: " + ", ".join(unexpected_fields)
        )

    if "sha256" in metadata:
        metadata_sha256 = require_string(metadata, "sha256")
        if re.fullmatch(r"[0-9a-f]{64}", metadata_sha256) is None:
            raise ValueError(
                "sha256 must be 64 lowercase hexadecimal characters"
            )
        if metadata_sha256 != expected_sha256:
            raise ValueError(
                "metadata sha256 does not match the trusted APK checksum"
            )

    version = require_string(metadata, "version")
    if re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", version) is None:
        raise ValueError("version must be a semantic version")
    version_code = metadata["versionCode"]
    if (
        isinstance(version_code, bool)
        or not isinstance(version_code, int)
        or version_code < 1
    ):
        raise ValueError("versionCode must be a positive integer")

    signing_mode = metadata.get("signingMode")
    signer_sha256 = metadata.get("signerSha256")
    if (signing_mode is None) != (signer_sha256 is None):
        raise ValueError(
            "signingMode and signerSha256 must either both be present or both be absent"
        )
    if signing_mode is not None:
        signing_mode = require_string(metadata, "signingMode")
        signer_sha256 = require_string(metadata, "signerSha256")
        if signing_mode not in ("Compatibility", "Official"):
            raise ValueError(
                "signingMode must be Compatibility or Official"
            )
        if re.fullmatch(r"[0-9a-f]{64}", signer_sha256) is None:
            raise ValueError(
                "signerSha256 must be 64 lowercase hexadecimal characters"
            )

    min_sdk_version = require_string(metadata, "minSdkVersion")
    if len(min_sdk_version) > 128:
        raise ValueError("minSdkVersion is too long")

    build_date = require_string(metadata, "buildDate")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", build_date) is None:
        raise ValueError("buildDate must use YYYY-MM-DD")
    datetime.date.fromisoformat(build_date)

    size_value = require_string(metadata, "size")
    size_match = re.fullmatch(r"(\d+(?:\.\d)?) MB", size_value)
    if size_match is None:
        raise ValueError(
            "size must be expressed in MB with at most one decimal"
        )
    declared_size = float(size_match.group(1))
    actual_size = round(os.path.getsize(apk_path) / (1024 * 1024), 1)
    if declared_size != actual_size:
        raise ValueError(
            f"size does not match APK ({actual_size:g} MB expected)"
        )

    validate_api_base_url(
        require_string(metadata, "apiBaseUrl"),
        strict=validation_mode == "policy",
        allow_insecure_http_transition=(
            allow_insecure_http_transition_release
        ),
        approved_http_transition_url=(
            approved_http_transition_api_base_url
        ),
    )

    if validation_mode == "policy":
        if version != approved_version:
            raise ValueError(f"version must be {approved_version}")
        if version_code != int(approved_version_code):
            raise ValueError(
                f"versionCode must be {approved_version_code}"
            )
        if signing_mode != approved_signing_mode:
            raise ValueError(
                f"signingMode must be {approved_signing_mode}"
            )
        if signer_sha256 != approved_signer_sha256:
            raise ValueError(
                "signerSha256 does not match the approved compatibility signer"
            )
        if min_sdk_version != "Android 8.0 (API 26)":
            raise ValueError(
                "minSdkVersion must be Android 8.0 (API 26)"
            )
except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
    print(f"Metadata validation failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
}

if [ "${INSTALL_MODE}" = "activate" ] ||
   [ "${INSTALL_MODE}" = "verify" ]
then
    if ! validate_metadata \
        "${TMP_METADATA}" \
        "${TMP_APK}" \
        "${EXPECTED_SHA256}" \
        "policy"
    then
        fail "version.json failed release policy validation"
    fi
fi

validate_release_bundle() {
    local release_directory="$1"
    local release_sha256="$2"
    local metadata_mode="$3"
    local expected_metadata_path="${4:-}"
    local actual_sha256
    local path
    local mode

    if [ -L "${release_directory}" ] || [ ! -d "${release_directory}" ]; then
        echo "Release directory is missing or is a symbolic link: ${release_directory}" >&2
        return 1
    fi
    mode="$(stat -c '%a' "${release_directory}")" || return 1
    if [ "${mode}" != "555" ]; then
        echo "Release directory must have mode 555: ${release_directory}" >&2
        return 1
    fi
    if [ "$(stat -c '%u' "${release_directory}")" != "${CURRENT_PROCESS_UID}" ]; then
        echo "Release directory is not owned by the installer user: ${release_directory}" >&2
        return 1
    fi
    if ! python3 - "${release_directory}" <<'PY'
import os
import stat
import sys

release_directory = sys.argv[1]
expected = {
    "app-release.apk",
    "app-release.apk.sha256",
    "version.json",
}
actual = set(os.listdir(release_directory))
if actual != expected:
    print(
        "Release directory members differ from the required three-file bundle",
        file=sys.stderr,
    )
    sys.exit(1)
for name in expected:
    member = os.path.join(release_directory, name)
    member_stat = os.lstat(member)
    if (
        not stat.S_ISREG(member_stat.st_mode)
        or member_stat.st_nlink != 1
        or member_stat.st_uid != os.geteuid()
    ):
        print(
            f"Release member must be owned and non-hardlinked: {member}",
            file=sys.stderr,
        )
        sys.exit(1)
PY
    then
        return 1
    fi

    for path in \
        "${release_directory}/app-release.apk" \
        "${release_directory}/app-release.apk.sha256" \
        "${release_directory}/version.json"
    do
        if [ -L "${path}" ] || [ ! -f "${path}" ] || [ ! -r "${path}" ]; then
            echo "Release member is missing, unreadable, or not a regular file: ${path}" >&2
            return 1
        fi
        mode="$(stat -c '%a' "${path}")" || return 1
        if [ "${mode}" != "444" ]; then
            echo "Release member must have mode 444: ${path}" >&2
            return 1
        fi
    done

    actual_sha256="$(
        sha256sum "${release_directory}/app-release.apk" | awk '{print $1}'
    )" || return 1
    if [ "${actual_sha256}" != "${release_sha256}" ]; then
        echo "Release APK checksum does not match its content-addressed directory" >&2
        return 1
    fi
    if ! printf '%s  app-release.apk\n' "${release_sha256}" |
        cmp -s - "${release_directory}/app-release.apk.sha256"
    then
        echo "Release checksum file is invalid" >&2
        return 1
    fi
    if ! validate_metadata \
        "${release_directory}/version.json" \
        "${release_directory}/app-release.apk" \
        "${release_sha256}" \
        "${metadata_mode}"
    then
        return 1
    fi
    if [ -n "${expected_metadata_path}" ] &&
       ! cmp -s \
           "${expected_metadata_path}" \
           "${release_directory}/version.json"
    then
        echo "Existing content-addressed release metadata differs from the candidate" >&2
        return 1
    fi
}

ACTIVE_TARGET=""
ACTIVE_STATE_DIR=""
ACTIVE_CURRENT_SHA256=""
ACTIVE_CURRENT_RELEASE=""
ACTIVE_PREVIOUS_SHA256=""
ACTIVE_PREVIOUS_RELEASE=""

load_active_state() {
    local validation_scope="${1:-all}"
    local active_target
    local state_id
    local state_directory
    local state_mode
    local current_target
    local current_sha256
    local current_release
    local previous_target
    local previous_sha256
    local previous_release

    case "${validation_scope}" in
        layout|current|all)
            ;;
        *)
            echo "Unknown active-state validation scope: ${validation_scope}" >&2
            return 1
            ;;
    esac

    if [ ! -L "${ACTIVE_LINK}" ]; then
        echo "Active release pointer is missing or is not a symbolic link" >&2
        return 1
    fi
    if [ "$(stat -c '%u:%h' "${ACTIVE_LINK}")" != "${CURRENT_PROCESS_UID}:1" ]; then
        echo "Active release pointer must be owned and singly linked" >&2
        return 1
    fi
    active_target="$(readlink -- "${ACTIVE_LINK}")" || return 1
    if [[ ! "${active_target}" =~ ^states/([A-Za-z0-9][A-Za-z0-9._-]{0,127})$ ]]; then
        echo "Active release pointer has an unsafe target: ${active_target}" >&2
        return 1
    fi
    state_id="${BASH_REMATCH[1]}"
    state_directory="${STATES_DIR}/${state_id}"
    if [ -L "${state_directory}" ] || [ ! -d "${state_directory}" ]; then
        echo "Active state directory is missing or is a symbolic link" >&2
        return 1
    fi
    state_mode="$(stat -c '%a' "${state_directory}")" || return 1
    if [ "${state_mode}" != "555" ]; then
        echo "Active state directory must have mode 555" >&2
        return 1
    fi
    if [ "$(stat -c '%u' "${state_directory}")" != "${CURRENT_PROCESS_UID}" ]; then
        echo "Active state directory is not owned by the installer user" >&2
        return 1
    fi
    if ! python3 - "${state_directory}" <<'PY'
import os
import sys

state_directory = sys.argv[1]
actual = set(os.listdir(state_directory))
if actual not in ({"current"}, {"current", "previous"}):
    print(
        "Active state must contain only current and optional previous pointers",
        file=sys.stderr,
    )
    sys.exit(1)
for name in actual:
    member = os.lstat(os.path.join(state_directory, name))
    if not os.path.islink(os.path.join(state_directory, name)):
        print("Active state members must be symbolic links", file=sys.stderr)
        sys.exit(1)
    if member.st_uid != os.geteuid():
        print("Active state members must be owned by the installer user", file=sys.stderr)
        sys.exit(1)
PY
    then
        return 1
    fi

    if [ ! -L "${state_directory}/current" ]; then
        echo "Active state has no current release pointer" >&2
        return 1
    fi
    current_target="$(readlink -- "${state_directory}/current")" || return 1
    if [[ ! "${current_target}" =~ ^\.\./\.\./releases/([0-9a-f]{64})$ ]]; then
        echo "Current release pointer has an unsafe target: ${current_target}" >&2
        return 1
    fi
    current_sha256="${BASH_REMATCH[1]}"
    current_release="${RELEASES_DIR}/${current_sha256}"
    if [ "${validation_scope}" != "layout" ]; then
        if ! validate_release_bundle \
            "${current_release}" \
            "${current_sha256}" \
            "managed"
        then
            echo "Current release bundle failed integrity validation" >&2
            return 1
        fi
    fi

    previous_sha256=""
    if [ -e "${state_directory}/previous" ] ||
       [ -L "${state_directory}/previous" ]
    then
        if [ ! -L "${state_directory}/previous" ]; then
            echo "Previous release pointer is not a symbolic link" >&2
            return 1
        fi
        previous_target="$(
            readlink -- "${state_directory}/previous"
        )" || return 1
        if [[ ! "${previous_target}" =~ ^\.\./\.\./releases/([0-9a-f]{64})$ ]]; then
            echo "Previous release pointer has an unsafe target: ${previous_target}" >&2
            return 1
        fi
        previous_sha256="${BASH_REMATCH[1]}"
        previous_release="${RELEASES_DIR}/${previous_sha256}"
        if [ "${validation_scope}" = "all" ]; then
            if ! validate_release_bundle \
                "${previous_release}" \
                "${previous_sha256}" \
                "managed"
            then
                echo "Previous release bundle failed integrity validation" >&2
                return 1
            fi
        fi
    fi

    ACTIVE_TARGET="${active_target}"
    ACTIVE_STATE_DIR="${state_directory}"
    ACTIVE_CURRENT_SHA256="${current_sha256}"
    ACTIVE_CURRENT_RELEASE="${current_release}"
    ACTIVE_PREVIOUS_SHA256="${previous_sha256}"
    ACTIVE_PREVIOUS_RELEASE="${previous_release:-}"
}

LEGACY_SHA256=""

validate_legacy_bundle() {
    local legacy_apk="${APK_DIR}/app-release.apk"
    local legacy_checksum="${APK_DIR}/app-release.apk.sha256"
    local legacy_metadata="${APK_DIR}/version.json"
    local path
    local mode
    local link_count
    local actual_sha256

    for path in "${legacy_apk}" "${legacy_checksum}" "${legacy_metadata}"; do
        if [ -L "${path}" ] || [ ! -f "${path}" ] || [ ! -r "${path}" ]; then
            echo "Legacy import member is missing, unreadable, or not a regular file: ${path}" >&2
            return 1
        fi
        link_count="$(stat -c '%h' "${path}")" || return 1
        if [ "${link_count}" != "1" ]; then
            echo "Legacy import member must not be a hardlink: ${path}" >&2
            return 1
        fi
        mode="$(stat -c '%a' "${path}")" || return 1
        case "${mode: -1}" in
            4|5|6|7)
                ;;
            *)
                echo "Legacy import member must be world-readable: ${path}" >&2
                return 1
                ;;
        esac
    done

    actual_sha256="$(
        sha256sum "${legacy_apk}" | awk '{print $1}'
    )" || return 1
    if [ "${actual_sha256}" != "${HISTORICAL_EXPECTED_SHA256}" ]; then
        echo "Legacy APK does not match the trusted historical checksum" >&2
        return 1
    fi
    if ! printf '%s  app-release.apk\n' "${actual_sha256}" |
        cmp -s - "${legacy_checksum}"
    then
        echo "Legacy import checksum file is invalid" >&2
        return 1
    fi
    if ! validate_metadata \
        "${legacy_metadata}" \
        "${legacy_apk}" \
        "${actual_sha256}" \
        "legacy-flat"
    then
        echo "Legacy import metadata failed validation" >&2
        return 1
    fi

    LEGACY_SHA256="${actual_sha256}"
}

restore_active_pointer() {
    local active_target="$1"

    if ! ln -s -- "${active_target}" "${TMP_DIR}/active.restore"; then
        return 1
    fi
    if ! mv -Tf -- "${TMP_DIR}/active.restore" "${ACTIVE_LINK}"; then
        return 1
    fi
    if ! sync -f "${APK_DIR}"; then
        return 1
    fi
    ACTIVE_SWITCH_UNCERTAIN=false
}

confirm_active_release_durable() {
    local expected_sha256="$1"

    ACTIVE_SWITCH_UNCERTAIN=true
    if ! load_active_state "current"; then
        echo "Active APK state failed integrity validation during durability confirmation" >&2
        return 1
    fi
    if [ "${ACTIVE_CURRENT_SHA256}" != "${expected_sha256}" ]; then
        echo "Active APK release does not match the expected durability target" >&2
        return 1
    fi
    if ! sync -f "${APK_DIR}"; then
        echo "Could not durably synchronize the already-active APK release" >&2
        return 1
    fi
    if ! load_active_state "current"; then
        echo "Active APK state failed integrity validation after durability synchronization" >&2
        return 1
    fi
    if [ "${ACTIVE_CURRENT_SHA256}" != "${expected_sha256}" ]; then
        echo "Active APK release changed during durability confirmation" >&2
        return 1
    fi
    ACTIVE_SWITCH_UNCERTAIN=false
}

perform_legacy_import() {
    local import_sha256
    local import_release_dir
    local import_release_staging
    local import_state_id
    local import_state_dir
    local import_state_staging

    if [ -L "${ACTIVE_LINK}" ]; then
        if ! load_active_state "current"; then
            fail "Existing managed APK state is invalid; legacy import was not attempted"
        fi
        if [ "${ACTIVE_CURRENT_SHA256}" = "${HISTORICAL_EXPECTED_SHA256}" ]; then
            if ! confirm_active_release_durable \
                "${HISTORICAL_EXPECTED_SHA256}"
            then
                fail "Trusted legacy APK is active but durability confirmation failed"
            fi
            echo "Trusted legacy APK release is already managed and active"
            echo "Durability of the active release pointer was confirmed"
            echo "Public path deploy/apk/active/current"
            return 0
        fi
        fail "A different managed APK release is already active"
    fi

    if ! validate_legacy_bundle; then
        fail "Legacy flat three-file bundle failed trusted import validation"
    fi
    import_sha256="${LEGACY_SHA256}"
    import_release_dir="${RELEASES_DIR}/${import_sha256}"

    if [ -e "${import_release_dir}" ] ||
       [ -L "${import_release_dir}" ]
    then
        if ! validate_release_bundle \
            "${import_release_dir}" \
            "${import_sha256}" \
            "managed" \
            "${APK_DIR}/version.json"
        then
            fail "Existing managed legacy release is invalid or differs from the trusted flat bundle"
        fi
    else
        if ! create_managed_staging release; then
            fail "Could not create managed legacy release staging"
        fi
        import_release_staging="${CREATED_STAGING_DIR}"
        cp -- \
            "${APK_DIR}/app-release.apk" \
            "${import_release_staging}/app-release.apk"
        cp -- \
            "${APK_DIR}/app-release.apk.sha256" \
            "${import_release_staging}/app-release.apk.sha256"
        cp -- \
            "${APK_DIR}/version.json" \
            "${import_release_staging}/version.json"
        chmod 0444 -- \
            "${import_release_staging}/app-release.apk" \
            "${import_release_staging}/app-release.apk.sha256" \
            "${import_release_staging}/version.json"
        chmod 0555 -- "${import_release_staging}"
        if ! validate_release_bundle \
            "${import_release_staging}" \
            "${import_sha256}" \
            "managed" \
            "${APK_DIR}/version.json"
        then
            fail "Staged legacy release failed managed validation"
        fi
        if ! mv -T -- \
            "${import_release_staging}" \
            "${import_release_dir}"
        then
            fail "Could not finalize managed legacy release"
        fi
        if ! sync -f "${APK_DIR}"; then
            fail "Could not durably synchronize the managed legacy release"
        fi
    fi

    import_state_id="$(
        date -u '+%Y%m%dT%H%M%SZ'
    )-import-${import_sha256:0:12}-$$-${RANDOM}"
    import_state_dir="${STATES_DIR}/${import_state_id}"
    if [ -e "${import_state_dir}" ] ||
       [ -L "${import_state_dir}" ]
    then
        fail "Generated legacy import state already exists: ${import_state_id}"
    fi

    if ! create_managed_staging state; then
        fail "Could not create managed legacy state staging"
    fi
    import_state_staging="${CREATED_STAGING_DIR}"
    if ! ln -s -- "../../releases/${import_sha256}" \
        "${import_state_staging}/current"
    then
        fail "Could not prepare imported legacy current pointer"
    fi
    chmod 0555 -- "${import_state_staging}"
    if ! mv -T -- \
        "${import_state_staging}" \
        "${import_state_dir}"
    then
        fail "Could not finalize managed legacy state"
    fi
    if ! sync -f "${APK_DIR}"; then
        fail "Could not durably synchronize the managed legacy state"
    fi

    if ! ln -s -- "states/${import_state_id}" \
        "${TMP_DIR}/active.import"
    then
        fail "Could not prepare imported legacy active pointer"
    fi
    ACTIVE_SWITCH_UNCERTAIN=true
    if ! mv -Tf -- "${TMP_DIR}/active.import" "${ACTIVE_LINK}"; then
        fail "Could not atomically activate the imported legacy release"
    fi

    if ! sync -f "${APK_DIR}" ||
       ! load_active_state "current" ||
       [ "${ACTIVE_TARGET}" != "states/${import_state_id}" ] ||
       [ "${ACTIVE_CURRENT_SHA256}" != "${import_sha256}" ]
    then
        echo "Post-import verification failed" >&2
        if rm -f -- "${ACTIVE_LINK}" && sync -f "${APK_DIR}"; then
            ACTIVE_SWITCH_UNCERTAIN=false
            echo "Failed imported active pointer was removed" >&2
        else
            echo "Could not remove the failed imported active pointer; manual recovery is required" >&2
        fi
        exit 1
    fi

    ACTIVE_SWITCH_UNCERTAIN=false
    echo "Imported and activated trusted legacy APK release ${import_sha256}"
    echo "Public path deploy/apk/active/current"
}

perform_rollback() {
    local old_active_target
    local old_current_sha256
    local old_current_release
    local rollback_sha256
    local rollback_release
    local preserve_failed_current=false
    local rollback_target_prefix
    local rollback_state_id
    local rollback_state_dir
    local rollback_state_staging

    if [ ! -L "${ACTIVE_LINK}" ]; then
        fail "No managed active APK state exists to roll back"
    fi
    if ! load_active_state "layout"; then
        fail "Active APK pointer layout is unsafe; rollback was not attempted"
    fi

    old_active_target="${ACTIVE_TARGET}"
    old_current_sha256="${ACTIVE_CURRENT_SHA256}"
    old_current_release="${ACTIVE_CURRENT_RELEASE}"
    rollback_target_prefix="${HISTORICAL_EXPECTED_SHA256:0:12}"

    if [ "${old_current_sha256}" = "${HISTORICAL_EXPECTED_SHA256}" ] &&
       [[ "${ACTIVE_TARGET}" =~ ^states/[0-9]{8}T[0-9]{6}Z-rollback-${rollback_target_prefix}-[0-9]+-[0-9]+$ ]]
    then
        if ! confirm_active_release_durable \
            "${HISTORICAL_EXPECTED_SHA256}"
        then
            fail "Trusted rollback target is active but durability confirmation failed"
        fi
        echo "Trusted rollback target is already active"
        echo "Durability of the active release pointer was confirmed"
        echo "Public path deploy/apk/active/current"
        return 0
    fi

    if [ -n "${ACTIVE_PREVIOUS_SHA256}" ]; then
        rollback_sha256="${ACTIVE_PREVIOUS_SHA256}"
        rollback_release="${ACTIVE_PREVIOUS_RELEASE}"
        if [ "${rollback_sha256}" != "${HISTORICAL_EXPECTED_SHA256}" ]; then
            fail "Managed previous APK does not match the trusted rollback checksum"
        fi
        if ! validate_release_bundle \
            "${rollback_release}" \
            "${rollback_sha256}" \
            "managed"
        then
            fail "Managed previous APK bundle is not safe to activate"
        fi
        if validate_release_bundle \
            "${old_current_release}" \
            "${old_current_sha256}" \
            "managed"
        then
            preserve_failed_current=true
        else
            echo "WARNING: current APK bundle is damaged; it will not become the next previous release" >&2
        fi

        rollback_state_id="$(
            date -u '+%Y%m%dT%H%M%SZ'
        )-rollback-${rollback_sha256:0:12}-$$-${RANDOM}"
        rollback_state_dir="${STATES_DIR}/${rollback_state_id}"
        if [ -e "${rollback_state_dir}" ] ||
           [ -L "${rollback_state_dir}" ]
        then
            fail "Generated rollback state already exists: ${rollback_state_id}"
        fi

        if ! create_managed_staging state; then
            fail "Could not create rollback state staging"
        fi
        rollback_state_staging="${CREATED_STAGING_DIR}"
        ln -s -- "../../releases/${rollback_sha256}" \
            "${rollback_state_staging}/current"
        if [ "${preserve_failed_current}" = true ]; then
            ln -s -- "../../releases/${old_current_sha256}" \
                "${rollback_state_staging}/previous"
        fi
        chmod 0555 -- "${rollback_state_staging}"
        if ! mv -T -- \
            "${rollback_state_staging}" \
            "${rollback_state_dir}"
        then
            fail "Could not finalize rollback state"
        fi
        if ! sync -f "${APK_DIR}"; then
            fail "Could not durably synchronize the rollback state"
        fi

        if ! ln -s -- "states/${rollback_state_id}" \
            "${TMP_DIR}/active.rollback"
        then
            fail "Could not prepare rollback active pointer"
        fi
        ACTIVE_SWITCH_UNCERTAIN=true
        if ! mv -Tf -- "${TMP_DIR}/active.rollback" "${ACTIVE_LINK}"; then
            fail "Could not atomically activate the managed previous APK"
        fi

        if ! sync -f "${APK_DIR}" ||
           ! load_active_state "current" ||
           [ "${ACTIVE_TARGET}" != "states/${rollback_state_id}" ] ||
           [ "${ACTIVE_CURRENT_SHA256}" != "${rollback_sha256}" ]
        then
            echo "Post-rollback verification failed" >&2
            if restore_active_pointer "${old_active_target}"; then
                echo "Original active APK pointer was restored" >&2
            else
                echo "Could not restore the original active APK pointer; manual recovery is required" >&2
            fi
            exit 1
        fi

        ACTIVE_SWITCH_UNCERTAIN=false
        echo "Rolled back to managed APK release ${rollback_sha256}"
        echo "Public path deploy/apk/active/current"
        return 0
    fi

    fail "Active APK state has no managed previous release to roll back to"
}

if [ "${INSTALL_MODE}" = "import-legacy" ]; then
    perform_legacy_import
    exit 0
fi

if [ "${INSTALL_MODE}" = "rollback" ]; then
    perform_rollback
    exit 0
fi

HAD_ACTIVE=false
OLD_ACTIVE_TARGET=""
OLD_CURRENT_SHA256=""
OLD_CURRENT_RELEASE=""
OLD_PREVIOUS_SHA256=""

if [ -L "${ACTIVE_LINK}" ]; then
    if ! load_active_state "current"; then
        fail "Existing managed APK state is invalid; no release was changed"
    fi
    HAD_ACTIVE=true
    OLD_ACTIVE_TARGET="${ACTIVE_TARGET}"
    OLD_CURRENT_SHA256="${ACTIVE_CURRENT_SHA256}"
    OLD_CURRENT_RELEASE="${ACTIVE_CURRENT_RELEASE}"
    OLD_PREVIOUS_SHA256="${ACTIVE_PREVIOUS_SHA256}"
fi

echo "Verified candidate APK bundle"
echo "SHA-256 ${ACTUAL_SHA256}"

if [ "${INSTALL_MODE}" = "verify" ]; then
    echo "Verification only; active release was not changed"
    exit 0
fi

RELEASE_DIR="${RELEASES_DIR}/${ACTUAL_SHA256}"
if [ -e "${RELEASE_DIR}" ] || [ -L "${RELEASE_DIR}" ]; then
    if ! validate_release_bundle \
        "${RELEASE_DIR}" \
        "${ACTUAL_SHA256}" \
        "policy" \
        "${TMP_METADATA}"
    then
        fail "Existing content-addressed release is invalid or differs from the candidate"
    fi
else
    if ! create_managed_staging release; then
        fail "Could not create content-addressed release staging"
    fi
    RELEASE_STAGING="${CREATED_STAGING_DIR}"
    cp -- "${TMP_APK}" "${RELEASE_STAGING}/app-release.apk"
    cp -- "${TMP_METADATA}" "${RELEASE_STAGING}/version.json"
    printf '%s  app-release.apk\n' "${ACTUAL_SHA256}" \
        > "${RELEASE_STAGING}/app-release.apk.sha256"
    chmod 0444 -- \
        "${RELEASE_STAGING}/app-release.apk" \
        "${RELEASE_STAGING}/app-release.apk.sha256" \
        "${RELEASE_STAGING}/version.json"
    chmod 0555 -- "${RELEASE_STAGING}"

    if ! validate_release_bundle \
        "${RELEASE_STAGING}" \
        "${ACTUAL_SHA256}" \
        "policy" \
        "${TMP_METADATA}"
    then
        fail "Staged release bundle failed validation"
    fi
    if ! mv -T -- "${RELEASE_STAGING}" "${RELEASE_DIR}"; then
        fail "Could not finalize content-addressed release directory"
    fi
    if ! validate_release_bundle \
        "${RELEASE_DIR}" \
        "${ACTUAL_SHA256}" \
        "policy" \
        "${TMP_METADATA}"
    then
        fail "Finalized content-addressed release failed validation"
    fi
    if ! sync -f "${APK_DIR}"; then
        fail "Could not durably synchronize the finalized release"
    fi
fi

if [ "${HAD_ACTIVE}" = true ] &&
   [ "${OLD_CURRENT_SHA256}" = "${ACTUAL_SHA256}" ]
then
    if ! confirm_active_release_durable "${ACTUAL_SHA256}"; then
        fail "Candidate bundle is active but durability confirmation failed"
    fi
    echo "Candidate bundle is already active; no state switch was needed"
    echo "Durability of the active release pointer was confirmed"
    exit 0
fi

STATE_ID="$(
    date -u '+%Y%m%dT%H%M%SZ'
)-${ACTUAL_SHA256:0:12}-$$-${RANDOM}"
STATE_DIR="${STATES_DIR}/${STATE_ID}"
if [ -e "${STATE_DIR}" ] || [ -L "${STATE_DIR}" ]; then
    fail "Generated release state already exists: ${STATE_ID}"
fi

if ! create_managed_staging state; then
    fail "Could not create release state staging"
fi
STATE_STAGING="${CREATED_STAGING_DIR}"
if ! ln -s -- \
    "../../releases/${ACTUAL_SHA256}" \
    "${STATE_STAGING}/current"
then
    fail "Could not prepare current release pointer"
fi
if [ "${HAD_ACTIVE}" = true ]; then
    if ! ln -s -- "../../releases/${OLD_CURRENT_SHA256}" \
        "${STATE_STAGING}/previous"
    then
        fail "Could not prepare previous release pointer"
    fi
fi
chmod 0555 -- "${STATE_STAGING}"
if ! mv -T -- "${STATE_STAGING}" "${STATE_DIR}"; then
    fail "Could not finalize release state"
fi
if ! sync -f "${APK_DIR}"; then
    fail "Could not durably synchronize the finalized release state"
fi

if ! ln -s -- "states/${STATE_ID}" "${TMP_DIR}/active.next"; then
    fail "Could not prepare active release pointer"
fi
ACTIVE_SWITCH_UNCERTAIN=true
if ! mv -Tf -- "${TMP_DIR}/active.next" "${ACTIVE_LINK}"; then
    fail "Could not atomically activate the verified APK bundle"
fi

POST_VERIFY_OK=true
if ! sync -f "${APK_DIR}"; then
    echo "Could not durably synchronize the active release pointer" >&2
    POST_VERIFY_OK=false
fi
if [ "${POST_VERIFY_OK}" = true ] && ! load_active_state; then
    POST_VERIFY_OK=false
elif [ "${ACTIVE_TARGET}" != "states/${STATE_ID}" ] ||
     [ "${ACTIVE_CURRENT_SHA256}" != "${ACTUAL_SHA256}" ] ||
     [ "${ACTIVE_CURRENT_RELEASE}" != "${RELEASE_DIR}" ]
then
    echo "Activated release pointer did not resolve to the candidate" >&2
    POST_VERIFY_OK=false
elif [ "${HAD_ACTIVE}" = true ] &&
     [ "${ACTIVE_PREVIOUS_SHA256}" != "${OLD_CURRENT_SHA256}" ]
then
    echo "Activated state did not preserve the previous current release" >&2
    POST_VERIFY_OK=false
elif [ "${HAD_ACTIVE}" = false ] &&
     [ -n "${ACTIVE_PREVIOUS_SHA256}" ]
then
    echo "First activation unexpectedly created a previous release pointer" >&2
    POST_VERIFY_OK=false
elif ! validate_release_bundle \
    "${ACTIVE_CURRENT_RELEASE}" \
    "${ACTUAL_SHA256}" \
    "policy" \
    "${TMP_METADATA}"
then
    POST_VERIFY_OK=false
fi

if [ "${POST_VERIFY_OK}" != true ]; then
    echo "Post-activation verification failed" >&2
    if [ "${HAD_ACTIVE}" = true ]; then
        if restore_active_pointer "${OLD_ACTIVE_TARGET}" &&
           load_active_state "current" &&
           [ "${ACTIVE_TARGET}" = "${OLD_ACTIVE_TARGET}" ] &&
           [ "${ACTIVE_CURRENT_SHA256}" = "${OLD_CURRENT_SHA256}" ]
        then
            echo "Previous active release was restored" >&2
            exit 1
        fi
        echo "Automatic rollback failed; write-protected release and state directories were retained for recovery" >&2
        exit 1
    fi

    if rm -f -- "${ACTIVE_LINK}" && sync -f "${APK_DIR}"; then
        ACTIVE_SWITCH_UNCERTAIN=false
        echo "Failed first activation was removed; write-protected release and state directories were retained" >&2
    else
        echo "Could not remove failed first activation; manual recovery is required" >&2
    fi
    exit 1
fi

ACTIVE_SWITCH_UNCERTAIN=false
echo "Activated verified APK bundle"
echo "Release deploy/apk/releases/${ACTUAL_SHA256}"
echo "Public path deploy/apk/active/current"
