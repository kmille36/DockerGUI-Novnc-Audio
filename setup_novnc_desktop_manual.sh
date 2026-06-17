#!/bin/bash
# =============================================================================
# VNC Desktop Environment Setup Script
# Converted from Dockerfile — runs directly on Ubuntu 20.04 (no Docker needed)
# Usage: sudo bash setup_vnc_desktop.sh
# =============================================================================

set -e  # Exit on any error

# ─────────────────────────────────────────────
# CONFIGURATION (edit these as needed)
# ─────────────────────────────────────────────
GUI="${GUI:-xfce}"
VNC_PASSWD="${VNC_PASSWD:-123456}"
PORT="${PORT:-8081}"
AUDIO_PORT="${AUDIO_PORT:-1699}"
WEBSOCKIFY_PORT="${WEBSOCKIFY_PORT:-6900}"
VNC_PORT="${VNC_PORT:-5900}"
SCREEN_WIDTH="${SCREEN_WIDTH:-1024}"
SCREEN_HEIGHT="${SCREEN_HEIGHT:-768}"
SCREEN_DEPTH="${SCREEN_DEPTH:-32}"
USERNAME="${USERNAME:-ubuntu}"
HOME_DIR="/home/${USERNAME}"

# ─────────────────────────────────────────────
# REQUIRE ROOT
# ─────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root (or with sudo)." >&2
  exit 1
fi

# ─────────────────────────────────────────────
# EXPORT ENV (mirrors Dockerfile ENV lines)
# ─────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

echo "================================================================"
echo " VNC Desktop Setup"
echo " User     : $USERNAME"
echo " GUI      : $GUI"
echo " VNC port : $VNC_PORT   noVNC port: $PORT"
echo " Resolution: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH}"
echo "================================================================"

# ─────────────────────────────────────────────
# STEP 1 — Basic utilities
# ─────────────────────────────────────────────
echo ""
echo "[1/9] Installing basic utilities (unzip, zip)..."
apt-get update -qq
apt-get install -y -qq unzip zip

# ─────────────────────────────────────────────
# STEP 2 — Unpack bin.zip (must exist beside this script)
# ─────────────────────────────────────────────
echo ""
echo "[2/9] Unpacking bin.zip to /opt/ ..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/bin.zip" ]]; then
  echo "ERROR: bin.zip not found next to this script (${SCRIPT_DIR}/bin.zip)." >&2
  echo "       Place bin.zip in the same directory as this script and re-run." >&2
  exit 1
fi

mkdir -p /opt
cp "${SCRIPT_DIR}/bin.zip" /opt/
cd /opt && unzip -o bin.zip

