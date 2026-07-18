#!/bin/bash
# =====================================================================
# MASTER NEATBOT FARM PROVISIONING & AUTO-HEAL SCRIPT (DEBIAN 11/12/13)
# ZERO-TOUCH UNATTENDED INSTALLATION VERSION
# =====================================================================

set -e
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: This script must be run as root."
  exit 1
fi

echo "========================================================="
echo "  Deploying Hardened XFCE + Auto-Login + Wine Bot Farm   "
echo "========================================================="

# 1. Unattended Configuration Details
# FIXED: Swapped curl for wget to support barebones Debian ISOs
PUBLIC_IP=$(wget -4 -qO- https://ifconfig.me || wget -4 -qO- icanhazip.com || echo "127.0.0.1")
# Sanitize the IP right away to strip any hidden newlines or spaces
CLEAN_IP=$(echo "$PUBLIC_IP" | tr -d '[:space:]')
if [ -z "$CLEAN_IP" ]; then CLEAN_IP="127.0.0.1"; fi
echo "[+] Detected Public IP: $CLEAN_IP"

# Use environment variables if set, otherwise fallback to defaults
FARM_USER=${FARM_USER:-"botfarmer"}
HOME_IP=${HOME_IP:-""}

# Auto-generate a secure 16-character password if not supplied
if [ -z "$RDP_PASSWORD" ]; then
  RDP_PASSWORD=$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 16)
  echo "[+] Auto-generated RDP Password."
fi

# 2. Update System and Install Core Packages
echo "[+] Installing XFCE4, utilities, and Wine Multi-Arch..."
dpkg --add-architecture i386
apt-get update
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -o Dpkg::Options::="--force-overwrite" xfce4 xfce4-goodies curl wget ufw sed gnupg ca-certificates polkitd pkexec xvfb jq lightdm x11vnc sudo wine wine64 wine32 dbus-x11 faketime tar xz-utils libdbus-glib-1-2

# 3. Install and Configure XRDP Server
echo "[+] Installing and configuring XRDP server..."
apt-get install -y xrdp
if getent group ssl-cert >/dev/null; then
  adduser xrdp ssl-cert || true
fi
sed -i 's|test -x /etc/X11/Xsession && exec /etc/X11/Xsession|startxfce4|g' /etc/xrdp/startwm.sh

mkdir -p /etc/polkit-1/rules.d
cat << 'EOF' > /etc/polkit-1/rules.d/50-color-management.rules
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.color-manager.create-device") === 0) {
        return polkit.Result.YES;
    }
});
EOF
systemctl enable --now xrdp

# 4. Provision the Windows-on-Linux Architecture
echo "[+] Wine Multi-Architecture verified..."

# 5. Build and Configure Headscale Private Mesh Coordinator
echo "[+] Installing/Repairing Headscale VPN server (v0.29.2)..."
if [ ! -f /usr/bin/headscale ]; then
  wget -q https://github.com/juanfont/headscale/releases/download/v0.29.2/headscale_0.29.2_linux_amd64.deb
  apt install ./headscale_0.29.2_linux_amd64.deb -y
  rm headscale_0.29.2_linux_amd64.deb
fi

mkdir -p /etc/headscale
if [ -f /etc/headscale/config.yaml ]; then
  # Wrap the URL in double-quotes to protect the YAML parser from bare colons
  sed -i "s|^server_url:.*|server_url: \"http://$CLEAN_IP:8080\"|g" /etc/headscale/config.yaml
  sed -i "s|listen_addr: 127.0.0.1:8080|listen_addr: 0.0.0.0:8080|g" /etc/headscale/config.yaml
fi

systemctl enable --now headscale
systemctl restart headscale

# Wait 3 seconds to ensure the service is fully booted before throwing commands at it
sleep 3

# Create the user (This automatically assigns them ID 1)
headscale users create botuser || true

# 6. Bind the Host to its Private Network
echo "[+] Initializing localized VPN endpoint client connection..."
if [ ! -f /usr/bin/tailscale ]; then
  # FIXED: Swapped curl for wget
  wget -qO- https://tailscale.com/install.sh | sh
fi

# Generate the pre-auth key using the numeric ID (1) instead of the string name
HOST_AUTH_KEY=$(headscale preauthkeys create --user 1 --expiration 24h)

