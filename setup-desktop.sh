#!/bin/bash
# =====================================================================
# MASTER NEATBOT FARM PROVISIONING & AUTO-HEAL SCRIPT (DEBIAN 11/12/13)
# =====================================================================

set -e
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: This script must be run as root."
  exit 1
fi

clear
echo "========================================================="
echo "  Deploying Hardened XFCE + Auto-Login + Wine Bot Farm   "
echo "========================================================="

# 1. Gather Configuration Details Upfront with Safety Loops
PUBLIC_IP=$(curl -4 -s https://ifconfig.me || curl -4 -s icanhazip.com || echo "127.0.0.1")
echo "[+] Detected Public IP: $PUBLIC_IP"
read -p "Press ENTER to confirm, or type the correct public IP manually: " USER_IP
if [ ! -z "$USER_IP" ]; then PUBLIC_IP=$USER_IP; fi

# Prompt for custom username
while true; do
  read -p "Enter the default user account name for the bot farm (e.g., botfarmer): " FARM_USER
  if [[ -z "$FARM_USER" || "$FARM_USER" == "root" ]]; then
    echo "[-] Error: Username cannot be blank or 'root'."
  else
    break
  fi
done

# Password verification loop
while true; do
  read -s -p "Enter a SECURE password for the RDP user account ($FARM_USER): " PASS1
  echo ""
  read -s -p "Confirm the password: " PASS2
  echo ""
  if [ "$PASS1" == "$PASS2" ]; then
    RDP_PASSWORD="$PASS1"
    break
  else
    echo "[-] Passwords do not match. Please try again."
  fi
done

read -p "Enter your Home IP address to whitelist for direct SSH (leave blank to ONLY allow SSH via the VPN or VPS Console): " HOME_IP

# 2. Update System and Install XFCE Desktop + Utilities (Debian 13 Polkit Fix)
echo "[+] Installing/Repairing XFCE4 desktop, utilities, and native browser..."
apt-get update
export DEBIAN_FRONTEND=noninteractive
apt-get install -y xfce4 xfce4-goodies curl wget ufw sed gnupg ca-certificates polkitd pkexec xvfb firefox-esr jq lightdm x11vnc

# 3. Install and Configure XRDP Server
echo "[+] Installing and configuring XRDP server..."
apt-get install -y xrdp
if getent group ssl-cert >/dev/null; then
  adduser xrdp ssl-cert || true
fi

# Set XFCE as the global default desktop engine for XRDP connections
sed -i 's|test -x /etc/X11/Xsession && exec /etc/X11/Xsession|startxfce4|g' /etc/xrdp/startwm.sh

# Fix Linux Polkit pop-up
mkdir -p /etc/polkit-1/rules.d
cat << 'EOF' > /etc/polkit-1/rules.d/50-color-management.rules
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.color-manager.create-device") === 0) {
        return polkit.Result.YES;
    }
});
EOF
systemctl enable --now xrdp

# 4. Provision the Windows-on-Linux Architecture (Pure 64-bit / WoW64 Engine)
echo "[+] Purging broken multi-arch layers and deploying pure 64-bit Wine..."

# Clean up any partial WineHQ installations from previous attempts
apt-get remove -y winehq-staging wine-staging winehq-stable wine-stable wine32 wine || true
rm -f /etc/apt/sources.list.d/winehq*.sources || true

# Forcefully remove the i386 architecture to permanently kill dependency hell
dpkg --remove-architecture i386 || true

# Update and install the native Debian 64-bit WoW64 execution framework
apt-get update
export DEBIAN_FRONTEND=noninteractive
apt-get install -y wine64

# 5. Build and Configure Headscale Private Mesh Coordinator
echo "[+] Installing/Repairing Headscale VPN server..."
if [ ! -f /usr/bin/headscale ]; then
  wget -q https://github.com/juanfont/headscale/releases/download/v0.23.0/headscale_0.23.0_linux_amd64.deb
  apt install ./headscale_0.23.0_linux_amd64.deb -y
  rm headscale_0.23.0_linux_amd64.deb
fi

mkdir -p /etc/headscale
if [ -f /etc/headscale/config.yaml ]; then
  sed -i "s|^server_url:.*|server_url: http://$PUBLIC_IP:8080|g" /etc/headscale/config.yaml
  sed -i "s|listen_addr: 127.0.0.1:8080|listen_addr: 0.0.0.0:8080|g" /etc/headscale/config.yaml
fi

systemctl enable --now headscale
headscale users create botuser || true

# 6. Bind the Host to its Private Network
echo "[+] Initializing localized VPN endpoint client connection..."
if [ ! -f /usr/bin/tailscale ]; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

HOST_AUTH_KEY=$(headscale preauthkeys create --user botuser --expiration 24h --output json 2>/dev/null | jq -r '.key' 2>/dev/null || headscale preauthkeys create --user botuser --expiration 24h | awk '{print $NF}')

tailscale up --login-server http://127.0.0.1:8080 --authkey "$HOST_AUTH_KEY" || true

# Grab internal VPN IP
VPN_IP=$(tailscale ip -4 || echo "100.64.0.1")

