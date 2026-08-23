# Migration Plan: Raspberry Pi → Main Homelab Node → Kubernetes (Rancher + Fleet)

This document describes how the single-Pi setup evolves as the homelab grows. It
is the "split and conquer" plan: the Pi is the **front-line soldier** handling
everything today; when the **main node (cavalry)** is ready, responsibilities
split cleanly.

## Current state (Pi = everything)

| Role | Runs on | How |
| --- | --- | --- |
| DNS ad-blocking (Pi-hole) | Pi | Container, deployed via GitHub Actions |
| Living-room kiosk (DAKboard) | Pi | Native Chromium via Wayfire, HDMI |
| DAKboard backend | DAKboard cloud | External (not yet self-hosted) |

## DNS architecture: now → later

- **Now:** Pi-hole owns port 53 on the Pi (systemd-resolved stub listener disabled).
  Clients get Pi-hole as DNS via **router DHCP** (whole LAN, new devices inherit
  ad-blocking automatically) **and** via **Tailscale MagicDNS** (follows you off-home).
- **Later:** Pi-hole migrates to the main node. Because its config lives in Git
  (`etc-pihole` volume + compose), migration is: clone repo on the new node,
  `docker compose up -d`, then repoint router DHCP + MagicDNS at the new IP.
  **No redesign — just a target swap.**

## Target state (split & conquer)

| Role | Moves to | Notes |
| --- | --- | --- |
| Pi-hole (DNS) | **Main node** | More reliable, always-on host |
| Nextcloud (storage) | **Main node** | Born on its final host to avoid moving stateful data twice; needs Restic/Borg backups |
| Traefik (reverse proxy) | **Main node** | Owns 80/443, routes by hostname — resolves web-port contention when multiple web apps exist |
| DAKboard backend (optional) | **Main node** | Self-hosted in a container; kiosk just repoints to the new URL |
| Kiosk (Chromium) | **Stays on the Pi** | The Pi has the HDMI cable to the living-room monitor |

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
