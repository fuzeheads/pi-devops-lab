# pi-devops-lab

A homelab DevOps lab on a single **Raspberry Pi 4** that plays two roles at once:

1. **Living-room kiosk** — a wall-mounted HDMI display showing **DAKboard** (Google Calendar + weather + Google Keep notes), driven by native Chromium via Wayfire.
2. **Containerized homelab node** — **Pi-hole** (network-wide DNS ad-blocking) running in Docker, deployed via GitHub Actions over a Tailscale tunnel.

Scope is deliberately kept to **one Pi, one service (Pi-hole), one kiosk, one GitOps pipeline** — rock-solid before scaling to the main homelab node and Kubernetes (Rancher + Fleet).

> 📌 **Documentation discipline:** update this README **in the same commit** as any infra/config/process change. Undocumented changes count as unfinished. This is what makes the lab reliable and rebuildable.

---

## 🧭 Design principles

- **Containerize services; keep the display native.** Pi-hole (and later DAKboard's backend) are containers. The kiosk browser is native Chromium because it must reliably drive the Pi's physical HDMI on every boot — a containerized browser rendering to real HDMI on a Pi is fragile.
- **Everything version-controlled in Git**, even the native bits (`kiosk/wayfire.ini`).
- **Secrets: rotate, never recover.** GitHub secrets are write-only. If you don't know a secret's value, replace it — don't try to read it.
- **Self-healing on reboot.** A power cycle (smart plug) or nightly reboot must bring back DNS + the calendar with zero manual steps.

---

## 🏗️ Architecture

```
Push to main → GitHub Actions → Tailscale SSH → Pi:
   ├─ docker compose up  → Pi-hole (DNS, container)
   └─ render DAKBOARD_URL → ~/.config/wayfire.ini (native kiosk)

On boot: Docker → Pi-hole (DNS live) → Wayfire → Chromium → DAKboard on the wall
```

| Layer | Technology |
| --- | --- |
| Host OS | Raspberry Pi OS 64-bit (Desktop / Wayfire) |
| Network | TP-Link Archer BE550 (DHCP reservation for the Pi) |
| Access | Key-based SSH (`ed25519`), Tailscale mesh + SSH |
| Orchestration | Docker Compose (interim; → k3s / Rancher Fleet later) |
| Services | Pi-hole (DNS) |
| Display | Native Chromium kiosk → DAKboard |

---

## 📁 Repository layout

```
pi-devops-lab/
├── .github/workflows/deploy.yml   # CI/CD: deploy Pi-hole + inject kiosk URL
├── docker/pi-hole/                # Containerized Pi-hole service
│   ├── docker-compose.yml
│   └── .env.template
├── kiosk/                         # Native kiosk (Git-controlled)
│   ├── wayfire.ini                # Autostart Chromium → DAKboard (URL injected)
│   └── README.md
├── systemd/                       # Host units
│   ├── nightly-reboot.service
│   └── nightly-reboot.timer       # Optional scheduled reboot
├── scripts/pi-bootstrap.sh        # One-shot Pi provisioning (idempotent)
├── docs/migration.md              # Pi → main node → k8s migration plan
└── README.md
```

---

## 🔑 Required GitHub Actions secrets

Set under **Settings → Secrets and variables → Actions**. These are the **only** secrets the pipeline uses:

| Secret | Purpose | Notes |
| --- | --- | --- |
| `TAILSCALE_AUTHKEY` | CI runner joins your tailnet to reach the Pi | Tailscale keys **expire** — regenerate if old |
| `PIHOLE_WEBPASSWORD` | Pi-hole admin password | Store a copy in your password manager |
| `DAKBOARD_URL` | Your DAKboard display URL | Treated as a secret; never committed |

> 🧹 **Remove obsolete secrets.** Earlier `SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY` are **not used** (deploy is over Tailscale SSH). Delete them.

---

## 🚀 Reproduce this setup (Pi or a friend's homelab)

Once the SD is flashed, the whole scenario is **three actions**: run one bootstrap command on the Pi, set three secrets on GitHub, push to main. Everything else lives in Git.

Legend: **💻 LAPTOP** = your computer/browser · **🍓 PI** = terminal on the Pi (SSH).

### Phase 0 — Bootstrap (makes the pipeline reachable)

1. **🍓 PI** — join Tailscale with the tag/hostname the pipeline targets:
   ```bash
   sudo tailscale up --advertise-tags=tag:pi --ssh --hostname livingroompi
   tailscale status --self
   ```
2. **💻 LAPTOP** — Tailscale admin → **Access Controls**: ensure `tag:pi` exists with you as `tagOwner`. *(Already configured for this lab.)*
3. **💻 LAPTOP** — GitHub → Secrets → Actions: set `TAILSCALE_AUTHKEY`, `PIHOLE_WEBPASSWORD`, `DAKBOARD_URL` (see table above).
4. **🍓 PI** — run the one-shot bootstrap (port-53 fix, Docker, boot-enable, clone, kiosk config):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/fuzeheads/pi-devops-lab/main/scripts/pi-bootstrap.sh | bash
   ```

### Phase 1 — Deploy Pi-hole via the pipeline

5. **💻 LAPTOP** — push to `main` (or run the workflow manually via **Actions → Run workflow**). Watch the Actions tab.
6. **🍓 PI** — verify:
   ```bash
   docker ps | grep pihole
   curl -f http://localhost:8080/admin -s --max-time 5 && echo "Pi-hole UI OK"
   ```
7. **💻 LAPTOP** — router admin: set the Pi as the LAN DNS server; add it in Tailscale MagicDNS so devices inherit ad-blocking.

### Phase 2 — Living-room calendar (the main goal)

8. **💻 LAPTOP** — build your **DAKboard** dashboard (Google Calendar + weather + Keep), copy the **display URL**, save it as the `DAKBOARD_URL` secret, and re-run the workflow so it's injected into `wayfire.ini`.
9. **🍓 PI** — reboot and confirm the wall shows DAKboard:
   ```bash
   sudo reboot
   ```

---

## 🌐 DNS architecture (now → later)

- **Now (Pi = front line):** Pi-hole owns port 53 on the Pi (`systemd-resolved` stub listener disabled by the bootstrap — persistent across reboots). Clients get Pi-hole via **router DHCP** (whole LAN, new devices auto-inherit ad-blocking) and **Tailscale MagicDNS** (follows you off-home).
- **Later (main node = cavalry):** Pi-hole migrates to the main node. Because config lives in Git, migration is: clone repo → `docker compose up -d` → repoint DHCP + MagicDNS to the new IP. No redesign. See [`docs/migration.md`](docs/migration.md).

---

## ♻️ Reboot resilience

The Pi must return to a working state after any restart (smart-plug power cycle or the optional nightly reboot) with **no manual steps**:

1. **Docker** is enabled at boot → starts automatically.
2. **Pi-hole** has `restart: unless-stopped` → relaunches → DNS live.
3. **Port 53** fix is persistent in `/etc/systemd/resolved.conf`.
4. **Wayfire** autostarts **Chromium** → DAKboard fills the screen.

Optional nightly reboot (keeps the Pi snappy) via `systemd/nightly-reboot.timer`:
```bash
ENABLE_NIGHTLY_REBOOT=yes bash ~/pi-devops-lab/scripts/pi-bootstrap.sh
# or: sudo cp systemd/nightly-reboot.* /etc/systemd/system/ && sudo systemctl enable --now nightly-reboot.timer
```
> If your smart plug already power-cycles the Pi/monitor overnight, you may not need the timer at all.

---

## 🗺️ Roadmap: Docker Compose → Rancher + Fleet

| Stage | Goal |
| --- | --- |
| 1. Compose (now) | Pi-hole + kiosk stable on one Pi |
| 2. Split & conquer | Move Pi-hole, add **Nextcloud** + **Traefik** (80/443 reverse proxy), optionally self-host **DAKboard backend** on the main node; Pi stays the kiosk |
| 3. Compose → k8s | Convert to manifests (`kompose`), run on local **k3s** |
| 4. GitOps with Fleet | Register repo with **Rancher Fleet** for reconciled deploys |
| 5. Scaleway | Apply the same Rancher/Fleet pattern on Scaleway VMs/containers |

**Principle:** don't over-scope — keep Pi-hole + kiosk rock-solid before adding Kubernetes.

---

## 🆘 What If You Get Lost Again? (Recovery runbook)

> This project was once disrupted by a lost microSD and a forgotten repo. This section ensures that never kills it again.

**Recovery model:** the **repo rebuilds the node**, not a disk clone. A lost card is a ~20-minute rebuild.

**Rebuild from zero:**
1. Flash a fresh SD (Raspberry Pi Imager): hostname `livingroompi`, inject your SSH public key, disable password auth.
2. Restore the router DHCP reservation for the Pi (or re-add by MAC).
3. **🍓 PI:** run the bootstrap one-liner (Phase 0, step 4).
4. **🍓 PI:** `sudo tailscale up --advertise-tags=tag:pi --ssh --hostname livingroompi`.
5. **💻 LAPTOP:** confirm the three secrets exist (rotate `TAILSCALE_AUTHKEY` if expired), push to `main`.

**What must live OUTSIDE the Pi (survives hardware loss):**
- ✅ This repo (compose, kiosk config, docs) — in Git.
- ✅ SSH **public** keys + router config backup — off-device.
- ⚠️ Secrets (`PIHOLE_WEBPASSWORD`, `DAKBOARD_URL`, `TAILSCALE_AUTHKEY`) — password manager / GitHub Secrets, **never** committed.

**If you simply forgot the project:** read this README top to bottom, then resume at the first unfinished phase above.

---

## 👨‍🔬 Author

Created and maintained by Diego S. — a living lab for honing modern DevOps practices.
