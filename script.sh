#!/usr/bin/env bash

set -euo pipefail

# Required commands for this script
REQUIRED_CMDS=(
    find
    sha256sum
    awk
    printf
    sort
    git
    rm
    mkdir
)

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command '$cmd' is not installed or not in PATH."
        exit 1
    fi
done

PULL_LOCATION="/tmp"

TIMER_SCAN="$PULL_LOCATION/stay-out"

OUT_DIR="$TIMER_SCAN/current-hashes"

GITHUB_REPO="https://github.com/BobAl853/stay-out.git"

BASELINE_DIR="$TIMER_SCAN/hashes"


UNIT_DIRS=(
    /etc/systemd/system
    /usr/lib/systemd/system
    /lib/systemd/system
    /usr/local/lib/systemd/system
    /run/systemd/system
)

CRON_DIRS=(
    /etc/crontab
    /etc/cron.hourly
    /etc/cron.daily
    /etc/cron.weekly
    /etc/cron.monthly
    /etc/cron.d
    /var/spool/cron
    /var/spool/cron/crontabs
    /etc/anacrontab
)

hash_units() {
    local out_file="$1"
    : > "$out_file"

    for dir in "${UNIT_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -type f \( -name "*.timer" -o -name "*.service" \) \
                -exec sh -c 'for f; do
                    hash=$(sha256sum "$f" | awk "{print \$1}")
                    printf "%s\t\t\t%s\n" "$f" "$hash"
                done' _ {} + >> "$out_file"
        fi
    done

    # Hash cron paths
    for path in "${CRON_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            # Single file
            hash=$(sha256sum "$path" | awk '{print $1}')
            printf "%s\t%s\n" "$path" "$hash" >> "$out_file"
        elif [[ -d "$path" ]]; then
            # Directory of cron jobs
            find "$path" -type f -exec sh -c '
                for f; do
                    hash=$(sha256sum "$f" | awk "{print \$1}")
                    printf "%s\t%s\n" "$f" "$hash"
                done
            ' _ {} + >> "$out_file"
        fi
    done

    sort -o "$out_file" "$out_file"
}

echo "Building snapshot"

mkdir -p "$BASELINE_DIR"
mkdir -p "$OUT_DIR"

# Build current snapshot
hash_units "$OUT_DIR/units.sha256"

# If no baseline exists close
if [[ ! -f "$BASELINE_DIR/units.sha256" ]]; then
        echo "NO BASLINE FOUND"
    exit 1
fi

echo "Comparing current systemd unit state to baseline..."

# Compare baseline vs current
diff_output=$(diff -u "$BASELINE_DIR/units.sha256" "$OUT_DIR/units.sha256" || true)

if [[ -z "$diff_output" ]]; then
    echo "No changes detected in systemd timer or service units."
else
    echo "CHANGES DETECTED:"
    if [! -d "/var/log/stay-out/"]; then
        mkdir "/var/log/stay-out/"
    fi
    echo "$diff_output" >> "/var/log/stay-out/diff_output.log"
    logger -p user.alert "Hashing mismatch: Files in one or more persistance areas have been modified. More info found at \"/var/log/stay-out/diff_output.log\""
    echo "$diff_output"
fi

echo "Cleaning up"
 rm -rf "$TIMER_SCAN"