# Generate a key for the user's home computer
HOME_AUTH_KEY=$(headscale preauthkeys create --user botuser --expiration 24h --output json 2>/dev/null | jq -r '.key' 2>/dev/null || headscale preauthkeys create --user botuser --expiration 24h | awk '{print $NF}')

# 7. Apply the UFW Firewall Security Hardening
echo "[+] Resetting and locking down Firewall boundaries..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 8080/tcp     # Headscale Public handshake port
ufw allow in on tailscale0 to any port 3389  # Secure RDP
ufw allow in on tailscale0 to any port 22    # Secure SSH

if [ ! -z "$HOME_IP" ]; then
    echo "[+] Whitelisting direct SSH access for $HOME_IP..."
    ufw allow from "$HOME_IP" to any port 22
fi
ufw --force enable

# 8. Create or Update the Desktop User Profile
echo "[+] Initializing/Verifying system profile for '$FARM_USER'..."
if id "$FARM_USER" &>/dev/null; then
  echo "[*] User '$FARM_USER' already exists. Synchronizing password and environment..."
else
  useradd -m -s /bin/bash "$FARM_USER"
fi
echo "$FARM_USER:$RDP_PASSWORD" | chpasswd

echo "startxfce4" > "/home/$FARM_USER/.xsession"
chown "$FARM_USER:$FARM_USER" "/home/$FARM_USER/.xsession"

# 9. Download and Set the Custom Medieval Desktop Background
echo "[+] Deploying custom medieval wallpaper..."
mkdir -p "/home/$FARM_USER/Pictures"
wget -q "https://neato3.com/wp-content/uploads/2016/12/cropped-67008137-medieval-wallpapers.jpg" -O "/home/$FARM_USER/Pictures/neato-desktop.jpg" || true

mkdir -p /usr/share/backgrounds/xfce/
if [ -f "/home/$FARM_USER/Pictures/neato-desktop.jpg" ]; then
  cp "/home/$FARM_USER/Pictures/neato-desktop.jpg" /usr/share/backgrounds/xfce/xfce-blue.jpg
  cp "/home/$FARM_USER/Pictures/neato-desktop.jpg" /usr/share/backgrounds/xfce/xfce-teal.jpg
  ln -sf "/home/$FARM_USER/Pictures/neato-desktop.jpg" /usr/share/images/desktop-base/desktop-background
fi

mkdir -p "/home/$FARM_USER/.config/xfce4/xfconf/xfce-perchannel-xml"
cat << EOF > "/home/$FARM_USER/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/home/$FARM_USER/Pictures/neato-desktop.jpg"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitorrdp-0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/home/$FARM_USER/Pictures/neato-desktop.jpg"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
chown -R "$FARM_USER:$FARM_USER" "/home/$FARM_USER/Pictures" "/home/$FARM_USER/.config"

# 10. Pre-initialize the Wine Environment
echo "[+] Pre-initializing Wine prefix for '$FARM_USER'..."
sudo -u "$FARM_USER" WINEDEBUG=-all xvfb-run -a wineboot -u
mkdir -p "/home/$FARM_USER/Downloads"

# 11. Download and Install TheNEATBotfather
echo "[+] Fetching and installing TheNEATBotfather..."
wget -q "https://github.com/evony-tech/NeatBotfather/releases/download/1.9.6.5/TheNEATBotfather_v1.9.6.5_Setup.exe" -O "/home/$FARM_USER/Downloads/Botfather-Setup.exe" || true
chown -R "$FARM_USER:$FARM_USER" "/home/$FARM_USER/Downloads"
sudo -u "$FARM_USER" WINEDEBUG=-all xvfb-run -a wine "/home/$FARM_USER/Downloads/Botfather-Setup.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- || true

# 12. Download and Install NeatFlashBrowser
echo "[+] Fetching and installing NeatFlashBrowser..."
wget -q "https://neato3.com/NeatFlashBrowser-Setup.exe" -O "/home/$FARM_USER/Downloads/NeatFlashBrowser-Setup.exe" || true
chown -R "$FARM_USER:$FARM_USER" "/home/$FARM_USER/Downloads"
sudo -u "$FARM_USER" WINEDEBUG=-all xvfb-run -a wine "/home/$FARM_USER/Downloads/NeatFlashBrowser-Setup.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- || true

# 13. Override Wine Browser: HTTP to Flash Client, HTTPS to Native Linux Firefox
echo "[+] Injecting split-routing registry patch..."
cat << EOF > "/home/$FARM_USER/default-browser.reg"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Classes\http\shell\open\command]
@="\"C:\\Program Files (x86)\\NeatFlashBrowser\\NeatFlashBrowser.exe\" \"%1\""

[HKEY_CLASSES_ROOT\http\shell\open\command]
@="\"C:\\Program Files (x86)\\NeatFlashBrowser\\NeatFlashBrowser.exe\" \"%1\""

[HKEY_CURRENT_USER\Software\Classes\https\shell\open\command]
@="\"C:\\windows\\system32\\winebrowser.exe\" \"%1\""

