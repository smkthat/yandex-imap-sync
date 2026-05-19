# Running yandex-imap-sync in Docker

**English** | [Русский](README.ru.md)

---

## Table Of Contents

- [Running yandex-imap-sync in Docker](#running-yandex-imap-sync-in-docker)
  - [Table Of Contents](#table-of-contents)
  - [1. Prepare Configuration](#1-prepare-configuration)
  - [2. Build The Image](#2-build-the-image)
  - [3. Run](#3-run)
    - [Overriding Parameters](#overriding-parameters)
    - [Available `PARAMS` Modes](#available-params-modes)
    - [Underlying `imapsync` Reference](#underlying-imapsync-reference)
    - [Yandex Mailbox Modes](#yandex-mailbox-modes)
  - [4. Forward New Messages](#4-forward-new-messages)
    - [Recommended: Yandex 360 Admin Rule](#recommended-yandex-360-admin-rule)
    - [Alternative: Rule In The Source Mailbox](#alternative-rule-in-the-source-mailbox)
    - [Checks And Limits](#checks-and-limits)

## 1. Prepare Configuration

Make sure [Docker](https://docs.docker.com/get-docker/) and [Make](https://www.gnu.org/software/make/) are installed.

1. Copy `.env.example` to `.env`, or create `.env` manually:

   ```bash
   SOURCE_MAILBOX_TYPE=login
   SOURCE_IMAP_LOGIN=source@example.com
   SOURCE_IMAP_APP_PASSWORD=your_source_app_password_here

   TARGET_MAILBOX_TYPE=shared
   TARGET_SHARED_MAILBOX_DOMAIN=example.org
   TARGET_SHARED_MAILBOX_NAME=info
   TARGET_DELEGATE_LOGIN=john.doe
   TARGET_IMAP_APP_PASSWORD=your_target_delegate_app_password_here
   ```

   `TARGET_IMAP_APP_PASSWORD` is the Yandex Mail app password for the employee account `john.doe@example.org` that has access to the shared mailbox. The shared mailbox `info@example.org` does not need its own password.

   This script is intended for Yandex Mail/Yandex 360. It uses `imap.yandex.ru` by default. Override it with `YANDEX_IMAP_SERVER` if needed.

## 2. Build The Image

Build the Docker image:

```bash
make build
```

## 3. Run

Use `make` to manage the container:

- **Run with live logs** (recommended):

  ```bash
  make run-logs
  ```

- **Run in the background**:

  ```bash
  make run
  ```

- **Follow logs** (for a background container):

  ```bash
  make logs
  ```

- **Stop the container**:

  ```bash
  make stop
  ```

### Overriding Parameters

Pass extra `PARAMS` directly to the container when you need to change the sync mode:

```bash
# Login check only:
make run-logs PARAMS="--justlogin"

# Folder-only run:
make run-logs PARAMS="--automap --useheader Message-Id --errorsmax 5 --justfolders"
```

### Available `PARAMS` Modes

`PARAMS` are passed directly to `imapsync`. For a typical migration, use one of the modes below.

| Mode                | Command                                                              | What it does                                                                          |
| ------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Login check         | `--justlogin`                                                        | Checks source and target authentication only. Does not migrate folders or messages.   |
| Folder dry-run      | `--dry --justfolders --automap --useheader Message-Id --errorsmax 5` | Checks folder mapping and shows which folders would be created, without real changes. |
| Create/sync folders | `--justfolders --automap --useheader Message-Id --errorsmax 5`       | Creates missing target folders, but does not migrate messages.                        |
| Full migration      | `--automap --useheader Message-Id --errorsmax 5`                     | Creates missing folders and migrates messages with attachments.                       |

Recommended run order:

```bash
make run-logs PARAMS="--justlogin"
make run-logs PARAMS="--dry --justfolders --automap --useheader Message-Id --errorsmax 5"
make run-logs PARAMS="--automap --useheader Message-Id --errorsmax 5"
```

Main option notes:

- `--automap` maps standard folders such as `Sent`, `Drafts`, `Spam`, and `Trash`.
- `--useheader Message-Id` helps avoid duplicates on repeated runs.
- `--errorsmax 5` stops the process after 5 errors.
- `--dry` shows the action plan without changing the target mailbox.
- `--justfolders` works only with folders and does not migrate messages.

Do not add `--delete1` or `--delete2` unless you explicitly want to delete messages from the source or target mailbox.

### Underlying `imapsync` Reference

This Docker wrapper downloads and runs [`imapsync`](https://imapsync.lamiral.info/), a Perl command-line tool for one-way IMAP mailbox transfers. The wrapper builds the required `--host1`, `--user1`, `--password1`, `--host2`, `--user2`, and `--password2` arguments from `.env`, then appends `PARAMS` unchanged.

The modes above are safe presets for this project, not the full `imapsync` interface. `imapsync` supports many more arguments for folder mapping, folder selection, message filtering, deletion behavior, logging, authentication, OAuth, and debugging. The full list of available arguments is in the official [`imapsync` README OPTIONS section](https://imapsync.lamiral.info/README). The official [Unix tutorial](https://imapsync.lamiral.info/doc/TUTORIAL_Unix.html) is also useful for understanding dry-runs, folder-only runs, and why testing with a destination account first is safer.

### Yandex Mailbox Modes

The script supports two modes for each mailbox:

- `login`: a regular mailbox where the IMAP login is the email address.
- `shared`: a Yandex 360 shared mailbox where the IMAP login is built through an employee account with access.

Regular mailbox example:

```env
SOURCE_MAILBOX_TYPE=login
SOURCE_IMAP_LOGIN=source@example.com
SOURCE_IMAP_APP_PASSWORD=your_source_app_password_here
```

Shared mailbox example:

```env
TARGET_MAILBOX_TYPE=shared
TARGET_SHARED_MAILBOX_DOMAIN=example.org
TARGET_SHARED_MAILBOX_NAME=info
TARGET_DELEGATE_LOGIN=john.doe
TARGET_IMAP_APP_PASSWORD=your_target_delegate_app_password_here
```

For a shared mailbox, the script builds the technical IMAP login in this format:

```text
domain/employee_login/shared_mailbox_name
```

For example, `info@example.org` with employee `john.doe` becomes:

```text
example.org/john.doe/info
```

Supported sync directions:

- `login -> login`
- `login -> shared`
- `shared -> login`
- `shared -> shared`

*Migration can take a long time. With `make run-logs`, the container is automatically removed after the script exits.*

## 4. Forward New Messages

After migrating old messages, configure forwarding so new incoming mail for `source@example.com` lands in the shared mailbox `info@example.org`.

Forwarding only applies to new incoming messages. It does not move old inbox, sent, or outgoing messages; those are handled by `imapsync`.

### Recommended: Yandex 360 Admin Rule

1. Open the [organization admin console](https://admin.yandex.ru).
2. Go to `Mail -> Mail rules`.
3. Click `Add rule`.
4. In the conditions block, set:
   - field: `To`;
   - match type: `equals` or `contains`;
   - value: `source@example.com`.
5. In the actions block, choose `Forward` and enter `info@example.org`.
6. Save the rule, then save the rule list.

### Alternative: Rule In The Source Mailbox

If you do not have access to the organization admin console:

1. Sign in to `source@example.com`.
2. Open `All settings -> Message filtering rules -> Create rule`.
3. Configure a rule for new incoming messages.
4. Enable `Forward to address` and enter `info@example.org`.
5. If Yandex sends a confirmation email to `info@example.org`, open it and confirm forwarding.

### Checks And Limits

- After setup, send a test message to `source@example.com` and verify that it appears in `info@example.org`.
- Do not enable deletion from `source@example.com` immediately. Check several test messages first.
- Messages in `Spam` are usually not forwarded automatically.
- If the rule does not work, check rule priority and make sure no earlier rule stops further processing.

Yandex documentation:

- [Mail processing rules in Yandex 360](https://yandex.ru/support/yandex-360/business/admin/ru/mail/rules)
- [Forwarding messages to another address](https://yandex.ru/support/yandex-360/customers/mail/ru/web/preferences/filters/forwarding)
