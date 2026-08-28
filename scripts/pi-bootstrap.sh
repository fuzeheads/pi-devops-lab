#!/usr/bin/env bash
#
# pi-bootstrap.sh — one-shot provisioning for the pi-devops-lab node.
#
# WHAT IT DOES (idempotent — safe to re-run):
#   1. Ensures port 53 is free for Pi-hole. On OS images that use systemd-resolved
#      it disables the stub listener; on Raspberry Pi OS (which typically does NOT
#      use systemd-resolved) it just verifies 53 is free and moves on.
#   2. Installs Docker Engine and enables it at boot.
#   3. Adds the current user to the docker group.
#   4. Clones (or updates) this repo to ~/pi-devops-lab.
#   5. Installs the native kiosk (Chromium via labwc autostart) that boots into DAKboard,
#      and configures LightDM autologin so the kiosk starts unattended on every boot.
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
# 1. Ensure port 53 is free for Pi-hole
#    Different OS images handle DNS differently:
#      - Ubuntu / some images use systemd-resolved (holds port 53) -> disable stub.
#      - Raspberry Pi OS typically does NOT use systemd-resolved    -> nothing to do.
#    This step must never abort the whole run.
# ---------------------------------------------------------------------------
log "Ensuring port 53 is free for Pi-hole"
if systemctl is-active --quiet systemd-resolved 2>/dev/null || [ -f /etc/systemd/resolved.conf ]; then
  log "systemd-resolved detected -> disabling DNS stub listener"
  if [ -f /etc/systemd/resolved.conf ] && grep -q '^#\?DNSStubListener=' /etc/systemd/resolved.conf; then
    sudo sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
  else
    echo 'DNSStubListener=no' | sudo tee -a /etc/systemd/resolved.conf >/dev/null
  fi
  sudo systemctl restart systemd-resolved || true
else
  log "systemd-resolved not in use on this OS -> no stub-listener fix needed"
fi

# Sanity check: is anything already bound to port 53?
if sudo ss -tulnp 2>/dev/null | grep -q ':53 '; then
  log "WARNING: something is already listening on port 53 — investigate before Pi-hole starts:"
  sudo ss -tulnp | grep ':53 ' || true
else
  log "Port 53 is free for Pi-hole ✅"
fi

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
# 4. Install the native kiosk (Chromium via labwc autostart)
#
#    Raspberry Pi OS / Debian 13 (trixie) ships:
#      - labwc  : the wlroots Wayland compositor we use for the kiosk
#      - chromium : the browser binary is 'chromium' (NOT 'chromium-browser')
#      - LightDM  : the display manager we configure for autologin
#    We install labwc + a background painter, drop the labwc autostart script
#    (which launches Chromium in --kiosk with --password-store=basic to avoid the
#    GNOME Keyring popup), and configure LightDM to autologin into the labwc session.
# ---------------------------------------------------------------------------
log "Installing kiosk packages (labwc, swaybg, chromium, wlr-randr)"
sudo apt-get update -y
sudo apt-get install -y labwc swaybg chromium wlr-randr

log "Installing labwc autostart (Chromium kiosk -> DAKboard)"
mkdir -p "${HOME}/.config/labwc"
cp "${REPO_DIR}/kiosk/labwc-autostart" "${HOME}/.config/labwc/autostart"
chmod +x "${HOME}/.config/labwc/autostart"

# Render DAKBOARD_URL into the kiosk autostart if provided in the environment.
if [ -n "${DAKBOARD_URL:-}" ]; then
  log "Injecting DAKBOARD_URL into labwc autostart"
  sed -i "s|__DAKBOARD_URL__|${DAKBOARD_URL}|g" "${HOME}/.config/labwc/autostart"
else
  log "DAKBOARD_URL not set — leaving placeholder. The pipeline will inject it on deploy,"
  log "or edit ~/.config/labwc/autostart and replace __DAKBOARD_URL__ manually."
fi

log "Configuring LightDM autologin into the labwc session (user: admin)"
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo cp "${REPO_DIR}/kiosk/lightdm-autologin.conf" /etc/lightdm/lightdm.conf.d/50-kiosk-autologin.conf
# Ensure the autologin user is in the 'autologin' group (required by LightDM).
sudo groupadd -f autologin
sudo usermod -aG autologin admin
# Make sure the Pi boots to the graphical target so LightDM starts.
sudo systemctl set-default graphical.target

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
echo "After a reboot the Pi should: start Docker -> Pi-hole (DNS) -> LightDM autologin"
echo "-> labwc -> Chromium (kiosk) -> DAKboard."