[HKEY_CLASSES_ROOT\https\shell\open\command]
@="\"C:\\windows\\system32\\winebrowser.exe\" \"%1\""
EOF
chown "$FARM_USER:$FARM_USER" "/home/$FARM_USER/default-browser.reg"
sudo -u "$FARM_USER" WINEDEBUG=-all xvfb-run -a wine regedit "/home/$FARM_USER/default-browser.reg"

# 14. Generate Foolproof Desktop Shortcuts & Instructions
echo "[+] Generating Desktop Shortcuts..."
mkdir -p "/home/$FARM_USER/Desktop"

cp /usr/share/applications/firefox-esr.desktop "/home/$FARM_USER/Desktop/firefox.desktop" || true

cat << EOF > "/home/$FARM_USER/Desktop/NeatFlashBrowser.desktop"
[Desktop Entry]
Name=NeatFlashBrowser
Exec=env WINEPREFIX="/home/$FARM_USER/.wine" wine "C:\\Program Files (x86)\\NeatFlashBrowser\\NeatFlashBrowser.exe"
Type=Application
StartupNotify=true
Icon=wine
Terminal=false
EOF

cat << EOF > "/home/$FARM_USER/Desktop/Botfather.desktop"
[Desktop Entry]
Name=The NEAT Botfather
Exec=env WINEPREFIX="/home/$FARM_USER/.wine" wine "C:\\Program Files\\TheNEATBotfather\\TheNEATBotfather.exe"
Type=Application
StartupNotify=true
Icon=wine
Terminal=false
EOF

cat << EOF > "/home/$FARM_USER/Desktop/Tailscale_Setup_Instructions.txt"
=====================================================
    SECURE BOT FARM - HOME CONNECTION INSTRUCTIONS
=====================================================

To connect your home computer to this private network:

1. Download and install Tailscale: https://tailscale.com/download
2. Open Command Prompt (cmd.exe) on your Windows machine.
3. Copy and paste this exact command to link your machine:

   tailscale up --login-server http://$PUBLIC_IP:8080 --authkey $HOME_AUTH_KEY

4. Once connected, open Remote Desktop Connection (mstsc.exe).
5. Enter this IP: $VPN_IP
6. Log in with the username: $FARM_USER

=====================================================
EOF

chmod +x /home/$FARM_USER/Desktop/*.desktop || true
chown -R "$FARM_USER:$FARM_USER" "/home/$FARM_USER/Desktop"

# 15. Configure LightDM Auto-Login for Appliance Engine Mode
echo "[+] Configuring Automatic Host GUI Shell Login..."
mkdir -p /etc/lightdm
cat << EOF > /etc/lightdm/lightdm.conf
[Seat:*]
autologin-user=$FARM_USER
autologin-user-timeout=0
EOF

# 16. Add Botfather to XFCE System Boot Run-level Sequence
echo "[+] Registering Botfather daemon engine into user environment autostart sequence..."
mkdir -p "/home/$FARM_USER/.config/autostart"
cp "/home/$FARM_USER/Desktop/Botfather.desktop" "/home/$FARM_USER/.config/autostart/"
chown -R "$FARM_USER:$FARM_USER" "/home/$FARM_USER/.config/autostart"

# 17. Configure background x11vnc mirroring service
echo "[+] Creating screen mirroring pipeline for seamless RDP hook-in..."
cat << 'EOF' > /etc/systemd/system/x11vnc.service
[Unit]
Description=x11vnc Mirror Service for XRDP
After=display-manager.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -forever -loop -noxdamage -repeat -rfbport 5900 -shared
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now x11vnc

# Inject Mirror profile cleanly into XRDP configuration mapping rules
if ! grep -q "Mirror_VirtualBox_Screen" /etc/xrdp/xrdp.ini; then
cat << 'EOF' >> /etc/xrdp/xrdp.ini

[Mirror_VirtualBox_Screen]
name=Mirror VirtualBox Screen
lib=libvnc.so
ip=127.0.0.1
port=5900
username=na
password=ask
EOF
fi

systemctl restart xrdp

clear
echo "========================================================="
echo "   SUCCESS: APPLIANCE IS INSTALLED & AUTO-HEALED!       "
echo "========================================================="
echo " Your RDP Username: $FARM_USER"
echo " Your RDP Password: [Hidden and Confirmed]"
echo " Server VPN IP:     $VPN_IP"
echo ""
echo " --- HOME CONNECTION INSTRUCTIONS ---"
echo " 1. Install Tailscale on your Home PC (tailscale.com/download)"
echo " 2. Open Command Prompt (cmd.exe) on your Home PC and paste this exact command:"
echo ""
echo "    tailscale up --login-server http://$PUBLIC_IP:8080 --authkey $HOME_AUTH_KEY"
echo ""
echo " 3. Once connected, open Remote Desktop Connection (mstsc.exe)."
echo " 4. Enter $VPN_IP"
echo " 5. Switch the login dropdown protocol selection option to 'Mirror VirtualBox Screen'."
echo " 6. Type your password to enter the live boot session."
echo ""
echo " Please reboot the virtual machine now to verify the boot sequence:"
echo " Command: sudo reboot"
echo "========================================================="
