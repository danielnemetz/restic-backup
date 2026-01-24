# Restic Backup Wrapper

A lightweight wrapper system to easily manage **Restic** backups (via Rclone). It supports multiple backup targets, pre/post-backup hooks (e.g., for database dumps), and interactive restoration.

## Features

- **Multi-Target**: Backup multiple directories with different tags in a single run.
- **Hooks**: Automatic execution of scripts _before_ (`pre-backup.d`) and _after_ (`post-backup.d`) the backup (ideal for Docker exports).
- **Retention**: Automatic cleanup of old snapshots (Daily, Weekly, Monthly, Yearly).
- **Restore UI**: Interactive script to select and restore snapshots.
- **Robust**: Failures in one backup target do not stop the entire process.

## Requirements

- `restic`
- `rclone` (configured for the target repository, e.g., Google Drive)

## Installation & Setup

1.  **Clone Repository:**

    ```bash
    git clone <repo-url> /path/to/backup-scripts
    cd /path/to/backup-scripts
    ```

2.  **Create Configuration:**
    Copy the example configuration and adjust it:

    ```bash
    cp .env.example .env
    nano .env
    ```

3.  **Important Settings in `.env`:**
    - `RESTIC_REPOSITORY`: Rclone path to the repository (e.g., `rclone:gdrive:backups/server`).
    - `RESTIC_PASSWORD`: Your Restic repository password.
    - `BACKUP_TARGETS`: List of paths to backup and their tags.
      ```bash
      # Format: "PATH:TAG PATH2:TAG2"
      BACKUP_TARGETS="/mnt/data:files /mnt/docker/db-dump:database"
      ```

## Usage

### Start Backup

Runs all configured backups, including pre/post hooks and retention cleanup.

```bash
./backup.sh
```

_Tip: Set this up as a Cronjob._

### Restore

Starts a wizard that lists all snapshots and lets you select what to restore and where.

```bash
./restore.sh
```

### Check

Verifies the consistency of the Restic repository.

```bash
./check.sh
```

## Hooks (Extensions)

Place executable scripts in the corresponding folders to extend the process:

- **`hooks/pre-backup.d/`**: Scripts here run **BEFORE** the backup.
  - _Example:_ `10-paperless-export.sh` (Exports Paperless-NGX documents).
  - _Important:_ If a pre-script fails (Exit Code `!= 0`), the backup is **aborted**.
- **`hooks/post-backup.d/`**: Scripts here run **AFTER** the backup (regardless of success).
  - _Example:_ `99-notify-push.sh` (Sends a push notification).

## Structure

```text
.
├── backup.sh           # Main script
├── check.sh            # Integrity check
├── restore.sh          # Restore wizard
├── common.sh           # Shared logic & config loader
├── .env                # Your configuration (not in Git!)
├── .gitignore          # Ignores secrets & temp files
└── hooks/
    ├── pre-backup.d/   # Scripts before backup
    └── post-backup.d/  # Scripts after backup
```