# Make all scripts in /opt/bin executable
chmod +x /opt/bin/*.sh 2>/dev/null || true

# ─────────────────────────────────────────────
# STEP 3 — Core VNC / display packages
# ─────────────────────────────────────────────
echo ""
echo "[3/9] Installing VNC and display packages..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  sudo supervisor dbus-x11 xvfb x11vnc x11-xserver-utils \
  tigervnc-standalone-server tigervnc-common \
  novnc websockify wget curl unzip gettext

# Run apt cleanup helper if it exists
[[ -x /opt/bin/apt_clean.sh ]] && bash /opt/bin/apt_clean.sh

# ─────────────────────────────────────────────
# STEP 4 — Audio packages
# ─────────────────────────────────────────────
echo ""
echo "[4/9] Installing audio and streaming packages..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  pulseaudio pavucontrol alsa-base ffmpeg nginx

[[ -x /opt/bin/apt_clean.sh ]] && bash /opt/bin/apt_clean.sh

# ─────────────────────────────────────────────
# STEP 5 — System / filesystem setup
# ─────────────────────────────────────────────
echo ""
echo "[5/9] Configuring /dev/shm and X11 socket dir..."
chmod +x /dev/shm
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# ─────────────────────────────────────────────
# STEP 6 — Create user
# ─────────────────────────────────────────────
echo ""
echo "[6/9] Creating user '${USERNAME}'..."

if ! getent group "${USERNAME}" > /dev/null 2>&1; then
  groupadd "${USERNAME}" --gid 1001
fi

if ! id "${USERNAME}" > /dev/null 2>&1; then
  useradd "${USERNAME}" \
    --create-home \
    --gid 1001 \
    --shell /bin/bash \
    --uid 1001
fi

usermod -aG sudo "${USERNAME}"

# Passwordless sudo
if ! grep -q 'ALL ALL = (ALL) NOPASSWD: ALL' /etc/sudoers; then
  echo 'ALL ALL = (ALL) NOPASSWD: ALL' >> /etc/sudoers
fi

# Set user password to username (mirrors: echo "$USERNAME:$USERNAME" | chpasswd)
echo "${USERNAME}:${USERNAME}" | chpasswd

# ─────────────────────────────────────────────
# STEP 7 — Copy config files (must be beside this script)
# ─────────────────────────────────────────────
echo ""
echo "[7/9] Copying config files..."

if [[ -f "${SCRIPT_DIR}/supervisord.conf" ]]; then
  cp "${SCRIPT_DIR}/supervisord.conf" /etc/supervisor/supervisord.conf
else
  echo "WARNING: supervisord.conf not found — skipping." >&2
fi

if [[ -f "${SCRIPT_DIR}/nginx.conf" ]]; then
  mkdir -p /etc/nginx/conf.d
  cp "${SCRIPT_DIR}/nginx.conf" /etc/nginx/conf.d/nginx.conf.template
else
  echo "WARNING: nginx.conf not found — skipping." >&2
fi

# ─────────────────────────────────────────────
# STEP 8 — Run installer scripts from bin.zip
# ─────────────────────────────────────────────
echo ""
echo "[8/9] Running installer scripts from /opt/bin/ ..."

echo "  → install_gui.sh (GUI: $GUI)"
[[ -x /opt/bin/install_gui.sh ]] && GUI="$GUI" bash /opt/bin/install_gui.sh \
  || echo "WARNING: install_gui.sh failed or not found."

echo "  → install_utils.sh"
[[ -x /opt/bin/install_utils.sh ]] && bash /opt/bin/install_utils.sh \
  || echo "WARNING: install_utils.sh failed or not found."

echo "  → setup_audio.sh"
[[ -x /opt/bin/setup_audio.sh ]] && bash /opt/bin/setup_audio.sh \
  || echo "WARNING: setup_audio.sh failed or not found."

# ─────────────────────────────────────────────
# STEP 9 — noVNC custom build (vnc.zip)
# ─────────────────────────────────────────────
echo ""
echo "[9/9] Installing custom noVNC build from vnc.zip..."

if [[ -f "${SCRIPT_DIR}/vnc.zip" ]]; then
  cp "${SCRIPT_DIR}/vnc.zip" /usr/share/
  rm -rf /usr/share/novnc/
  cd /usr/share && unzip -o vnc.zip

  # Patch noVNC resize default: 'off' → 'remote'
  NOVNC_UI="/usr/share/novnc/app/ui.js"
  if [[ -f "$NOVNC_UI" ]]; then
    sed -i "s/UI.initSetting('resize', 'off');/UI.initSetting('resize', 'remote');/g" "$NOVNC_UI"
    echo "  → Patched $NOVNC_UI (resize default set to 'remote')"
  else
    echo "WARNING: $NOVNC_UI not found — resize patch skipped." >&2
  fi
else
  echo "WARNING: vnc.zip not found — using system novnc." >&2
fi

# Relax permissions (run as root, script may chown things for $USERNAME)
[[ -x /opt/bin/relax_permission.sh ]] && bash /opt/bin/relax_permission.sh \
  || echo "WARNING: relax_permission.sh failed or not found."

# ─────────────────────────────────────────────
# WRITE ENVIRONMENT FILE (so entry_point.sh can read it)
# ─────────────────────────────────────────────
ENV_FILE="/opt/vnc_env.sh"
cat > "$ENV_FILE" << EOF
export GUI="${GUI}"
export VNC_PASSWD="${VNC_PASSWD}"
export PORT="${PORT}"
export AUDIO_PORT="${AUDIO_PORT}"
export WEBSOCKIFY_PORT="${WEBSOCKIFY_PORT}"
export VNC_PORT="${VNC_PORT}"
export SCREEN_WIDTH="${SCREEN_WIDTH}"
export SCREEN_HEIGHT="${SCREEN_HEIGHT}"
export SCREEN_DEPTH="${SCREEN_DEPTH}"
export USERNAME="${USERNAME}"
export HOME="${HOME_DIR}"
EOF
chmod 644 "$ENV_FILE"
echo ""
echo "Environment saved to $ENV_FILE"

# ─────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────
echo ""
echo "================================================================"
echo " Setup complete!"
echo ""
echo " To start the VNC desktop, run as user '${USERNAME}':"
echo "   source /opt/vnc_env.sh && bash /opt/bin/entry_point.sh"
echo ""
echo " Or add to /etc/rc.local to start on boot:"
echo "   su - ${USERNAME} -c 'source /opt/vnc_env.sh && bash /opt/bin/entry_point.sh &'"
echo ""
echo " Access via browser: http://<your-ip>:${PORT}"
echo "================================================================"
