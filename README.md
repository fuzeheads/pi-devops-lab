# pi-devops-lab

A homelab DevOps lab built on a single **Raspberry Pi 4** that serves two roles at once:

1. **Physical Edge Kiosk** — a wall-mounted full-screen display running Chromium, autostarted via Wayfire (Wayland).
2. **Containerized Homelab Node** — Docker-managed workloads running **Pi-hole** (network DNS sinkhole) and **Nextcloud** (cloud storage).

This repo is the single source of truth for the node. It is intentionally scoped to **one Pi, two containers, one GitOps pipeline** — kept rock-solid before scaling toward Kubernetes (Rancher + Fleet).

> 📌 **Documentation discipline:** This README is updated with **every commit** that changes infrastructure, config, or process. Keeping it current is what makes this project reliable and rebuildable. If a change isn't reflected here, it isn't done.

---

## 🧭 Architecture

```
Push to main → GitHub Actions → SSH via Tailscale tunnel → Docker Compose deploy on Pi
```

### Stack

| Layer | Technology |
| --- | --- |
| **Host OS** | Raspberry Pi OS 64-bit (Desktop / Wayfire compositor) |
| **Network** | TP-Link Archer BE550 (DHCP Reservation enforced) |
| **Access Control** | Key-based SSH (`ed25519`), WayVNC, Tailscale mesh |
| **Orchestration** | Docker Compose (interim step prior to Rancher/Fleet Kubernetes migration) |
| **Services** | Pi-hole (DNS), Nextcloud (storage) |

---

## 🖥️ Infrastructure Baseline

| Property | Value / Configuration |
| --- | --- |
| **Node Hardware** | Raspberry Pi 4 |
| **Hostname** | `homelab-pi` (set via Raspberry Pi Imager) |
| **Network IP** | Fixed via TP-Link Archer BE550 DHCP Reservation |
| **Primary Admin Key** | Pop!_OS SSH public key (`~/.ssh/id_ed25519.pub`), injected via Imager |
| **Password Auth** | Disabled for SSH (public-key authentication enforced) |

---

## ✅ Deployment Status

```
[x] MicroSD flashed with customized Raspberry Pi OS 64-bit Desktop
[x] Primary SSH public key injected during image provisioning
[x] Router DHCP address reservation active and committed to NVRAM
[x] Router configuration file backed up locally (.bin)
[ ] Initial SSH verification from Pop!_OS laptop
[ ] Base system update (apt full-upgrade)
[ ] Remote management setup (WayVNC + Tailscale)
[ ] Kiosk autostart configuration (wayfire.ini)
[ ] Docker Engine installation & systemd-resolved port 53 fix
[ ] Deployment of Docker Compose stack (Pi-hole + Nextcloud)
[ ] Secondary SSH keys authorized (iPad & Android devices)
[ ] Repository initialization & GitOps pipeline tracking
```

---

## 🚀 Sequential Execution Plan

### Step 1 — Base Access & System Hardening

Connect from Pop!_OS and refresh core repositories:

```bash
ssh yourusername@RESERVED_PI_IP
sudo apt update && sudo apt full-upgrade -y
```

### Step 2 — Remote Access Configuration

Enable native Wayland VNC and join the Tailscale tailnet:

```bash
# Enable VNC
sudo raspi-config
# Interface Options -> VNC -> Enable -> Exit

# Install and authenticate Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### Step 3 — Wayfire Kiosk Display Autostart

Launch Chromium into full-screen kiosk mode on boot. Edit `~/.config/wayfire.ini` and append:

```ini
[autostart]
chromium = chromium-browser --start-maximized --start-fullscreen --kiosk --noerrdialogs --disable-infobars "YOUR_CALENDAR_URL_HERE"
screensaver = false
dpms = false
```

### Step 4 — Docker Engine & DNS Host Configuration

Install Docker and free port 53 so Pi-hole can claim native DNS:

```bash
# Install Docker Engine
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Disable systemd-resolved DNS stub listener (frees port 53)
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved
```

### Step 5 — Stack Deployment

Create `~/containers/homelab/docker-compose.yml`:

```yaml
version: '3.8'

