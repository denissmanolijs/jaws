#!/usr/bin/env bash
#
# setup-unattended-upgrades.sh
# Configures unattended security updates on Ubuntu.
# Idempotent: backs up existing configs before overwriting.

set -euo pipefail

# --- Guard: must be root ---
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
APT_CONF_DIR="/etc/apt/apt.conf.d"
AUTO_UPGRADES="${APT_CONF_DIR}/20auto-upgrades"
UNATTENDED="${APT_CONF_DIR}/50unattended-upgrades"

BACKUP_DIR="/root/apt-config-backups"

backup() {
    local f="$1"
    if [[ -f "$f" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$f" "${BACKUP_DIR}/$(basename "$f").bak-${TS}"
        echo "Backed up ${f} -> ${BACKUP_DIR}/$(basename "$f").bak-${TS}"
    fi
}

echo "==> Installing unattended-upgrades..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq unattended-upgrades apt-listchanges

echo "==> Writing ${AUTO_UPGRADES}..."
backup "$AUTO_UPGRADES"
cat > "$AUTO_UPGRADES" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

echo "==> Writing ${UNATTENDED}..."
backup "$UNATTENDED"
cat > "$UNATTENDED" <<'EOF'
// Managed by setup-unattended-upgrades.sh

Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
    "${distro_id}:${distro_codename}-updates";
//  "${distro_id}:${distro_codename}-proposed";
//  "${distro_id}:${distro_codename}-backports";
};

Unattended-Upgrade::Package-Blacklist {
    "docker-ce";
    "docker-ce-cli";
    "docker-ce-rootless-extras";
    "containerd.io";
};

Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

echo "==> Enabling timers..."
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer

echo "==> Validating configuration (dry run)..."
if unattended-upgrade --dry-run --debug >/tmp/uu-dryrun.log 2>&1; then
    echo "Dry run OK. Full output: /tmp/uu-dryrun.log"
else
    echo "Dry run reported an error. Check /tmp/uu-dryrun.log" >&2
    exit 1
fi

echo "==> Done."
echo "    Config:  ${UNATTENDED}"
echo "    Timers:  systemctl list-timers apt-daily*.timer"
echo "    Logs:    /var/log/unattended-upgrades/unattended-upgrades.log"
