#!/usr/bin/env bash
#
# pi-bootstrap.sh — one-shot provisioning for the pi-devops-lab node.
#
# WHAT IT DOES (idempotent — safe to re-run):
#   1. Frees port 53 (disables systemd-resolved stub listener) so Pi-hole can bind DNS.
#   2. Installs Docker Engine and enables it at boot.
#   3. Adds the current user to the docker group.
#   4. Clones (or updates) this repo to ~/pi-devops-lab.
#   5. Installs the native kiosk (Chromium via Wayfire) that boots into DAKboard.
#   6. Optionally installs the nightly-reboot systemd timer.
#
# RUN THIS ON THE PI (over SSH), NOT on your laptop:
#   curl -fsSL https://raw.githubusercontent.com/fuzeheads/pi-devops-lab/main/scripts/pi-bootstrap.sh | bash
#
# Re-run any time to bring a rebuilt/replaced Pi back to a known-good state.

set -euo pipefail

REPO_URL="https://github.com/fuzeheads/pi-devops-lab.git"
REPO_DIR="${HOME}/pi-devops-lab"
ENABLE_NIGHTLY_REBOOT="${ENABLE_NIGHTLY_REBOOT:-no}"   # set to "yes" to install the timer

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Free port 53 for Pi-hole (persistent across reboots)
# ---------------------------------------------------------------------------
log "Freeing port 53 (systemd-resolved stub listener off)"
if grep -q '^#\?DNSStubListener=' /etc/systemd/resolved.conf; then
  sudo sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
else
  echo 'DNSStubListener=no' | sudo tee -a /etc/systemd/resolved.conf >/dev/null
fi
sudo systemctl restart systemd-resolved

# ---------------------------------------------------------------------------
# 2. Install Docker Engine + enable at boot
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine"
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
else
  log "Docker already installed — skipping"
fi

log "Enabling Docker at boot (survives nightly reboot)"
sudo systemctl enable --now docker

if ! id -nG "$USER" | grep -qw docker; then
  log "Adding $USER to docker group (re-login or reboot to take effect)"
  sudo usermod -aG docker "$USER"
fi

# ---------------------------------------------------------------------------
# 3. Clone or update the repo
# ---------------------------------------------------------------------------
if [ -d "${REPO_DIR}/.git" ]; then
  log "Updating existing repo at ${REPO_DIR}"
  git -C "${REPO_DIR}" pull --ff-only
else
  log "Cloning repo to ${REPO_DIR}"
  git clone "${REPO_URL}" "${REPO_DIR}"
fi

# ---------------------------------------------------------------------------
# 4. Install the native kiosk (Chromium via Wayfire autostart)
# ---------------------------------------------------------------------------
log "Installing native kiosk config (wayfire.ini)"
mkdir -p "${HOME}/.config"
cp "${REPO_DIR}/kiosk/wayfire.ini" "${HOME}/.config/wayfire.ini"

# Render DAKBOARD_URL into the kiosk config if provided in the environment.
if [ -n "${DAKBOARD_URL:-}" ]; then
  log "Injecting DAKBOARD_URL into wayfire.ini"
  sed -i "s|__DAKBOARD_URL__|${DAKBOARD_URL}|g" "${HOME}/.config/wayfire.ini"
else
  log "DAKBOARD_URL not set — leaving placeholder. The pipeline will inject it on deploy,"
  log "or edit ~/.config/wayfire.ini and replace __DAKBOARD_URL__ manually."
fi

# ---------------------------------------------------------------------------
# 5. Optional: nightly reboot timer (keeps the Pi snappy)
# ---------------------------------------------------------------------------
if [ "${ENABLE_NIGHTLY_REBOOT}" = "yes" ]; then
  log "Installing nightly-reboot systemd timer"
  sudo cp "${REPO_DIR}/systemd/nightly-reboot.service" /etc/systemd/system/
  sudo cp "${REPO_DIR}/systemd/nightly-reboot.timer" /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now nightly-reboot.timer
else
  log "Skipping nightly reboot timer (set ENABLE_NIGHTLY_REBOOT=yes to install)"
fi

log "Bootstrap complete."
echo
echo "Next: push to main (or re-run the GitHub Actions pipeline) to deploy Pi-hole."
echo "After a reboot the Pi should: start Docker -> Pi-hole (DNS) -> Wayfire -> Chromium -> DAKboard."
