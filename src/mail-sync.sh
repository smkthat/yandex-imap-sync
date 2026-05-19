#!/bin/bash
set -euo pipefail

die() {
    echo "Error: $*" >&2
    exit 1
}

require_value() {
    local name="$1"
    local value="$2"
    if [[ -z "$value" ]]; then
        die "Missing required variable $name"
    fi
}

strip_email_domain() {
    local login="$1"
    echo "${login%@*}"
}

resolve_mailbox() {
    local prefix="$1"
    local mailbox_type_var="${prefix}_MAILBOX_TYPE"
    local mailbox_type="${!mailbox_type_var:-}"

    require_value "$mailbox_type_var" "$mailbox_type"

    case "$mailbox_type" in
        login)
            local login_var="${prefix}_IMAP_LOGIN"
            local password_var="${prefix}_IMAP_APP_PASSWORD"
            local login="${!login_var:-}"
            local password="${!password_var:-}"

            require_value "$login_var" "$login"
            require_value "$password_var" "$password"
            RESOLVED_IMAP_LOGIN="$login"
            RESOLVED_IMAP_APP_PASSWORD="$password"
            ;;
        shared)
            local domain_var="${prefix}_SHARED_MAILBOX_DOMAIN"
            local name_var="${prefix}_SHARED_MAILBOX_NAME"
            local delegate_var="${prefix}_DELEGATE_LOGIN"
            local password_var="${prefix}_IMAP_APP_PASSWORD"
            local domain="${!domain_var:-}"
            local name="${!name_var:-}"
            local delegate="${!delegate_var:-}"
            local password="${!password_var:-}"

            delegate="$(strip_email_domain "$delegate")"

            require_value "$domain_var" "$domain"
            require_value "$name_var" "$name"
            require_value "$delegate_var" "$delegate"
            require_value "$password_var" "$password"
            RESOLVED_IMAP_LOGIN="${domain}/${delegate}/${name}"
            RESOLVED_IMAP_APP_PASSWORD="$password"
            ;;
        *)
            die "${mailbox_type_var} must be one of: login, shared"
            ;;
    esac
}

resolve_mailbox SOURCE
SOURCE_RESOLVED_IMAP_LOGIN="$RESOLVED_IMAP_LOGIN"
SOURCE_RESOLVED_IMAP_APP_PASSWORD="$RESOLVED_IMAP_APP_PASSWORD"

resolve_mailbox TARGET
TARGET_RESOLVED_IMAP_LOGIN="$RESOLVED_IMAP_LOGIN"
TARGET_RESOLVED_IMAP_APP_PASSWORD="$RESOLVED_IMAP_APP_PASSWORD"

PARAMS=${PARAMS:-"--automap --useheader Message-Id --errorsmax 5"}
YANDEX_IMAP_SERVER=${YANDEX_IMAP_SERVER:-"imap.yandex.ru"}

IMAPSYNC_URL="https://raw.githubusercontent.com/imapsync/imapsync/master/imapsync"
IMAPSYNC_FILE="./imapsync"

wget -N -q --show-progress "$IMAPSYNC_URL" -O "$IMAPSYNC_FILE"
chmod +x "$IMAPSYNC_FILE"

echo "Запуск imapsync с параметрами: $PARAMS"
echo "Источник IMAP: $SOURCE_RESOLVED_IMAP_LOGIN"
echo "Целевой ящик IMAP: $TARGET_RESOLVED_IMAP_LOGIN"
/usr/bin/env perl "$IMAPSYNC_FILE" \
    --host1 "$YANDEX_IMAP_SERVER" --user1 "$SOURCE_RESOLVED_IMAP_LOGIN" --password1 "$SOURCE_RESOLVED_IMAP_APP_PASSWORD" \
    --host2 "$YANDEX_IMAP_SERVER" --user2 "$TARGET_RESOLVED_IMAP_LOGIN" --authmech2 LOGIN --password2 "$TARGET_RESOLVED_IMAP_APP_PASSWORD" \
    $PARAMS
