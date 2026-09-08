# Migration Plan: Raspberry Pi → Main Homelab Node → Kubernetes (Rancher + Fleet)

This document describes how the single-Pi setup evolves as the homelab grows. It
is the "split and conquer" plan: the Pi is the **front-line soldier** handling
everything today; when the **main node (cavalry)** is ready, responsibilities
split cleanly.

## Current state (Pi = everything)

| Role | Runs on | How |
| --- | --- | --- |
| DNS ad-blocking (Pi-hole) | Pi | Container, deployed via GitHub Actions |
| Living-room kiosk (DAKboard) | Pi | LightDM autologin (`admin`) → labwc → native Chromium, HDMI |
| DAKboard backend | DAKboard cloud | External (not yet self-hosted) |

## Phase status (Phase 1: one Pi, rock-solid)

Phase 1 must be *verified*, not just *built*, before adding the homelab node or k3s.

| Item | Status |
| --- | --- |
| Kiosk boot chain (LightDM → labwc → chromium → DAKboard) | ✅ Live and stable |
| Pi-hole container serving LAN DNS on :53 | ✅ Live |
| GitOps deploy over Tailscale SSH | ✅ Working |
| Nightly reboot timer (04:30) | ✅ Enabled on the live Pi |
| Docs match deployed reality | ✅ Realigned to labwc/LightDM |
| Pi-hole v6 admin password wired correctly | ✅ Fixed (`FTLCONF_webserver_api_password`) |
| Container health signal trustworthy | ✅ Fixed (inherit image DNS healthcheck) |
| Tailscale MagicDNS resolves `livingroompi` from laptop | ⚠️ Open — laptop has `accept-dns=false` |
| Fresh-microSD reproducibility test | ⏳ Pending spare hardware |

### Version-drift lesson (carry this forward)

Pi-hole v5 → v6 renamed the password variable (`WEBPASSWORD` →
`FTLCONF_webserver_api_password`) and replaced the HTTP healthcheck with a
DNS-native one. Both drifted silently: the password was never applied and the
container reported `unhealthy` for ~29,000 consecutive checks while working fine.

**Rule:** when a container image crosses a major version, re-read its env-var and
healthcheck contract before assuming the compose file still applies. Prefer the
image's built-in healthcheck over a hand-written one — it is maintained upstream
and tests the service's actual job. This matters more under k3s, where liveness
and readiness probes act on that signal instead of just printing a status string.

## Documentation discipline for painless migration

For migrations to stay low-risk, keep this separation strict:

- **Git-tracked state (portable):** compose files, bootstrap scripts, kiosk templates, systemd units, docs.
- **Runtime host state (not in Git):** container bind mounts/volumes (`docker/pi-hole/etc-pihole/`, `docker/pi-hole/etc-dnsmasq.d/`), system packages, host networking.
- **Secrets (never in Git):** `.env` values, GitHub Actions secrets (`PIHOLE_WEBPASSWORD`, `DAKBOARD_URL`, `TAILSCALE_AUTHKEY`).

If an infra/config/process change is made, update docs in the same commit.

## DNS architecture: now → later

- **Now:** Pi-hole owns port 53 on the Pi (systemd-resolved stub listener disabled).
  Clients get Pi-hole as DNS via **router DHCP** (whole LAN, new devices inherit
  ad-blocking automatically) **and** via **Tailscale MagicDNS** (follows you off-home).
- **Later:** Pi-hole migrates to another host. Because config is Git-defined,
  migration is: clone repo on the new host, set env, `docker compose up -d`, then
  repoint router DHCP + MagicDNS at the new IP. **No redesign — just a target swap.**

## Target state (split & conquer)

| Role | Moves to | Notes |
| --- | --- | --- |
| Pi-hole (DNS) | **Main node** | More reliable, always-on host |
| Nextcloud (storage) | **Main node** | Born on its final host to avoid moving stateful data twice; needs Restic/Borg backups |
| Traefik (reverse proxy) | **Main node** | Owns 80/443, routes by hostname — resolves web-port contention when multiple web apps exist |
| Backend dashboards/services | **Main node** | Pi kiosk can repoint by changing only `DAKBOARD_URL` secret |
| Kiosk (Chromium) | **Stays on the Pi** | The Pi has the HDMI cable to the living-room monitor |

## Pi-hole host migration checklist (actionable)

1. On target host, install Docker + Docker Compose plugin.
2. Clone this repo:
   ```bash
   git clone https://github.com/fuzeheads/pi-devops-lab.git
   cd pi-devops-lab/docker/pi-hole
   ```
3. Create `.env` from template and fill values:
   ```bash
   cp .env.template .env
   ```
4. Start Pi-hole:
   ```bash
   docker compose pull
   docker compose up -d
   ```
5. Validate locally on new host:
   ```bash
   docker ps --format '{{.Names}}\t{{.Status}}' | grep pihole   # expect "healthy"
   docker exec pihole dig +short +norecurse +retry=0 @127.0.0.1 pi.hole
   curl -f -s -o /dev/null --max-time 5 http://localhost:8080/admin/ && echo "Pi-hole UI OK"
   ```
   The DNS query is the authoritative check — the UI responding does not prove
   resolution works.
6. Repoint router DHCP DNS and Tailscale MagicDNS to the new host IP.
7. Monitor clients and logs; once stable, retire old Pi-hole instance.

## Display/server split checklist (Pi stays display-only)

- Keep the Pi attached to HDMI and running only the kiosk session.
- Move server-side containers (Pi-hole now, Nextcloud later) to homelab machines.
- If backend URL changes, only update the `DAKBOARD_URL` GitHub Actions secret and redeploy.
- Pipeline injects the URL into `~/.config/labwc/autostart`; no manual Pi edits required.

## Fresh microSD reproducibility test (pending hardware)

**TODO (pending spare hardware):** run a full fresh-microSD validation and capture results here:

- Flash new card, run bootstrap, verify LightDM autologin → labwc → Chromium kiosk.
- Run deploy workflow and verify Pi-hole + kiosk URL injection.
- Confirm nightly reboot timer and post-reboot service recovery.
- Record elapsed time, issues found, and any doc updates needed.

## Kubernetes roadmap (Rancher + Fleet)

Mirrors the eventual work project on Scaleway VMs/containers:

1. **Compose → manifests:** convert `docker-compose.yml` to Kubernetes manifests
   (via `kompose` or manual refactor); run on a local **k3s** cluster.
2. **GitOps with Fleet:** commit manifests to Git; register the repo with
   **Rancher Fleet** for continuous, reconciled deployment (Git = source of truth,
   no manual `kubectl`).
3. **Scale to Scaleway:** apply the same Rancher/Fleet pattern to Scaleway
   VMs/containers for the work project.

**Principle:** don't over-scope. Keep one Pi + Pi-hole + kiosk rock-solid before
adding the Kubernetes/Fleet layer.
