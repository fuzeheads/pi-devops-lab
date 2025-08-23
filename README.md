# pi-devops-lab

A homelab setup built on Raspberry Pi and modern DevOps tooling. This repo serves as a playground for testing deployment strategies, automation, and infrastructure-as-code — all within a compact and low-cost environment.

## 📦 Project Structure

```
pi-devops-lab/
├── .github/
│   └── workflows/          # GitHub Actions workflows
│       └── deploy.yml
├── casaos/                 # CasaOS setup files
│   ├── installed-notes.md     # Notes on installed CasaOS apps or configs (currently empty)
│   └── setup.sh               # CasaOS installation script
├── docker/                 # Docker configs for Pi-hole etc.
│   └── pi-hole/
│       ├── .env
│       └── docker-compose.yml
├── docs/                   # Technical documentation and setup guides
│   └── migration.md
├── provisioning/           # Legacy provisioning scripts
├── stacks/                 # Hybrid deployment guides (e.g. CasaOS + Pi-hole)
├── .gitignore              # Git exclusions
└── README.md               # Project overview
```

## 🚀 Technologies

- Docker & Docker Compose  
- CasaOS for app management  
- CI/CD pipelines via GitHub Actions

## 🧰 Goals

- Simulate real-world deployment flows on local hardware  
- Maintain a modular, scalable, and testable lab setup  
- Learn and apply DevOps principles  
- Automate deployments with security and reproducibility in mind

## 🌱 Getting Started

1. Clone the repo:
    ```bash
    git clone https://github.com/fuzeheads/pi-devops-lab.git
    ```
2. Explore `docs/`, `docker/`, and `stacks/` to configure services.  
3. Trigger automated Pi-hole deployment via GitHub Actions when pushing to `main`.

## 🏡 Hybrid Deployments

This lab uses both **CasaOS** and **Pi-hole** on a Raspberry Pi to manage self-hosted apps and network-wide ad blocking.

- CasaOS stack runs separately and manages UI-based apps.  
- Pi-hole is deployed via GitHub Actions with secrets for secure configuration.  
- `.env` is kept minimal and updated remotely for best practices.

## 💾 Raspberry Pi Backup and Restore (Optional)

### 📦 Create Backup

```bash
ssh <user>@<pi-ip> "sudo dd if=/dev/mmcblk0 bs=4M status=progress" | dd of=raspi.img bs=4M status=progress
gzip raspi.img
```

### 🔁 Restore Backup

```bash
gzip -dc raspi.img.gz | sudo dd of=/dev/sdX bs=4M status=progress
```

Use `lsblk` to verify your SD card target. Be extremely cautious.

## 🔐 .env Simplification

Replace any hardcoded password with GitHub secrets injection.

Your final `.env`:

```env
TZ=Europe/Amsterdam
PIHOLE_IMAGE=pihole/pihole:latest
PLATFORM=linux/arm64
```

No need to include `WEBPASSWORD`, as it's securely injected via `${{ secrets.PIHOLE_WEBPASSWORD }}`.

## 👨‍🔬 Author

Created and maintained by Diego S.  
This is a living lab of modern DevOps experimentation.

##########

# pi-devops-lab

A hybrid homelab setup for Raspberry Pi, Mac Mini, and legacy hardware—powered by GitOps, Docker, Tailscale, and CasaOS. This repo demonstrates scalable, modular DevOps practices for home self-hosting.

## 📁 Project Structure

```text
pi-devops-lab/
├── .github/                 # GitHub Actions workflows
│   └── workflows/
│       └── deploy.yml       # CI/CD pipeline for Pi-hole, Nextcloud, etc.
├── docker/                  # Docker Compose stacks
│   └── pi-hole/
│       ├── docker-compose.yml
│       └── .env.template     # Template for environment variables
├── stacks/                  # Git-managed application stacks
│   ├── pihole/              # Pi-hole stack
│   └── nextcloud/           # Nextcloud stack
├── docs/                    # Technical documentation and guides
├── infra/                   # Terraform scripts & provisioning
├── k8s/                     # Kubernetes manifests (future)
├── .gitignore               # Files to exclude from Git
└── README.md                # Project overview
```

## 🚀 Technologies

