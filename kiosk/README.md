# Kiosk (living-room display)

This directory holds the **native** kiosk configuration for the Raspberry Pi that
drives the wall-mounted living-room monitor.

## Design decision: native browser, containerized services

| Concern | Choice | Why |
| --- | --- | --- |
| **Display / browser** | **Native** Chromium via **labwc autostart** | The browser must drive the Pi's real HDMI output. A containerized browser rendering to physical HDMI on a Pi (Wayland/GPU passthrough) is fragile and unreliable on boot. |
| **Session boot** | **LightDM autologin** (`admin` → `labwc`) | Reliable unattended boot path into the kiosk session. |
| **Services (Pi-hole, future backend services)** | **Containerized** | Portable, Git-defined, easy to migrate to other homelab nodes later. |

> Project rule: *containerize what can be containerized; keep native only what has
> to be — but always version-controlled in Git.* The browser is the one thing
> that is genuinely better native. Everything it points at is a container.

## What it points at

The kiosk shows **DAKboard** (Google Calendar + weather + Google Keep notes).
Today DAKboard's backend runs in DAKboard's cloud and the kiosk simply opens your
**DAKboard display URL**. Later (see `docs/migration.md`) we may self-host a
backend/dashboard service on another homelab host — the kiosk keeps working, it
just points at a new URL.

## The DAKboard URL is a secret

`labwc-autostart` ships with a `__DAKBOARD_URL__` placeholder. The real URL is
stored as the `DAKBOARD_URL` GitHub Actions secret and injected at deploy time
(or by `scripts/pi-bootstrap.sh` if `DAKBOARD_URL` is exported). It is **never** committed.

## Chromium launch flags

`kiosk/labwc-autostart` launches `chromium` (Debian 13/trixie binary name) with:

- `--kiosk` — fullscreen unattended kiosk mode.
- `--password-store=basic` — avoids GNOME Keyring popup prompts.
- `--ozone-platform=wayland` — native Wayland path for labwc.

## Boot behaviour (survives nightly reboot)

On every (graphical) boot:

1. Docker starts (enabled at boot) → Pi-hole container relaunches (`restart: unless-stopped`) → DNS is live.
2. LightDM autologins user `admin` into the `labwc` session.
3. labwc runs `~/.config/labwc/autostart` → launches Chromium in kiosk mode → DAKboard fills the screen.

No cron, no manual step, independent of the smart-plug schedule. Powering the
monitor on (via the smart plug) and the Pi booting is all that's required.
