#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"
REPO_ROOT="$(
    cd -- "${SCRIPT_DIR}/../.." >/dev/null 2>&1
    pwd
)"
MANUAL_RUNBOOK="${REPO_ROOT}/docs/MANUAL_RELEASE_RUNBOOK.md"
IP_RUNBOOK="${REPO_ROOT}/docs/IP_HTTPS_RELEASE_RUNBOOK.md"
DIRECTORY_ANCHOR="${REPO_ROOT}/deploy/apk/.gitkeep"
TEST_ROOT="$(mktemp -d)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PASS_COUNT=0

cleanup() {
    case "${TEST_ROOT}" in
        /tmp/*|/var/tmp/*)
            rm -rf -- "${TEST_ROOT}"
            ;;
        *)
            printf 'Refusing to remove unexpected test directory: %s\n' \
                "${TEST_ROOT}" >&2
            ;;
    esac
}
trap cleanup EXIT

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'ok %d - %s\n' "${PASS_COUNT}" "$1"
}

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

establish_test_guard() {
    local repo="$1"
    local apk_directory="${repo}/deploy/apk"
    local guard="${apk_directory}/.install.migration-guard"
    local current_inode
    local recorded_inode
    local status_output

    current_inode="$(stat -Lc '%d:%i' "${apk_directory}")"
    if [ -e "${guard}" ] || [ -L "${guard}" ]; then
        test -f "${guard}" ||
            fail "existing migration guard is not a regular file"
        test ! -L "${guard}" ||
            fail "existing migration guard is a symbolic link"
        test "$(stat -c '%u' "${guard}")" = "$(id -u)" ||
            fail "existing migration guard has an unexpected owner"
        test "$(stat -c '%h' "${guard}")" = '1' ||
            fail "existing migration guard has multiple hard links"
        if [[ "$(uname -s)" != MINGW* ]]; then
            test "$(stat -c '%a' "${guard}")" = '600' ||
                fail "existing migration guard has an unsafe mode"
        fi
        recorded_inode="$(cat "${guard}")"
        [[ "${recorded_inode}" =~ ^[0-9]+:[0-9]+$ ]] ||
            fail "existing migration guard has invalid content"
        test "${recorded_inode}" = "${current_inode}" ||
            fail "existing migration guard records a stale inode"
    else
        test -z "$(
            git -C "${repo}" status \
                --porcelain \
                --untracked-files=all
        )" ||
            fail "worktree was dirty before creating migration guard"
        (
            umask 077
            printf '%s\n' "${current_inode}" > "${guard}"
        )
        recorded_inode="${current_inode}"
    fi

    status_output="$(
        git -C "${repo}" status \
            --porcelain \
            --untracked-files=all
    )"
    case "${status_output}" in
        ''|'?? deploy/apk/.install.migration-guard') ;;
        *)
            fail "worktree contains more than the deliberate migration guard"
            ;;
    esac
    printf '%s\n' "${recorded_inode}"
}

for required_file in \
    "${MANUAL_RUNBOOK}" \
    "${IP_RUNBOOK}" \
    "${DIRECTORY_ANCHOR}"
do
    test -f "${required_file}" ||
        fail "required release file is missing: ${required_file}"
done
pass "release runbook inputs exist"

MIGRATION_REPO="${TEST_ROOT}/migration-repo"
mkdir -p "${MIGRATION_REPO}/deploy/apk"
git -C "${MIGRATION_REPO}" init --quiet
git -C "${MIGRATION_REPO}" config user.name 'FitLoop CI'
git -C "${MIGRATION_REPO}" config user.email 'fitloop-ci@example.invalid'
printf '*.log\n' > "${MIGRATION_REPO}/.gitignore"
printf 'legacy apk\n' \
    > "${MIGRATION_REPO}/deploy/apk/app-release.apk"
printf 'legacy metadata\n' \
    > "${MIGRATION_REPO}/deploy/apk/version.json"
printf 'legacy alias apk\n' \
    > "${MIGRATION_REPO}/deploy/apk/fitloop-release.apk"
git -C "${MIGRATION_REPO}" add .gitignore
git -C "${MIGRATION_REPO}" add --force \
    deploy/apk/app-release.apk \
    deploy/apk/fitloop-release.apk \
    deploy/apk/version.json
git -C "${MIGRATION_REPO}" commit --quiet -m 'legacy flat release'
LEGACY_COMMIT="$(git -C "${MIGRATION_REPO}" rev-parse HEAD)"

git -C "${MIGRATION_REPO}" switch --quiet -c managed
git -C "${MIGRATION_REPO}" rm --quiet \
    deploy/apk/app-release.apk \
    deploy/apk/fitloop-release.apk \
    deploy/apk/version.json
mkdir -p "${MIGRATION_REPO}/deploy/apk"
cp -- "${REPO_ROOT}/.gitignore" "${MIGRATION_REPO}/.gitignore"
cp -- "${DIRECTORY_ANCHOR}" \
    "${MIGRATION_REPO}/deploy/apk/.gitkeep"
git -C "${MIGRATION_REPO}" add \
    .gitignore \
    deploy/apk/.gitkeep
git -C "${MIGRATION_REPO}" commit --quiet -m 'managed release layout'
MANAGED_COMMIT="$(git -C "${MIGRATION_REPO}" rev-parse HEAD)"

git -C "${MIGRATION_REPO}" switch --quiet \
    --create server "${LEGACY_COMMIT}"
MIGRATION_GUARD="${MIGRATION_REPO}/deploy/apk/.install.migration-guard"
APK_INODE_BEFORE="$(establish_test_guard "${MIGRATION_REPO}")"
test "$(
    git -C "${MIGRATION_REPO}" status \
        --porcelain \
        --untracked-files=all
)" = '?? deploy/apk/.install.migration-guard' ||
    fail "legacy baseline did not expose the deliberate migration guard"
test "$(establish_test_guard "${MIGRATION_REPO}")" = "${APK_INODE_BEFORE}" ||
    fail "legacy baseline guard rerun did not converge"
pass "legacy baseline safely reuses a pre-pull migration guard"

git -C "${MIGRATION_REPO}" pull --quiet --ff-only . managed
APK_INODE_AFTER="$(
    stat -Lc '%d:%i' "${MIGRATION_REPO}/deploy/apk"
)"

test "${APK_INODE_AFTER}" = "${APK_INODE_BEFORE}" ||
    fail "fast-forward replaced the bind-mounted APK directory inode"
test -f "${MIGRATION_GUARD}" ||
    fail "fast-forward removed the temporary migration guard"
git -C "${MIGRATION_REPO}" check-ignore --quiet \
    deploy/apk/.install.migration-guard ||
    fail "managed .gitignore does not cover the temporary migration guard"
test "$(establish_test_guard "${MIGRATION_REPO}")" = "${APK_INODE_BEFORE}" ||
    fail "post-fast-forward guard rerun did not converge"
test -z "$(
    git -C "${MIGRATION_REPO}" status \
        --porcelain \
        --untracked-files=all
)" ||
    fail "managed worktree is dirty after fast-forward"
test -f "${MIGRATION_REPO}/deploy/apk/.gitkeep" ||
    fail "fast-forward did not install the APK directory anchor"
test ! -e "${MIGRATION_REPO}/deploy/apk/app-release.apk" ||
    fail "fast-forward retained the tracked legacy APK"
test ! -e "${MIGRATION_REPO}/deploy/apk/version.json" ||
    fail "fast-forward retained the tracked legacy metadata"
test ! -e "${MIGRATION_REPO}/deploy/apk/fitloop-release.apk" ||
    fail "fast-forward retained the tracked legacy alias APK"
pass "guard survives fast-forward and safely converges after interruption"

rm -- "${MIGRATION_GUARD}"
test "$(establish_test_guard "${MIGRATION_REPO}")" = "${APK_INODE_AFTER}" ||
    fail "managed baseline could not create an ignored migration guard"
test -z "$(
    git -C "${MIGRATION_REPO}" status \
        --porcelain \
        --untracked-files=all
)" ||
    fail "managed baseline guard was not ignored"
test "$(establish_test_guard "${MIGRATION_REPO}")" = "${APK_INODE_AFTER}" ||
    fail "managed baseline guard rerun did not converge"
rm -- "${MIGRATION_GUARD}"
pass "managed baseline creates and reuses an ignored migration guard"

BOM_JSON="${TEST_ROOT}/version-with-bom.json"
printf '\357\273\277{"version":"0.1.5","versionCode":6}\n' \
    > "${BOM_JSON}"
"${PYTHON_BIN}" -c \
    'import json,pathlib,sys; json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig"))' \
    "${BOM_JSON}" ||
    fail "UTF-8 BOM metadata parser rejected valid JSON"
pass "UTF-8 BOM metadata parsing is portable"

for runbook in "${MANUAL_RUNBOOK}" "${IP_RUNBOOK}"; do
    if grep -Fq -- '-printf' "${runbook}"; then
        fail "runbook depends on GNU find formatting: ${runbook}"
    fi

    grep -Fq 'stat -c' "${runbook}" ||
        fail "runbook lacks BusyBox-compatible stat checks: ${runbook}"
    grep -Fq 'for path in' "${runbook}" ||
        fail "runbook lacks an explicit portable APK member loop: ${runbook}"
    grep -Fq 'decode("utf-8-sig")' "${runbook}" ||
        fail "runbook lacks BOM-safe public metadata parsing: ${runbook}"
done
pass "runbooks use BusyBox-compatible and BOM-safe verification"

grep -Fq 'deploy/apk/.gitkeep' "${MANUAL_RUNBOOK}" ||
    fail "manual runbook does not require the directory anchor"
grep -Fq 'deploy/apk/.install.migration-guard' "${MANUAL_RUNBOOK}" ||
    fail "manual runbook does not create the temporary migration guard"
grep -Fq "stat -Lc '%d:%i' deploy/apk" "${MANUAL_RUNBOOK}" ||
    fail "manual runbook does not compare the APK directory inode"
pass "manual migration requires both directory guards and the inode gate"

if ! "${PYTHON_BIN}" - "${MANUAL_RUNBOOK}" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(
    r"if \[ ! -L deploy/apk/active \]; then"
    r"(?P<restore>.*?)"
    r"\nfi\n"
    r"(?P<verify>.*?)"
    r"\ntest -L deploy/apk/active",
    text,
    flags=re.DOTALL,
)
if match is None:
    print("manual runbook managed import block was not found", file=sys.stderr)
    raise SystemExit(1)
if "--import-legacy" in match.group("restore"):
    print("managed import is incorrectly conditional on missing active", file=sys.stderr)
    raise SystemExit(1)
if "--import-legacy" not in match.group("verify"):
    print("managed import is not rerun for durability confirmation", file=sys.stderr)
    raise SystemExit(1)
PY
then
    fail "manual migration can skip idempotent managed import verification"
fi
pass "manual migration always confirms managed import durability"

if ! "${PYTHON_BIN}" - \
    "${MANUAL_RUNBOOK}" \
    "${IP_RUNBOOK}" <<'PY'
import pathlib
import re
import sys

for raw_path in sys.argv[1:]:
    path = pathlib.Path(raw_path)
    text = path.read_text(encoding="utf-8")
    blocks = re.findall(
        r"```powershell[^\n]*\n(.*?)```",
        text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    for block in blocks:
        invokes_ssh = re.search(
            r"(?:^|[^\w])ssh(?:\.exe)?(?:[^\w]|$)|&\s*\$SshPath(?:[^\w]|$)",
            block,
            flags=re.IGNORECASE,
        )
        if invokes_ssh and "2>&1" in block:
            print(
                f"{path}: PowerShell SSH block merges stderr with 2>&1",
                file=sys.stderr,
            )
            raise SystemExit(1)
PY
then
    fail "runbook captures SSH stderr as PowerShell success evidence"
fi
grep -Fq '& $SshPath @SshArgs' "${IP_RUNBOOK}" ||
    fail "IP runbook lacks the checked PowerShell SSH invocation"
grep -Fq '$SshExitCode = $LASTEXITCODE' "${IP_RUNBOOK}" ||
    fail "IP runbook does not gate SSH success on the native exit code"
pass "PowerShell SSH verification uses the native exit code"

printf '1..%d\n' "${PASS_COUNT}"
