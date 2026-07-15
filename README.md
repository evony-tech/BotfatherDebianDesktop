# BotfatherDebianDesktop

A fully automated, self-provisioning deployment script that transforms a fresh Debian 13 VPS into a secure, high-density, headless desktop appliance for running **The NEAT Botfather** and NEAT bots.

## Overview
Running high-density bot instances (100+) requires extreme resource efficiency and ironclad security. This repository provides a master script that eliminates the overhead and licensing costs of Windows Server. It builds a highly optimized Linux foundation (Debian + XFCE + Wine) and automatically locks the entire server behind a private mesh VPN.

### 🚀 Installation Options

This script is designed for fresh **Debian 13 (Trixie)** installations and can be run completely unattended. 

#### Option 1: Automated Cloud Deployment (Hetzner, DigitalOcean, etc.)
When creating your server, look for the **Cloud-Init** or **User Data** text box in your provider's dashboard. Simply paste the raw contents of `setup-desktop.sh` directly into that box. 
* The server will automatically install everything during its first boot.
* Once the server is online, SSH in as `root` and type `cat /root/botfarm_setup_instructions.txt` to retrieve your auto-generated password and Tailscale configuration.

#### Option 2: One-Line SSH Installer
If you already have a server running, log in as `root` via SSH and paste the following command. 

```bash
wget -qO- https://raw.githubusercontent.com/evony-tech/BotfatherDebianDesktop/main/setup-desktop.sh | bash
```
---

## 🔍 What Exactly Does This Script Do?

To ensure complete transparency, here is the exact sequence of actions this script performs on your server:

### 1. Core Desktop & Utilities
* **Installs XFCE4:** A highly lightweight graphical desktop environment that consumes minimal RAM, ensuring maximum memory is reserved for bot instances.
* **Installs Firefox ESR:** A native, secure Linux browser for general web use.

### 2. High-Security Networking (The "Iron Curtain")
* **Installs Headscale & Tailscale:** Creates a self-hosted, private mesh VPN. 
* **Configures UFW (Uncomplicated Firewall):** Completely blocks the public internet from accessing your server.
* **Locks SSH & RDP:** Port `22` (SSH) and Port `3389` (RDP) are forcefully restricted. They can *only* be accessed if you are connected to the secure Tailscale VPN tunnel (or explicitly whitelisted your home IP).

### 3. The Wine Environment & Split-Routing
* **Installs Wine Multi-Arch (64/32-bit):** Sets up the Windows translation layer so Botfather can run natively without an actual Windows OS.
* **Injects Custom Registry Rules (Split-Routing):** * `HTTP` links clicked inside the bots are securely trapped inside Wine and routed to **NeatFlashBrowser**.
  * `HTTPS` links escape the Wine environment and open natively in **Firefox ESR** for perfect SSL handling without emulation overhead.

### 4. Application Provisioning
* Automatically downloads and installs **The NEAT Botfather**.
* Automatically downloads and installs **NeatFlashBrowser**.
* Sets a custom medieval wallpaper and generates foolproof, clickable desktop shortcuts for all applications.

### 5. "Appliance Mode" Auto-Boot
* Configures **LightDM** to automatically log into your user account the moment the server turns on.
* Adds Botfather to the XFCE autostart sequence so your farm spins up automatically after a reboot.
* Configures **x11vnc** and **XRDP** for "Live Mirroring," meaning when you RDP into the server, you instantly hook into the active, running desktop instead of spawning a new session.

---

## 💻 How to Connect After Installation

Once the script finishes, it will output a custom, single-use connection command. 

1. Install Tailscale on your Home PC ([tailscale.com/download](https://tailscale.com/download)).
2. Open Windows Command Prompt (`cmd.exe`) and paste the exact `tailscale up` command provided by the script output.
3. Open Windows **Remote Desktop Connection** (`mstsc.exe`).
4. Enter your server's private VPN IP (e.g., `100.64.x.x`).
5. Select **Mirror VirtualBox Screen** from the login dropdown and enter your password.

## Requirements
* A fresh, unmodified VPS running **Debian 13**.
* Root access to execute the provisioning script.

## Auto-Healing (Idempotency)
If your installation gets interrupted, or you accidentally break a configuration, simply run the installation command again. The script is designed to safely overwrite broken files, fix dependencies, and return the environment to a perfectly green state without deleting your application data.