# Start Tailscale silently using the local loopback and the new key
tailscale up --login-server="http://127.0.0.1:8080" --authkey="${HOST_AUTH_KEY}"

# Capture the newly assigned VPN IP
VPN_IP=$(tailscale ip -4 || echo "100.64.0.1")
VPN_IP=$(echo "$VPN_IP" | tr -d '[:space:]')

# Generate a second one-time key for the user's home Windows machine
HOME_AUTH_KEY=$(headscale preauthkeys create --user 1 --expiration 24h)

# 7. Apply the UFW Firewall Security Hardening
echo "[+] Resetting and locking down Firewall boundaries..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 8080/tcp
ufw allow in on tailscale0 to any port 3389
ufw allow in on tailscale0 to any port 22
ufw allow in on tailscale0 to any port 8025
ufw allow in on lo to any port 8025

if [ ! -z "$HOME_IP" ]; then
    echo "[+] Whitelisting direct SSH access for $HOME_IP..."
    ufw allow from "$HOME_IP" to any port 22
fi
ufw --force enable

# 8. Create or Update the Desktop User Profile
echo "[+] Initializing/Verifying system profile for '$FARM_USER'..."
if id "$FARM_USER" &>/dev/null; then
  echo "[*] User '$FARM_USER' already exists."
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
sudo -u "$FARM_USER" DISPLAY=:0 dbus-launch xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "/home/$FARM_USER/Pictures/neato-desktop.jpg" --create -t string || true
sudo -u "$FARM_USER" DISPLAY=:0 dbus-launch xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorrdp-0/workspace0/last-image -s "/home/$FARM_USER/Pictures/neato-desktop.jpg" --create -t string || true
sudo -u "$FARM_USER" DISPLAY=:0 dbus-launch xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorVirtual1/workspace0/last-image -s "/home/$FARM_USER/Pictures/neato-desktop.jpg" --create -t string || true

# 10. Pre-initialize the Wine Environment and Inject .NET Framework via Cache
echo "[+] Constructing local Wine storage directories..."
mkdir -p "/home/$FARM_USER/.cache/wine"
wget -q "https://dl.winehq.org/wine/wine-mono/10.0.0/wine-mono-10.0.0-x86.msi" -O "/home/$FARM_USER/.cache/wine/wine-mono-10.0.0-x86.msi" || true
chown -R "$FARM_USER:$FARM_USER" "/home/$FARM_USER/.cache"
sudo -u "$FARM_USER" WINEDEBUG=-all xvfb-run -a wineboot -u
sleep 3
sudo -u "$FARM_USER" wineserver -w || true
sudo -u "$FARM_USER" wineserver -k || true
sleep 2

# 11. Download and Install TheNEATBotfather
echo "[+] Fetching and installing TheNEATBotfather..."
wget -q "https://github.com/evony-tech/NeatBotfather/releases/download/1.9.6.5/TheNEATBotfather_v1.9.6.5_Setup.exe" -O "/home/$FARM_USER/Downloads/Botfather-Setup.exe" || true
chown -R "$FARM_USER:$FARM_USER" "/home/$FARM_USER/Downloads"
sudo -u "$FARM_USER" WINEDEBUG=-all xvfb-run -a wine "/home/$FARM_USER/Downloads/Botfather-Setup.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- || true

# 12. Deploy Standalone Pale Moon Browser & Inject Native Flash Player
echo "[+] Delivering un-throttled Linux NPAPI Flash Layer into System Nodes..."
mkdir -p /usr/lib/mozilla/plugins/
wget -q "https://github.com/darknebular/bypassing-flash-timebomb/releases/download/v1.0/libflashplayer.so" -O /usr/lib/mozilla/plugins/libflashplayer.so
chmod 644 /usr/lib/mozilla/plugins/libflashplayer.so
wget -q "https://relapi.palemoon.org/release/palemoon-33.4.0.1.linux-x86_64-gtk3.tar.xz" -O /tmp/palemoon.tar.xz || true
tar -xf /tmp/palemoon.tar.xz -C /opt/ || true
ln -sf /opt/palemoon/palemoon /usr/bin/palemoon || true
rm -f /tmp/palemoon.tar.xz

