#!/bin/bash
# Install an externally published APK after verifying its SHA-256 checksum.
# Usage: bash deploy/install-apk.sh <apk-url> <sha256> [version-json-url]

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <apk-url> <sha256> [version-json-url]" >&2
    exit 2
fi

APK_URL="$1"
EXPECTED_SHA256="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
VERSION_URL="${3:-}"

if [[ ! "${EXPECTED_SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Expected SHA-256 must contain exactly 64 hexadecimal characters" >&2
    exit 2
fi

cd "$(dirname "$0")/.."
APK_DIR="deploy/apk"
APK_TARGET="${APK_DIR}/app-release.apk"
VERSION_TARGET="${APK_DIR}/version.json"
mkdir -p "${APK_DIR}"

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT

curl --fail --location --silent --show-error \
    --output "${TMP_DIR}/app-release.apk" "${APK_URL}"
ACTUAL_SHA256="$(sha256sum "${TMP_DIR}/app-release.apk" | awk '{print $1}')"
if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then
    echo "APK checksum mismatch; existing artifact was not changed" >&2
    exit 1
fi

if [ -n "${VERSION_URL}" ]; then
    curl --fail --location --silent --show-error \
        --output "${TMP_DIR}/version.json" "${VERSION_URL}"
    if [ ! -s "${TMP_DIR}/version.json" ]; then
        echo "Downloaded version.json is empty" >&2
        exit 1
    fi
fi

if [ -f "${APK_TARGET}" ]; then
    cp --preserve=mode,timestamps "${APK_TARGET}" "${APK_TARGET}.previous"
fi
if [ -n "${VERSION_URL}" ] && [ -f "${VERSION_TARGET}" ]; then
    cp --preserve=mode,timestamps "${VERSION_TARGET}" "${VERSION_TARGET}.previous"
fi

mv -f "${TMP_DIR}/app-release.apk" "${APK_TARGET}"
if [ -n "${VERSION_URL}" ]; then
    mv -f "${TMP_DIR}/version.json" "${VERSION_TARGET}"
fi

echo "Installed ${APK_TARGET}"
echo "SHA-256 ${ACTUAL_SHA256}"