- Docker & Docker Compose  
- GitHub Actions (CI/CD with encrypted secrets)  
- Tailscale (zero-config secure networking)  
- CasaOS (app management UI companion)  
- Pi-hole (network-wide ad blocking)  
- Nextcloud (shared calendar & file sync)  
- Grafana & Prometheus (monitoring & metrics)  
- Terraform (infra provisioning – planned)

## 🎯 Goals

- Automate service deployments using GitOps  
- Secure remote access and DNS with Tailscale  
- Maintain portable, reproducible stacks per host  
- Use CasaOS for day-to-day app operations  
- Scale across Raspberry Pi, Mac Mini, and Sony Vaio  
- Build core DevOps skills in a homelab context

## 🌱 Getting Started

1. Clone the repo:  
   ```bash
   git clone https://github.com/fuzeheads/pi-devops-lab.git
   cd pi-devops-lab
   ```

2. Review stack definitions in `stacks/` and `.env.template` files.

3. Configure GitHub Actions secrets under **Settings → Secrets → Actions**:  
   - `SSH_HOST`  
   - `SSH_USER`  
   - `SSH_PRIVATE_KEY`  
   - `PIHOLE_WEBPASSWORD`  
   - (Later: `NEXTCLOUD_ADMIN_PASSWORD`, `DB_ROOT_PASSWORD`, etc.)

4. Push to `main` to trigger deployment via  
   `.github/workflows/deploy.yml`.

## 🔄 Hybrid Deployment Workflow

1. **GitHub Actions**  
   - CI/CD defined in `.github/workflows/deploy.yml`.  
   - On push to `main`, SSH into target, generate `.env` from secrets, run  
     `docker-compose up -d`.

2. **Tailscale Networking**  
   - Install on each host:  
     ```bash
     curl -fsSL https://tailscale.com/install.sh | sh
     sudo tailscale up
     ```  
   - Note each host’s Tailscale IP (`100.x.x.x`).  
   - In Tailscale Admin → DNS, add Pi-hole’s IP and enable Override Local DNS.

3. **CasaOS Companion**  
   - Install on each host for UI-driven management:  
     ```bash
     curl -sSL https://get.casaos.io | bash
     ```  
   - Access at `http://<tailscale-ip>:12181`.

4. **Scale & Migrate**  
   - Treat Raspberry Pi as staging.  
   - When Mac Mini is ready, update `SSH_HOST` secret to its Tailscale IP and re-run the workflow.  
   - Repeat for Sony Vaio or additional devices.

## 🛡️ Pi-hole Setup (Tailscale DNS)

To use Pi-hole without touching your router:

1. Install Tailscale on the Pi and authenticate.  
2. Retrieve the Pi’s Tailscale IP, e.g. `100.101.102.103`.  
3. In [Tailscale Admin → DNS](https://login.tailscale.com/admin/dns):  
   - Add `100.101.102.103` as a DNS server.  
   - Enable “Override local DNS” (MagicDNS).

## 📅 Nextcloud Stack

Located in `stacks/nextcloud/`.  
- Contains `docker-compose.yml` defining Nextcloud, MariaDB, Redis.  
- Use GitHub secrets for credentials and generate `.env` at deploy time.

## 💾 Backup & Restore

### Backup Raspberry Pi SD Card

```bash
ssh pi@<lan-ip> "sudo dd if=/dev/mmcblk0 bs=4M status=progress" \
  | dd of=raspi.img bs=4M status=progress
gzip raspi.img
```

### Restore SD Card Image

```bash
gzip -dc raspi.img.gz | sudo dd of=/dev/sdX bs=4M status=progress
```

Use `lsblk` to identify the correct device.

## 🔮 Future Enhancements

- Grafana dashboards for home-lab metrics  
- k3s Kubernetes cluster across hosts  
- Automated backups with Restic/Borg  
- Home Assistant integration for smart home control  

## 👨‍🔬 Author

Created and maintained by Diego S.  
This is a living lab for honing modern DevOps practices.
```

---

Next up: let’s troubleshoot Pi-hole over Tailscale. On your Pi, run:

```bash
docker ps | grep pihole
tailscale ip -4
curl http://localhost:8080/admin -s --max-time 5
sudo netstat -tuln | grep 8080
```

Share the outputs and we’ll pinpoint why the admin UI isn’t reachable via the Tailscale IP.