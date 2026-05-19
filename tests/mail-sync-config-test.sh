#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/src/mail-sync.sh"
WORK_DIR="$(mktemp -d)"
MOCK_BIN="$WORK_DIR/bin"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/wget" <<'MOCK'
#!/bin/bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -O)
            output="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
if [[ -z "$output" ]]; then
    echo "mock wget: missing -O output" >&2
    exit 1
fi
printf '#!/bin/sh\n' > "$output"
MOCK

cat >"$MOCK_BIN/perl" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" > "$CAPTURE_FILE"
MOCK

chmod +x "$MOCK_BIN/wget" "$MOCK_BIN/perl"

assert_arg_after() {
    local capture_file="$1"
    local option="$2"
    local expected="$3"
    local actual
    actual="$(awk -v option="$option" 'found { print; exit } $0 == option { found = 1 }' "$capture_file")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected $option to be followed by [$expected], got [$actual]" >&2
        echo "Captured args:" >&2
        sed 's/^/  /' "$capture_file" >&2
        exit 1
    fi
}

run_success_case() {
    local case_name="$1"
    local expected_user1="$2"
    local expected_password1="$3"
    local expected_user2="$4"
    local expected_password2="$5"
    shift 5
    local expected_host="imap.yandex.ru"
    local env_assignment
    for env_assignment in "$@"; do
        if [[ "$env_assignment" == YANDEX_IMAP_SERVER=* ]]; then
            expected_host="${env_assignment#YANDEX_IMAP_SERVER=}"
        fi
    done

    local case_dir="$WORK_DIR/$case_name"
    local capture_file="$case_dir/perl-args.txt"
    mkdir -p "$case_dir"

    (
        cd "$case_dir"
        env -i \
            PATH="$MOCK_BIN:/usr/bin:/bin" \
            CAPTURE_FILE="$capture_file" \
            PARAMS="--justlogin" \
            "$@" \
            bash "$SCRIPT_PATH" >/dev/null
    )

    assert_arg_after "$capture_file" "--host1" "$expected_host"
    assert_arg_after "$capture_file" "--user1" "$expected_user1"
    assert_arg_after "$capture_file" "--password1" "$expected_password1"
    assert_arg_after "$capture_file" "--host2" "$expected_host"
    assert_arg_after "$capture_file" "--user2" "$expected_user2"
    assert_arg_after "$capture_file" "--password2" "$expected_password2"
}

run_failure_case() {
    local case_name="$1"
    local expected_error="$2"
    shift 2

    local case_dir="$WORK_DIR/$case_name"
    local output_file="$case_dir/output.txt"
    mkdir -p "$case_dir"

    set +e
    (
        cd "$case_dir"
        env -i \
            PATH="$MOCK_BIN:/usr/bin:/bin" \
            CAPTURE_FILE="$case_dir/perl-args.txt" \
            PARAMS="--justlogin" \
            "$@" \
            bash "$SCRIPT_PATH"
    ) >"$output_file" 2>&1
    local exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]]; then
        echo "Expected [$case_name] to fail, but it exited with 0" >&2
        sed 's/^/  /' "$output_file" >&2
        exit 1
    fi

    if ! grep -Fq "$expected_error" "$output_file"; then
        echo "Expected [$case_name] output to contain [$expected_error]" >&2
        sed 's/^/  /' "$output_file" >&2
        exit 1
    fi
}

run_success_case \
    "login_to_login" \
    "source@example.com" \
    "source-password" \
    "target@example.org" \
    "target-password" \
    SOURCE_MAILBOX_TYPE="login" \
    SOURCE_IMAP_LOGIN="source@example.com" \
    SOURCE_IMAP_APP_PASSWORD="source-password" \
    TARGET_MAILBOX_TYPE="login" \
    TARGET_IMAP_LOGIN="target@example.org" \
    TARGET_IMAP_APP_PASSWORD="target-password"

run_success_case \
    "login_to_shared" \
    "source@example.com" \
    "source-password" \
    "example.org/john.doe/info" \
    "delegate-password" \
    SOURCE_MAILBOX_TYPE="login" \
    SOURCE_IMAP_LOGIN="source@example.com" \
    SOURCE_IMAP_APP_PASSWORD="source-password" \
    TARGET_MAILBOX_TYPE="shared" \
    TARGET_SHARED_MAILBOX_DOMAIN="example.org" \
    TARGET_SHARED_MAILBOX_NAME="info" \
    TARGET_DELEGATE_LOGIN="john.doe@example.org" \
    TARGET_IMAP_APP_PASSWORD="delegate-password"