mkdir -p "/home/$FARM_USER/.moonchild productions/pale moon"
sudo -u "$FARM_USER" HOME="/home/$FARM_USER" xvfb-run -a /opt/palemoon/palemoon --headless & PM_PID=$!; sleep 4; kill $PM_PID || true
PM_PROFILE=$(ls "/home/$FARM_USER/.moonchild productions/pale moon" | grep default)
if [ ! -z "$PM_PROFILE" ]; then
cat << 'EOF' >> "/home/$FARM_USER/.moonchild productions/pale moon/$PM_PROFILE/prefs.js"
user_pref("browser.startup.homepage", "http://forum.neatportal.com/viewtopic.php?f=49&t=6747");
user_pref("browser.startup.page", 1);
EOF
chown -R "$FARM_USER:$FARM_USER" "/home/$FARM_USER/.moonchild productions"
fi

# 13. Override Wine Browser: Global Split Routing Tunnel to Native Linux Pale Moon
echo "[+] Intercepting Wine URL triggers and redirecting out to native system..."
sudo -u "$FARM_USER" wineserver -k || true
sleep 2
cat << EOF > "/home/$FARM_USER/default-browser.reg"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Classes\http\shell\open\command]
@="\"C:\\windows\\system32\\winebrowser.exe\" \"%1\""
[HKEY_CLASSES_ROOT\http\shell\open\command]
@="\"C:\\windows\\system32\\winebrowser.exe\" \"%1\""
[HKEY_CURRENT_USER\Software\Classes\https\shell\open\command]
@="\"C:\\windows\\system32\\winebrowser.exe\" \"%1\""
[HKEY_CLASSES_ROOT\https\shell\open\command]
@="\"C:\\windows\\system32\\winebrowser.exe\" \"%1\""
EOF
chown "$FARM_USER:$FARM_USER" "/home/$FARM_USER/default-browser.reg"
sudo -u "$FARM_USER" WINEDEBUG=-all xvfb-run -a wine regedit /S "/home/$FARM_USER/default-browser.reg" || true

sudo -u "$FARM_USER" xdg-settings set default-web-browser palemoon.desktop || true
xdg-mime default palemoon.desktop x-scheme-handler/http || true
xdg-mime default palemoon.desktop x-scheme-handler/https || true

# 14. Generate Foolproof Desktop Shortcuts
echo "[+] Generating Desktop Shortcuts..."
mkdir -p "/home/$FARM_USER/Desktop"
cat << EOF > "/home/$FARM_USER/Desktop/PaleMoon.desktop"
[Desktop Entry]
Name=Flash Game Client (Pale Moon)
Exec=palemoon
Type=Application
Icon=palemoon
Terminal=false
EOF

cat << EOF > "/home/$FARM_USER/Desktop/Botfather.desktop"
[Desktop Entry]
Name=The NEAT Botfather
Exec=env WINEPREFIX="/home/$FARM_USER/.wine" wine "C:\\\\Program Files\\\\TheNEATBotfather\\\\TheNEATBotfather.exe"
Type=Application
StartupNotify=true
Icon=wine
Terminal=false
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
cat << EOF > /etc/systemd/system/x11vnc.service
[Unit]
Description=x11vnc Mirror Service for XRDP
After=display-manager.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -forever -loop -noxdamage -repeat -rfbport 5900 -shared -listen 127.0.0.1 -passwd $RDP_PASSWORD
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

chmod 600 /etc/systemd/system/x11vnc.service
systemctl daemon-reload
systemctl enable --now x11vnc

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

# 18. Save Credentials for Unattended Retrieval
cat << EOF > /root/botfarm_setup_instructions.txt
=====================================================
   SUCCESS: APPLIANCE IS INSTALLED & AUTO-HEALED!    
=====================================================
 Your RDP Username: $FARM_USER
 Your RDP Password: $RDP_PASSWORD
 Server VPN IP:     $VPN_IP

 --- HOME CONNECTION INSTRUCTIONS ---
 1. Install Tailscale on your Home PC (tailscale.com/download)
 2. Open Command Prompt (cmd.exe) on your Home PC and paste this exact command:

    tailscale up --login-server http://$CLEAN_IP:8080 --authkey $HOME_AUTH_KEY

 3. Once connected, open Remote Desktop Connection (mstsc.exe).
 4. Enter $VPN_IP
 5. Switch the login dropdown protocol option to 'Mirror VirtualBox Screen'.
 6. Type your password to enter the live boot session.
=====================================================
EOF

cat /root/botfarm_setup_instructions.txt