services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8080:80/tcp"
    environment:
      TZ: 'Europe/Amsterdam'
      FTLCONF_LOCAL_IPV4: '0.0.0.0'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    restart: unless-stopped

  nextcloud:
    container_name: nextcloud
    image: lscr.io/linuxserver/nextcloud:latest
    ports:
      - "80:80"
      - "443:443"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Amsterdam
    volumes:
      - './nextcloud/config:/config'
      - './nextcloud/data:/data'
    restart: unless-stopped
```

Deploy:

```bash
cd ~/containers/homelab
docker compose up -d
```

### Step 6 — Authorize Additional Devices

Generate an `ed25519` key pair in Termius/Blink/JuiceSSH on iPad and Android, then append each public key:

```bash
nano ~/.ssh/authorized_keys
# Paste new public key on a new line, save and exit.
```

---

## 🗺️ Roadmap: From Docker Compose to Rancher + Fleet

This lab is a deliberate stepping stone toward a production-style **Rancher + Fleet** GitOps workflow (the same pattern targeted for Scaleway VMs/containers). Each stage teaches a skill needed for that work.

| Stage | Goal | Skill gained |
| --- | --- | --- |
| **1. Compose works locally** | Pi-hole + Nextcloud stable on one Pi via Docker Compose | Container fundamentals, host hardening, DNS |
| **2. Compose → Kubernetes manifests** | Convert `docker-compose.yml` to k8s manifests (via `kompose` or manual refactor), run on local `k3s` | Kubernetes objects, lightweight cluster ops |
| **3. GitOps with Fleet** | Commit manifests to Git; register the repo with **Rancher Fleet** for continuous, reconciled deployment | GitOps discipline (Git = source of truth, no manual `kubectl`) |
| **4. Scale to Scaleway** | Apply the same Rancher/Fleet pattern on Scaleway VMs/containers for the work project | Cloud cluster provisioning, multi-node fleets |

**Principle:** Do not over-scope. Keep this to one Pi, two containers, one pipeline until it is rock-solid. Add the Kubernetes/Fleet layer only when Stage 1 is genuinely stable.

---

## 🆘 What If You Get Lost Again? (Recovery Runbook)

> This project was once disrupted by a lost microSD card and a forgotten repo. This section exists so that **never kills the project again.** If you return after months, or the hardware dies, start here.

### Recovery mindset

The old recovery plan was a raw SD-card `dd` image — which is exactly what failed when the card was lost. **The new recovery model is: the repo rebuilds the node, not a disk clone.** A lost card should be a ~20-minute rebuild, not a dead project.

### Rebuild from zero

1. **Flash a fresh microSD** with Raspberry Pi OS 64-bit Desktop using Raspberry Pi Imager.
   - Set hostname to `homelab-pi`.
   - Inject your Pop!_OS SSH public key (`~/.ssh/id_ed25519.pub`).
   - Disable password authentication.
2. **Restore the network reservation** on the TP-Link Archer BE550 (restore the backed-up `.bin` config, or re-add the DHCP reservation for the Pi's MAC).
3. **Clone this repo** and follow the [Sequential Execution Plan](#-sequential-execution-plan) top to bottom.
4. **Re-authenticate Tailscale** (`sudo tailscale up`) to bring the node back onto the tailnet.
5. **Redeploy the stack** (`docker compose up -d`). Service config lives in Git; only secrets and persistent volumes are node-local.

### What must live OUTSIDE the Pi (so it survives hardware loss)

- ✅ This repo (compose files, config, this README) — in Git.
- ✅ SSH **public** keys — recorded here / in your key manager.
- ✅ Router config backup (`.bin`) — stored off-device.
- ⚠️ **Secrets** (Pi-hole/Nextcloud passwords) — in GitHub Actions Secrets or a password manager, **never** committed.
- ⚠️ **Nextcloud data volume** — needs a real backup strategy (planned: Restic/Borg to off-device storage).

### If you've simply forgotten the project

Read this README top to bottom, check the **Deployment Status** checklist for where you left off, then resume the Execution Plan at the first unchecked item.

---

## 🔁 Keeping This Document Reliable

- Update this README **in the same commit** as any infra/config/process change.
- Tick the **Deployment Status** boxes as steps complete.
- Treat undocumented changes as unfinished work.

---

## 👨‍🔬 Author

Created and maintained by Diego S. — a living lab for honing modern DevOps practices.