run_success_case \
    "shared_to_login" \
    "example.org/john.doe/info" \
    "delegate-password" \
    "target@example.org" \
    "target-password" \
    SOURCE_MAILBOX_TYPE="shared" \
    SOURCE_SHARED_MAILBOX_DOMAIN="example.org" \
    SOURCE_SHARED_MAILBOX_NAME="info" \
    SOURCE_DELEGATE_LOGIN="john.doe" \
    SOURCE_IMAP_APP_PASSWORD="delegate-password" \
    TARGET_MAILBOX_TYPE="login" \
    TARGET_IMAP_LOGIN="target@example.org" \
    TARGET_IMAP_APP_PASSWORD="target-password"

run_success_case \
    "shared_to_shared" \
    "source.example.org/john.doe/source-info" \
    "source-delegate-password" \
    "target.example.org/jane.doe/target-info" \
    "target-delegate-password" \
    SOURCE_MAILBOX_TYPE="shared" \
    SOURCE_SHARED_MAILBOX_DOMAIN="source.example.org" \
    SOURCE_SHARED_MAILBOX_NAME="source-info" \
    SOURCE_DELEGATE_LOGIN="john.doe@example.ru" \
    SOURCE_IMAP_APP_PASSWORD="source-delegate-password" \
    TARGET_MAILBOX_TYPE="shared" \
    TARGET_SHARED_MAILBOX_DOMAIN="target.example.org" \
    TARGET_SHARED_MAILBOX_NAME="target-info" \
    TARGET_DELEGATE_LOGIN="jane.doe@example.ru" \
    TARGET_IMAP_APP_PASSWORD="target-delegate-password"

run_success_case \
    "custom_yandex_server" \
    "source@example.com" \
    "source-password" \
    "target@example.org" \
    "target-password" \
    SOURCE_MAILBOX_TYPE="login" \
    SOURCE_IMAP_LOGIN="source@example.com" \
    SOURCE_IMAP_APP_PASSWORD="source-password" \
    TARGET_MAILBOX_TYPE="login" \
    TARGET_IMAP_LOGIN="target@example.org" \
    TARGET_IMAP_APP_PASSWORD="target-password" \
    YANDEX_IMAP_SERVER="imap.ya.ru"

run_failure_case \
    "unknown_source_type" \
    "SOURCE_MAILBOX_TYPE must be one of: login, shared" \
    SOURCE_MAILBOX_TYPE="oauth" \
    SOURCE_IMAP_LOGIN="source@example.com" \
    SOURCE_IMAP_APP_PASSWORD="source-password" \
    TARGET_MAILBOX_TYPE="login" \
    TARGET_IMAP_LOGIN="target@example.org" \
    TARGET_IMAP_APP_PASSWORD="target-password"

run_failure_case \
    "missing_login_password" \
    "Missing required variable SOURCE_IMAP_APP_PASSWORD" \
    SOURCE_MAILBOX_TYPE="login" \
    SOURCE_IMAP_LOGIN="source@example.com" \
    TARGET_MAILBOX_TYPE="login" \
    TARGET_IMAP_LOGIN="target@example.org" \
    TARGET_IMAP_APP_PASSWORD="target-password"

run_failure_case \
    "missing_shared_domain" \
    "Missing required variable TARGET_SHARED_MAILBOX_DOMAIN" \
    SOURCE_MAILBOX_TYPE="login" \
    SOURCE_IMAP_LOGIN="source@example.com" \
    SOURCE_IMAP_APP_PASSWORD="source-password" \
    TARGET_MAILBOX_TYPE="shared" \
    TARGET_SHARED_MAILBOX_NAME="info" \
    TARGET_DELEGATE_LOGIN="john.doe" \
    TARGET_IMAP_APP_PASSWORD="target-password"

run_failure_case \
    "mailbox_type_required" \
    "Missing required variable SOURCE_MAILBOX_TYPE" \
    SOURCE_IMAP_LOGIN="source@example.com" \
    SOURCE_IMAP_APP_PASSWORD="source-password" \
    TARGET_MAILBOX_TYPE="login" \
    TARGET_IMAP_LOGIN="target@example.org" \
    TARGET_IMAP_APP_PASSWORD="target-password"

run_failure_case \
    "legacy_password_not_used" \
    "Missing required variable TARGET_IMAP_APP_PASSWORD" \
    SOURCE_MAILBOX_TYPE="login" \
    SOURCE_IMAP_LOGIN="source@example.com" \
    SOURCE_IMAP_APP_PASSWORD="source-password" \
    TARGET_MAILBOX_TYPE="login" \
    TARGET_IMAP_LOGIN="target@example.org" \
    DST_PASSWORD="legacy-target-password"

echo "mail-sync config tests passed"
