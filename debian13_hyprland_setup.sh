#!/usr/bin/env bash

set -e

# If you want to run this script non-interactively, set the following environment variables:
#
#   BUILD_DIR="$HOME/hyprdebian" - you can set the BUILD_DIR somewhere else if you want
#   DISABLE_CONFIRM=false|true - disable the settings confirmation message
#   HYPRIDLE_SETUP=true|false - whether to set up (minimal config) hypridle
#   HYPRLOCK_SETUP=true|false - whether to install (without config) hyprlock
#   HYPRPAPER_SETUP=true|false - whether to install (without config) hyprpaper
#   HYPRSHOT_SETUP=true|false - whether to set up (minimal config) hyprshot
#   NOTIFICATION_DAEMON_PREF=dunst|mako|swaync|none - whether to set up a notification daemon
#   NVIDIA_SETUP=true|false - whether to set up nvidia proprietary drivers (ignored if no nvidia card is detected)
#   SWAYOSD_SETUP=true|false - whether to set up (minimal config) swayosd
#   THEME_PREF=dark|light|none - whether to set a default Adwaita theme
#   THUNAR_SETUP=true|false - whether to set up thunar
#   TUIGREET_SETUP=true|false - whether to set up tuigreet as the login manager
#   WAYBAR_SETUP=true|false - whether to install (minimal config) waybar as the status bar

PHY_CORES=$(lscpu -p=CORE,SOCKET | grep -v '^#' | sort -u | wc -l)
MAKE_THREADS=$((PHY_CORES > 1 ? PHY_CORES - 1 : 1))
DEBIAN_CODENAME="trixie"

ensure_debian_13() {
  if [ ! -r /etc/os-release ]; then
    echo "Error: Cannot read /etc/os-release; this script targets Debian 13 (Trixie)."
    exit 1
  fi

  # shellcheck source=/dev/null
  . /etc/os-release
  if [ "${ID:-}" != "debian" ] || { [ "${VERSION_ID:-}" != "13" ] && [ "${VERSION_CODENAME:-}" != "$DEBIAN_CODENAME" ]; }; then
    echo "Error: This script targets Debian 13 (Trixie), but detected ${PRETTY_NAME:-unknown OS}."
    exit 1
  fi
}

ask_yes_no() {
  local PROMPT="$1"
  local VAR_NAME="$2"
  local DEFAULT_VAL="$3"

  if [[ -n "${!VAR_NAME}" ]]; then
    return
  fi

  if [[ "$DEFAULT_VAL" == "true" ]]; then
    read -p "$PROMPT [Y/n] " -r
  else
    read -p "$PROMPT [y/N] " -r
  fi
  if [[ $REPLY =~ ^[Nn] ]]; then
    printf -v "$VAR_NAME" "%s" "false"
  else
    printf -v "$VAR_NAME" "%s" "true"
  fi
}

apt_install() {
  if [ $# -eq 0 ]; then
    return
  fi

  echo "Installing apt dependencies: $*"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt_install_backports() {
  if [ $# -eq 0 ]; then
    return
  fi

  echo "Installing Debian $DEBIAN_CODENAME backports dependencies: $*"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -t "$DEBIAN_CODENAME-backports" "$@"
}

apt_sources_contain() {
  grep -Rqs "$1" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
}

ensure_debian_13_apt_sources() {
  if ! apt_sources_contain "non-free-firmware"; then
    echo "Enabling Debian contrib/non-free/non-free-firmware components..."
    sudo tee /etc/apt/sources.list.d/hyprdebian-nonfree.sources >/dev/null <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $DEBIAN_CODENAME $DEBIAN_CODENAME-updates
Components: contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: $DEBIAN_CODENAME-security
Components: contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  fi

  if ! apt_sources_contain "$DEBIAN_CODENAME-backports"; then
    echo "Enabling Debian $DEBIAN_CODENAME backports..."
    sudo tee /etc/apt/sources.list.d/hyprdebian-backports.sources >/dev/null <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $DEBIAN_CODENAME-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  fi

  sudo DEBIAN_FRONTEND=noninteractive apt-get update
}

ensure_gcc_15() {
  if command -v gcc-15 >/dev/null 2>&1 && command -v g++-15 >/dev/null 2>&1; then
    return
  fi

  echo "Installing gcc-15/g++-15 from Debian sid with low-priority pinning..."
  sudo tee /etc/apt/sources.list.d/hyprdebian-sid.sources >/dev/null <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: sid
Components: main
Enabled: yes
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  sudo tee /etc/apt/preferences.d/99-hyprdebian-pin-sid >/dev/null <<'EOF'
Package: *
Pin: release a=unstable
Pin-Priority: 100
EOF

  sudo DEBIAN_FRONTEND=noninteractive apt-get update
  if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -t sid gcc-15 g++-15; then
    sudo sed -i 's/^Enabled: yes/Enabled: no/' /etc/apt/sources.list.d/hyprdebian-sid.sources
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    return 1
  fi
  sudo sed -i 's/^Enabled: yes/Enabled: no/' /etc/apt/sources.list.d/hyprdebian-sid.sources
  sudo DEBIAN_FRONTEND=noninteractive apt-get update
}

UPGRADES=()
install_hyprwm_package() {
  local PACKAGE_NAME="$1"
  local GIT_REF="$2" # A specific tag or branch, or "@stable" for latest tag
  shift 2
  local DEPS=("$@")
  local CMAKE_ARGS=(
    -S .
    -B build
    -G Ninja
    -DCMAKE_INSTALL_PREFIX=/usr
    -DCMAKE_BUILD_TYPE=Release
  )
  if [ -n "${DEB_HOST_MULTIARCH:-}" ]; then
    CMAKE_ARGS+=("-DCMAKE_INSTALL_LIBDIR=lib/$DEB_HOST_MULTIARCH")
  else
    CMAKE_ARGS+=("-DCMAKE_INSTALL_LIBDIR=lib")
  fi
  if [ -n "${CC:-}" ]; then
    CMAKE_ARGS+=("-DCMAKE_C_COMPILER=$CC")
  fi
  if [ -n "${CXX:-}" ]; then
    CMAKE_ARGS+=("-DCMAKE_CXX_COMPILER=$CXX")
  fi

  echo "------------------------------------------------"
  echo "Installing hyprwm/$PACKAGE_NAME..."
  echo "------------------------------------------------"
  local JUST_CLONED=false
  if [ ! -d "$BUILD_DIR/$PACKAGE_NAME" ]; then
    git clone --recursive "https://github.com/hyprwm/$PACKAGE_NAME.git" "$BUILD_DIR/$PACKAGE_NAME"
    JUST_CLONED=true
  fi
  cd "$BUILD_DIR/$PACKAGE_NAME"
  local OLD_REF
  local OLD_VERSION
  OLD_REF=$(git rev-parse HEAD)
  OLD_VERSION=$(git describe --tags --exact-match 2>/dev/null || git symbolic-ref -q --short HEAD 2>/dev/null || git rev-parse --short HEAD)
  if [ "$JUST_CLONED" = "true" ]; then
    echo "Fresh clone; skipping redundant fetch."
  else
    echo "Fetching updates for hyprwm/$PACKAGE_NAME..."
    if ! git fetch --all --tags --prune; then
      echo "Warning: failed to fetch hyprwm/$PACKAGE_NAME; continuing with the local checkout if possible."
    fi
  fi
  local LATEST_TAG
  local LATEST_REF
  LATEST_TAG=$(git tag --sort=-v:refname | head -n 1)
  if [ "@stable" = "$GIT_REF" ]; then
    if [ -z "$LATEST_TAG" ]; then
      echo "hyprwm/$PACKAGE_NAME has no tags"
      exit 1
    fi
    echo "Checking out latest tag: $LATEST_TAG"
    TARGET="$LATEST_TAG"
  else
    echo "Manual override: Checking out $GIT_REF"
    TARGET="$GIT_REF"
  fi
  LATEST_REF=$(git rev-parse "$LATEST_TAG")
  git checkout "$TARGET"
  if git show-ref --verify --quiet "refs/remotes/origin/$TARGET"; then
    echo "Resetting branch $TARGET to remote state..."
    git reset --hard "origin/$TARGET"
  fi
  git submodule sync --recursive
  git submodule update --init --force --recursive
  local NEW_REF
  local NEW_VERSION
  NEW_REF=$(git rev-parse HEAD)
  NEW_VERSION=$(git describe --tags --exact-match 2>/dev/null || git symbolic-ref -q --short HEAD 2>/dev/null || git rev-parse --short HEAD)
  if [ "$LATEST_REF" != "$NEW_REF" ]; then
    UPGRADES+=("hyprwm/$PACKAGE_NAME Built $NEW_VERSION although $LATEST_TAG is the latest")
  fi
  if [ "$OLD_REF" != "$NEW_REF" ]; then
    git clean -ffdx
    UPGRADES+=("hyprwm/$PACKAGE_NAME Upgraded $OLD_VERSION -> $NEW_VERSION")
  else
    git clean -ffdx -e build/
  fi
  git reset --hard HEAD
  git submodule foreach --recursive git reset --hard
  git submodule foreach --recursive git clean -ffdx
  if [ ${#DEPS[@]} -gt 0 ]; then
    apt_install "${DEPS[@]}"
  fi
  cmake "${CMAKE_ARGS[@]}"
  cmake --build build -j "$MAKE_THREADS"
  sudo cmake --install build
  sudo ldconfig
}

# whoami

if [ "$EUID" -eq 0 ]; then
  echo "Error: Please run this script as your normal user, not directly as root or with sudo."
  echo "The script will ask for your sudo password when it needs to install packages."
  exit 1
fi
ensure_debian_13
if ! sudo -v &>/dev/null; then
  echo "Error: You need sudo privileges to run this script."
  echo "Please ensure your user is in the sudo group/sudoers file."
  exit 1
fi

while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" || exit
done 2>/dev/null &

# I have questions

apt_install pciutils
has_nvidia() {
  if lspci | grep -qi nvidia; then
    return 0 # true
  fi
  return 1 # false
}
if has_nvidia; then
  ask_yes_no "Would you like to install nvidia proprietary drivers" "NVIDIA_SETUP" "true"
fi

if [ -z "${THEME_PREF}" ]; then
  echo "Would you like to set a default base theme? (Adwaita)"
  echo "1) Dark Theme (Recommended)"
  echo "2) Light Theme"
  echo "3) None / Skip"
  read -p "Select an option [1-3, default 1]: " -r
  case $REPLY in
  2) THEME_PREF="light" ;;
  3) THEME_PREF="none" ;;
  *) THEME_PREF="dark" ;; # Default to dark
  esac
fi

if [ -z "${NOTIFICATION_DAEMON_PREF}" ]; then
  echo "Would you like to setup a notification daemon?"
  echo "1) dunst"
  echo "2) mako"
  echo "3) swaync (Recommended)"
  echo "4) None / Skip"
  read -p "Select an option [1-3, default 1]: " -r
  case $REPLY in
  1) NOTIFICATION_DAEMON_PREF="dunst" ;;
  2) NOTIFICATION_DAEMON_PREF="mako" ;;
  4) NOTIFICATION_DAEMON_PREF="none" ;;
  *) NOTIFICATION_DAEMON_PREF="swaync" ;; # Default to swaync
  esac
fi

ask_yes_no "Would you like to install hyprpaper" "HYPRPAPER_SETUP" "true"
ask_yes_no "Would you like to install hyprlock" "HYPRLOCK_SETUP" "true"
ask_yes_no "Would you like to install hypridle" "HYPRIDLE_SETUP" "true"
ask_yes_no "Would you like to install hyprshot" "HYPRSHOT_SETUP" "true"
ask_yes_no "Would you like to install swayosd (media keys/brightness)" "SWAYOSD_SETUP" "true"
ask_yes_no "Would you like to install thunar (GUI file explorer)" "THUNAR_SETUP" "true"
ask_yes_no "Would you like to install waybar (status bar)" "WAYBAR_SETUP" "true"

has_tuigreet() {
  if command -v tuigreet &>/dev/null; then
    return 0 # true
  fi
  return 1 # false
}
ACTIVE_DESKTOP_MANAGER_SERVICES=()
DESKTOP_MANAGER_SERVICES=(
  gdm.service
  gdm3.service
  greetd.service
  lightdm.service
  lxdm.service
  ly.service
  sddm.service
  slim.service
  xdm.service
)
for SERVICE in "${DESKTOP_MANAGER_SERVICES[@]}"; do
  if systemctl is-active --quiet "$SERVICE" || systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
    ACTIVE_DESKTOP_MANAGER_SERVICES+=("$SERVICE")
  fi
done
has_desktop_manager() {
  if [ "${#ACTIVE_DESKTOP_MANAGER_SERVICES[@]}" -gt 0 ]; then
    return 0
  else
    return 1
  fi
}
if has_tuigreet; then
  echo "tuigreet is already setup, skipping login manager setup"
  TUIGREET_SETUP=false
else
  if has_desktop_manager; then
    ACTIVE_DESKTOP_MANAGER_SERVICE_LIST=$(printf "%s\n" "${ACTIVE_DESKTOP_MANAGER_SERVICES[@]}")

    cat <<EOF
The following login manager(s) are active or enabled:

$ACTIVE_DESKTOP_MANAGER_SERVICE_LIST

If you want to use something else (e.g. tuigreet) you should remove your current desktop manager.
EOF
  else
    ask_yes_no "No desktop manager detected, would you like to setup tuigreet" "TUIGREET_SETUP" "true"
  fi
fi

if [ -z "${BUILD_DIR}" ]; then
  BUILD_DIR="$HOME/hyprdebian"
fi

cat <<EOF

-----------------------------------------------
Hyprdebian setup environment
-----------------------------------------------

NVIDIA_SETUP="$NVIDIA_SETUP"
THEME_PREF="$THEME_PREF"
NOTIFICATION_DAEMON_PREF="$NOTIFICATION_DAEMON_PREF"
HYPRPAPER_SETUP="$HYPRPAPER_SETUP"
HYPRLOCK_SETUP="$HYPRLOCK_SETUP"
HYPRIDLE_SETUP="$HYPRIDLE_SETUP"
HYPRSHOT_SETUP="$HYPRSHOT_SETUP"
SWAYOSD_SETUP="$SWAYOSD_SETUP"
THUNAR_SETUP="$THUNAR_SETUP"
WAYBAR_SETUP="$WAYBAR_SETUP"
TUIGREET_SETUP="$TUIGREET_SETUP"
BUILD_DIR="$BUILD_DIR"

EOF
if [[ "$DISABLE_CONFIRM" != "true" ]]; then
  read -p "Are you happy to continue with this configuration? [y/N] " -r
  if [[ ! $REPLY =~ ^[Yy] ]]; then
    echo "Aborting setup..."
    exit 0
  fi
fi

# ok no more questions

mkdir -p "$BUILD_DIR"
XDG_CONFIG_HOME="$HOME/.config"
SYSTEMD_USER_DIR="/usr/lib/systemd/user"
HYPR_CONF_DIR="$XDG_CONFIG_HOME/hypr"
mkdir -p "$HYPR_CONF_DIR"
HYPRLAND_LUA_CONF_FILE="$HYPR_CONF_DIR/hyprland.lua"
HYPRLAND_CONF_FILE="$HYPRLAND_LUA_CONF_FILE"
HYPR_BIND_TARGET_FILE="$HYPRLAND_LUA_CONF_FILE"
mkdir -p "$HOME/.local/bin"

lua_escape() {
  local VAL="$1"
  VAL=${VAL//\\/\\\\}
  VAL=${VAL//\"/\\\"}
  printf "%s" "$VAL"
}

set_lua_program() {
  local NAME="$1"
  local VALUE
  VALUE=$(lua_escape "$2")
  VALUE=${VALUE//&/\\&}
  sed -i -E "s|^(local[[:space:]]+${NAME}[[:space:]]*=[[:space:]]*).*|\\1\"$VALUE\"|" "$HYPRLAND_LUA_CONF_FILE"
}

merge_hyprdebian_lua_settings() {
  if [[ $THUNAR_SETUP == "true" ]]; then
    set_lua_program "fileManager" "thunar"
  fi
}

ensure_hyprland_default_lua_source() {
  local DEFAULT_LUA_SOURCE="$BUILD_DIR/Hyprland/example/hyprland.lua"
  if [ -f "$DEFAULT_LUA_SOURCE" ]; then
    return
  fi

  echo "Hyprland clone is missing example/hyprland.lua; recreating the default config locally..."
  mkdir -p "$(dirname "$DEFAULT_LUA_SOURCE")"

  if git -C "$BUILD_DIR/Hyprland" cat-file -e HEAD:example/hyprland.lua 2>/dev/null; then
    git -C "$BUILD_DIR/Hyprland" show HEAD:example/hyprland.lua >"$DEFAULT_LUA_SOURCE"
  elif [ -f /usr/share/hypr/hyprland.lua ]; then
    cp /usr/share/hypr/hyprland.lua "$DEFAULT_LUA_SOURCE"
  else
    echo "Error: Cannot find Hyprland's default Lua config in the clone or /usr/share/hypr/hyprland.lua."
    exit 1
  fi
}

prepare_hyprland_config() {
  ensure_hyprland_default_lua_source

  if [ -f "$HYPRLAND_LUA_CONF_FILE" ]; then
    HYPRLAND_CONF_FILE="$HYPRLAND_LUA_CONF_FILE"
    HYPR_BIND_TARGET_FILE="$HYPRLAND_LUA_CONF_FILE"
    merge_hyprdebian_lua_settings
    return
  fi

  echo "Creating $HYPRLAND_LUA_CONF_FILE from upstream Hyprland default config..."
  cp "$BUILD_DIR/Hyprland/example/hyprland.lua" "$HYPRLAND_LUA_CONF_FILE"

  HYPRLAND_CONF_FILE="$HYPRLAND_LUA_CONF_FILE"
  HYPR_BIND_TARGET_FILE="$HYPRLAND_LUA_CONF_FILE"
  merge_hyprdebian_lua_settings
}

append_hypr_config_if_missing() {
  local PATTERN="$1"
  if ! grep -qiF "$PATTERN" "$HYPR_BIND_TARGET_FILE"; then
    cat >>"$HYPR_BIND_TARGET_FILE"
  else
    cat >/dev/null
  fi
}

ensure_debian_13_apt_sources

apt_install \
  build-essential \
  ca-certificates \
  cmake \
  cmake-extras \
  curl \
  dpkg-dev \
  git \
  ninja-build \
  pkg-config

apt_install_backports \
  libxkbcommon0 \
  libxkbcommon-dev \
  libxkbcommon-x11-0 \
  libxkbcommon-x11-dev \
  libxkbregistry0 \
  wayland-protocols

ensure_gcc_15
export CC="${CC:-gcc-15}"
export CXX="${CXX:-g++-15}"
DEB_HOST_MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
export PKG_CONFIG_PATH="/usr/lib/$DEB_HOST_MULTIARCH/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"

apt_install \
  fontconfig \
  fonts-cantarell \
  fonts-font-awesome

fc-cache -fv

apt_install \
  adwaita-icon-theme \
  gsettings-desktop-schemas \
  libglib2.0-bin

apt_install \
  gnome-keyring \
  libpam-gnome-keyring \
  qt6-wayland \
  qtwayland5 \
  rtkit

UWSM_ENV_DIR="$XDG_CONFIG_HOME/uwsm"
if [ ! -d "$UWSM_ENV_DIR" ]; then
  mkdir -p "$UWSM_ENV_DIR"
fi
UWSM_ENV_FILE="$UWSM_ENV_DIR/env"
touch "$UWSM_ENV_FILE"
envs=(
  "export QT_AUTO_SCREEN_SCALE_FACTOR=1"
  "export QT_WAYLAND_DISABLE_WINDOWDECORATION=1"
  "export QT_QPA_PLATFORM=\"wayland;xcb\""
  "export QT_QPA_PLATFORMTHEME=qt6ct"
  "export ELECTRON_OZONE_PLATFORM_HINT=auto"
  "export XDG_PICTURES_DIR=\${HOME}/Pictures"
  "export HYPRSHOT_DIR=\${HOME}/Pictures/Screenshots"
  "export SSH_AUTH_SOCK=\${XDG_RUNTIME_DIR}/gcr/ssh"
)
echo "Checking environment variables in $UWSM_ENV_FILE..."
for LINE in "${envs[@]}"; do
  VARNAME=$(echo "$LINE" | sed -E 's/^export ([^= ]+)=.*/\1/')
  if ! grep -qF "$VARNAME" "$UWSM_ENV_FILE"; then
    echo "$LINE" >>"$UWSM_ENV_FILE"
    echo "  + Added missing $VARNAME"
  else
    echo "  . $VARNAME already set"
  fi
done
if [ "none" != "$THEME_PREF" ]; then
  echo "Setting up $THEME_PREF theme..."

  THEME_NAME="Adwaita"
  if [ "light" = "$THEME_PREF" ]; then
    GTK_THEME_VAL="$THEME_NAME"
    COLOR_SCHEME="default"
    PREFER_DARK=0
  else
    GTK_THEME_VAL="$THEME_NAME:dark"
    COLOR_SCHEME="prefer-dark"
    PREFER_DARK=1
  fi

  theme_envs=(
    "export GTK_THEME=$GTK_THEME_VAL"
    "export HYPRCURSOR_SIZE=24"
    "export HYPRCURSOR_THEME=$THEME_NAME"
    "export XCURSOR_SIZE=24"
    "export XCURSOR_THEME=$THEME_NAME"
  )
  for LINE in "${theme_envs[@]}"; do
    VARNAME=$(echo "$LINE" | sed -E 's/^export ([^= ]+)=.*/\1/')
    if grep -q "^export $VARNAME=" "$UWSM_ENV_FILE"; then
      sed -i "s|^export $VARNAME=.*|$LINE|" "$UWSM_ENV_FILE"
      echo " -+ Overwrote $VARNAME"
    else
      echo "$LINE" >>"$UWSM_ENV_FILE"
      echo "  + Added $VARNAME"
    fi
  done

  GTK3_SETTINGS_DIR="$XDG_CONFIG_HOME/gtk-3.0"
  GTK4_SETTINGS_DIR="$XDG_CONFIG_HOME/gtk-4.0"
  mkdir -p "$GTK3_SETTINGS_DIR" "$GTK4_SETTINGS_DIR"
  cat <<EOF >"$GTK4_SETTINGS_DIR/settings.ini"
[Settings]
gtk-application-prefer-dark-theme=$PREFER_DARK
gtk-theme-name=$GTK_THEME_VAL
gtk-icon-theme-name=$THEME_NAME
gtk-cursor-theme-name=$THEME_NAME
EOF
  cp "$GTK4_SETTINGS_DIR/settings.ini" "$GTK3_SETTINGS_DIR/settings.ini"

  dbus-run-session bash <<EOF
gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME"
gsettings set org.gnome.desktop.interface gtk-theme "$THEME_NAME"
gsettings set org.gnome.desktop.interface icon-theme "$THEME_NAME"
gsettings set org.gnome.desktop.interface cursor-theme "$THEME_NAME"
EOF
fi

if [[ $NVIDIA_SETUP == "true" ]]; then
  echo "Installing proprietary nvidia drivers"
  apt_install \
    firmware-misc-nonfree \
    linux-headers-amd64 \
    nvidia-driver \
    nvidia-vaapi-driver

  if ! grep -q "nvidia" "$UWSM_ENV_FILE"; then
    cat <<'EOF' >>"$UWSM_ENV_FILE"
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export NVD_BACKEND=direct
export MOZ_DISABLE_RDD_SANDBOX=1
EOF
  fi
fi

apt_install_backports cargo rustc
configure_user_cargo() {
  local USER_CARGO_HOME="$HOME/.cargo"
  local USER_CARGO_INSTALL_ROOT="$USER_CARGO_HOME"
  local CARGO_BIN_DIR

  if [ -z "${CARGO_HOME:-}" ] || { [ -e "$CARGO_HOME" ] && [ ! -w "$CARGO_HOME" ]; } || { [ ! -e "$CARGO_HOME" ] && [ ! -w "$(dirname "$CARGO_HOME")" ]; }; then
    if [ -n "${CARGO_HOME:-}" ] && [ "$CARGO_HOME" != "$USER_CARGO_HOME" ]; then
      echo "CARGO_HOME=$CARGO_HOME is not writable; using $USER_CARGO_HOME"
    fi
    export CARGO_HOME="$USER_CARGO_HOME"
  fi

  if [ -z "${CARGO_INSTALL_ROOT:-}" ] || { [ -e "$CARGO_INSTALL_ROOT" ] && [ ! -w "$CARGO_INSTALL_ROOT" ]; } || { [ ! -e "$CARGO_INSTALL_ROOT" ] && [ ! -w "$(dirname "$CARGO_INSTALL_ROOT")" ]; }; then
    if [ -n "${CARGO_INSTALL_ROOT:-}" ] && [ "$CARGO_INSTALL_ROOT" != "$USER_CARGO_INSTALL_ROOT" ]; then
      echo "CARGO_INSTALL_ROOT=$CARGO_INSTALL_ROOT is not writable; using $USER_CARGO_INSTALL_ROOT"
    fi
    export CARGO_INSTALL_ROOT="$USER_CARGO_INSTALL_ROOT"
  fi

  mkdir -p "$CARGO_HOME" "$CARGO_INSTALL_ROOT/bin"
  CARGO_BIN_DIR="$CARGO_INSTALL_ROOT/bin"
  case ":$PATH:" in
  *":$CARGO_BIN_DIR:"*) ;;
  *) export PATH="$CARGO_BIN_DIR:$PATH" ;;
  esac
}
configure_user_cargo

if ! grep -qF "$CARGO_INSTALL_ROOT/bin" "$HOME/.bashrc"; then
  cat <<EOF >>"$HOME/.bashrc"

if [ -d "$CARGO_INSTALL_ROOT/bin" ] ; then
PATH="$CARGO_INSTALL_ROOT/bin:\$PATH"
fi
EOF
fi

has_bluetooth() {
  modprobe -q btusb

  if [ -d /sys/class/bluetooth ] && [ -n "$(ls /sys/class/bluetooth)" ]; then
    return 0 # true
  fi

  return 1 # false
}
if has_bluetooth; then
  echo "Bluetooth hardware detected. Installing bluez and bluetui..."
  apt_install \
    bluez \
    libdbus-1-dev \
    libspa-0.2-bluetooth

  cargo install bluetui
fi

has_ethernet() {
  if ip link show | grep -q ' en'; then
    return 0 # true
  fi
  return 1 # false
}

has_wifi() {
  for IFACE in /sys/class/net/*; do
    if [ -d "$IFACE/wireless" ] || [ -d "$IFACE/phy80211" ]; then
      return 0 # true
    fi
  done
  return 1 # false
}
if has_wifi; then
  echo "Wi-Fi hardware detected. Installing wlctl..."
  cargo install wlctl
fi

has_battery() {
  if ls /sys/class/power_supply/BAT* 1>/dev/null 2>&1; then
    return 0 # true
  fi
  return 1 # false
}

apt_install \
  libclang-dev \
  libpipewire-0.3-dev

cargo install wiremix

install_hyprwm_package hyprwayland-scanner "@stable" \
  libpugixml-dev

install_hyprwm_package hyprutils "@stable" \
  libpixman-1-dev

install_hyprwm_package hyprland-protocols "main"

install_hyprwm_package hyprlang "@stable"

install_hyprwm_package hyprcursor "@stable" \
  libcairo2-dev \
  librsvg2-dev \
  libtomlplusplus-dev \
  libzip-dev

install_hyprwm_package hyprgraphics "@stable" \
  libdrm-dev \
  libgles2-mesa-dev \
  libheif-dev \
  libjpeg-dev \
  libjxl-dev \
  libmagic-dev \
  libspng-dev \
  libwebp-dev

install_hyprwm_package aquamarine "@stable" \
  hwdata \
  libdisplay-info-dev \
  libgbm-dev \
  libgles-dev \
  libinput-dev \
  libseat-dev \
  libwayland-dev \
  wayland-protocols

install_hyprwm_package hyprwire "@stable" \
  libabsl-dev

install_hyprwm_package hyprtoolkit "@stable" \
  libiniparser-dev

install_hyprwm_package hyprland-guiutils "@stable"

install_hyprwm_package hyprpolkitagent "@stable" \
  libpolkit-agent-1-dev \
  libpolkit-qt6-1-dev \
  qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts \
  qt6-base-dev \
  qt6-declarative-dev

XDG_RUNTIME_DIR="/run/user/$(id -u)" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" systemctl --user enable hyprpolkitagent.service

install_hyprwm_package xdg-desktop-portal-hyprland "@stable" \
  libpipewire-0.3-dev \
  libspa-0.2-dev \
  libsystemd-dev

mkdir -p "$XDG_CONFIG_HOME/xdg-desktop-portal"
if [ ! -f "$XDG_CONFIG_HOME/xdg-desktop-portal/portals.conf" ]; then
  cat <<'EOF' >"$XDG_CONFIG_HOME/xdg-desktop-portal/portals.conf"
[preferred]
default=hyprland;gtk
EOF
fi

install_hyprwm_package Hyprland "@stable" \
  glslang-dev \
  glslang-tools \
  libegl-dev \
  libglaze-dev \
  libliftoff-dev \
  liblua5.4-dev \
  libmuparser-dev \
  libopengl-dev \
  libpango1.0-dev \
  libre2-dev \
  libudev-dev \
  libwayland-dev \
  libxcb1-dev \
  libudis86-dev \
  libxcb-composite0-dev \
  libxcb-ewmh-dev \
  libxcb-errors-dev \
  libxcb-icccm4-dev \
  libxcb-render-util0-dev \
  libxcb-res0-dev \
  libxcb-xinput-dev \
  libxcb-xfixes0-dev \
  libxcursor-dev

prepare_hyprland_config

install_hyprwm_package hyprlauncher "@stable" \
  libqalculate-dev

install_hyprwm_package hyprshutdown "@stable"

if [[ $HYPRPAPER_SETUP == "true" ]]; then
  install_hyprwm_package hyprpaper "@stable"
  systemctl --user enable hyprpaper.service
fi

if [[ $HYPRLOCK_SETUP == "true" ]]; then
  install_hyprwm_package hyprlock "@stable" \
    libaudit-dev \
    libpam0g-dev \
    libsdbus-c++-dev

fi

if [[ "$HYPRIDLE_SETUP" == "true" ]] && [[ "$HYPRLOCK_SETUP" == "true" ]]; then
  install_hyprwm_package hypridle "@stable"
  HYPRIDLE_CONF_FILE="$HYPR_CONF_DIR/hypridle.conf"
  if [ ! -f "$HYPRIDLE_CONF_FILE" ]; then
    cat <<'EOF' >"$HYPRIDLE_CONF_FILE"
general {
  lock_cmd = pidof hyprlock || hyprlock
  before_sleep_cmd = loginctl lock-session
  after_sleep_cmd = hyprctl dispatch dpms on
}

listener {
  timeout = 300
  on-timeout = brightnessctl -s set 10
  on-resume = brightnessctl -r
}

listener {
  timeout = 330
  on-timeout = loginctl lock-session
}

listener {
  timeout = 350
  on-timeout = hyprctl dispatch dpms off
  on-resume = hyprctl dispatch dpms on
}

EOF
    if has_battery; then
      cat <<'EOF' >>"$HYPRIDLE_CONF_FILE"
listener {
  timeout = 600
  on-timeout = grep -q "Discharging" /sys/class/power_supply/BAT*/status && systemctl suspend
}
EOF
    else
      cat <<'EOF' >>"$HYPRIDLE_CONF_FILE"
listener {
  timeout = 600
  on-timeout = systemctl suspend
}
EOF
    fi
  fi
  systemctl --user enable hypridle.service
fi

if [ "none" != "$NOTIFICATION_DAEMON_PREF" ]; then
  echo "Setting up $NOTIFICATION_DAEMON_PREF notification daemon..."
  if [ "dunst" = "$NOTIFICATION_DAEMON_PREF" ]; then
    apt_install dunst
    DUNST_CONFIG_DIR="$XDG_CONFIG_HOME/dunst"
    mkdir -p "$DUNST_CONFIG_DIR"
    DUNST_CONFIG_FILE="$DUNST_CONFIG_DIR/dunstrc"

    if [ ! -f "$DUNST_CONFIG_FILE" ]; then
      cat <<'EOF' >"$DUNST_CONFIG_FILE"
[global]
    icon_theme = "Adwaita"
    enable_recursive_icon_lookup = true
EOF
    fi
    append_hypr_config_if_missing "Hyprdebian notifications (dunst)" <<'EOF'
-- Hyprdebian notifications (dunst)
hl.bind("SUPER + COMMA",         hl.dsp.exec_cmd("dunstctl close"))
hl.bind("SUPER + SHIFT + COMMA", hl.dsp.exec_cmd("dunstctl close-all"))
hl.bind("SUPER + CTRL + COMMA",  hl.dsp.exec_cmd("dunstctl history-pop"))
hl.bind("SUPER + ALT + COMMA",   hl.dsp.exec_cmd("dunstctl set-paused toggle && dunstctl is-paused | grep -q 'true' && notify-send -u critical \"Silenced notifications\" || notify-send \"Enabled notifications\""))

EOF
    systemctl --user enable dunst.service
  fi
  if [ "mako" = "$NOTIFICATION_DAEMON_PREF" ]; then
    apt_install mako-notifier
    MAKO_CONFIG_DIR="$XDG_CONFIG_HOME/mako"
    mkdir -p "$MAKO_CONFIG_DIR"
    MAKO_CONFIG_FILE="$MAKO_CONFIG_DIR/config"

    if [ ! -f "$MAKO_CONFIG_FILE" ]; then
      cat <<'EOF' >"$MAKO_CONFIG_FILE"
# Do Not Disturb mode
[mode=dnd]
invisible=1

# Allow critical notifications to bypass Do Not Disturb
[mode=dnd urgency=critical]
invisible=0
EOF
    fi
    append_hypr_config_if_missing "Hyprdebian notifications (mako)" <<'EOF'
-- Hyprdebian notifications (mako)
hl.bind("SUPER + COMMA",         hl.dsp.exec_cmd("makoctl dismiss"))
hl.bind("SUPER + SHIFT + COMMA", hl.dsp.exec_cmd("makoctl dismiss -a"))
hl.bind("SUPER + CTRL + COMMA",  hl.dsp.exec_cmd("makoctl restore"))
hl.bind("SUPER + ALT + COMMA",   hl.dsp.exec_cmd("makoctl mode -t dnd && makoctl mode | grep -q 'dnd' && notify-send -u critical \"Silenced notifications\" || notify-send \"Enabled notifications\""))

EOF
    systemctl --user enable mako.service
  fi
  if [ "swaync" = "$NOTIFICATION_DAEMON_PREF" ]; then
    apt_install sway-notification-center
    append_hypr_config_if_missing "Hyprdebian notifications (swaync)" <<'EOF'
-- Hyprdebian notifications (swaync)
hl.bind("SUPER + COMMA",         hl.dsp.exec_cmd("swaync-client --close-latest"))
hl.bind("SUPER + SHIFT + COMMA", hl.dsp.exec_cmd("swaync-client --close-all"))
hl.bind("SUPER + CTRL + COMMA",  hl.dsp.exec_cmd("swaync-client --toggle-panel"))
hl.bind("SUPER + ALT + COMMA",   hl.dsp.exec_cmd("swaync-client --toggle-dnd && swaync-client --get-dnd | grep -q 'true' && notify-send \"Silenced notifications\" || notify-send \"Enabled notifications\""))

EOF
    systemctl --user enable swaync.service
  fi
fi

if [[ $HYPRSHOT_SETUP == "true" ]]; then
  apt_install \
    grim \
    slurp

  if [ ! -f "$HOME/.local/bin/hyprshot" ]; then
    # see XDG_PICTURES_DIR / HYPRSHOT_DIR envs
    mkdir -p "$HOME/Pictures/Screenshots"
    curl -o "$HOME/.local/bin/hyprshot" https://raw.githubusercontent.com/Gustash/Hyprshot/refs/heads/main/hyprshot
    chmod 755 "$HOME/.local/bin/hyprshot"
  fi
  append_hypr_config_if_missing "Hyprdebian screenshots" <<'EOF'
-- Hyprdebian screenshots
local hyprshot = os.getenv("HOME") .. "/.local/bin/hyprshot"
hl.bind("PRINT",         hl.dsp.exec_cmd(hyprshot .. " -m region"))
hl.bind("ALT + PRINT",   hl.dsp.exec_cmd(hyprshot .. " -m window"))
hl.bind("SHIFT + PRINT", hl.dsp.exec_cmd(hyprshot .. " -m output"))

EOF
fi

if [[ $SWAYOSD_SETUP == "true" ]]; then
  apt_install \
    brightnessctl \
    playerctl \
    swayosd

  SWAY_UNIT_FILE="$SYSTEMD_USER_DIR/swayosd.service"
  if [ ! -f "$SWAY_UNIT_FILE" ]; then
    sudo tee "$SWAY_UNIT_FILE" >/dev/null <<'EOF'
[Unit]
Description=Volume/Backlight OSD Indicator
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/swayosd-server
Restart=on-failure

[Install]
WantedBy=graphical-session.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable swayosd.service
    # brightnessctl is still expecting video group membership
    sudo usermod -aG video "$USER"
  fi

  append_hypr_config_if_missing "Hyprdebian SwayOSD binds" <<'EOF'
-- Hyprdebian SwayOSD binds
-- The upstream default config already binds the XF86 multimedia keys.
-- To use SwayOSD instead, replace the upstream XF86 binds with these lines:
-- hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("swayosd-client --playerctl next"),        { locked = true })
-- hl.bind("XF86AudioPause",       hl.dsp.exec_cmd("swayosd-client --playerctl play-pause"),  { locked = true })
-- hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("swayosd-client --playerctl play-pause"),  { locked = true })
-- hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("swayosd-client --playerctl previous"),    { locked = true })
-- hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("swayosd-client --output-volume raise"),   { locked = true, repeating = true })
-- hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("swayosd-client --output-volume lower"),   { locked = true, repeating = true })
-- hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"), { locked = true })
-- hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("swayosd-client --input-volume mute-toggle"),  { locked = true })
-- hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("swayosd-client --brightness raise"),      { locked = true, repeating = true })
-- hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("swayosd-client --brightness lower"),      { locked = true, repeating = true })

EOF
fi

if [[ $THUNAR_SETUP == "true" ]]; then
  apt_install \
    eject \
    ffmpegthumbnailer \
    gvfs \
    gvfs-backends \
    gvfs-fuse \
    thunar \
    thunar-archive-plugin \
    thunar-volman \
    tumbler

fi

apt_install \
  alsa-ucm-conf \
  alsa-utils \
  at-spi2-core \
  kitty \
  libmtp-runtime \
  libnotify-bin \
  libspa-0.2-libcamera \
  pipewire \
  pipewire-audio-client-libraries \
  pipewire-pulse \
  upower \
  usbutils \
  wireplumber \
  wl-clipboard \
  xdg-desktop-portal \
  xdg-desktop-portal-gtk \
  xwayland

if [[ $WAYBAR_SETUP == "true" ]]; then
  apt_install \
    waybar \
    wlogout

  WAYBAR_CONFIG_DIR="$XDG_CONFIG_HOME/waybar"
  mkdir -p "$WAYBAR_CONFIG_DIR"

  MODULES_RIGHT='"pulseaudio"'
  DYNAMIC_CONFIGS=""

  if has_wifi; then
    MODULES_RIGHT+=', "network#wifi"'
    DYNAMIC_CONFIGS+=$(
      cat <<'EOF'
    "network#wifi": {
        "interface": "wl*",
        "format-wifi": "{essid} ({signalStrength}%) ",
        "tooltip-format": "{ifname} via {gwaddr} ",
        "format-linked": "{ifname} (No IP) ",
        "format-disconnected": "Disconnected ⚠",
        "on-click": "pidof wlctl >/dev/null || hyprctl dispatch exec \"[float; size (monitor_w*0.9) (monitor_h*0.9); center] kitty -e wlctl\""
    },
EOF
    )
    DYNAMIC_CONFIGS+=$'\n'
  fi

  if has_ethernet; then
    MODULES_RIGHT+=', "network#ethernet"'
    DYNAMIC_CONFIGS+=$(
      cat <<'EOF'
    "network#ethernet": {
        "interface": "en*",
        "format-ethernet": "{ipaddr}/{cidr} ",
        "tooltip-format": "{ifname} via {gwaddr} ",
        "format-linked": "{ifname} (No IP) ",
        "format-disconnected": "Disconnected ⚠",
        "on-click": "pidof nmtui >/dev/null || hyprctl dispatch exec \"[float; size (monitor_w*0.9) (monitor_h*0.9); center] kitty -e nmtui\""
    },
EOF
    )
    DYNAMIC_CONFIGS+=$'\n'
  fi

  if has_bluetooth; then
    MODULES_RIGHT+=', "bluetooth"'
    DYNAMIC_CONFIGS+=$(
      cat <<'EOF'
    "bluetooth": {
        "format": " {status}",
        "format-connected": " {device_alias}",
        "on-click": "pidof bluetui >/dev/null || hyprctl dispatch exec \"[float; size (monitor_w*0.9) (monitor_h*0.9); center] kitty -e bluetui\""
    },
EOF
    )
    DYNAMIC_CONFIGS+=$'\n'
  fi

  MODULES_RIGHT+=', "clock"'

  if has_battery; then
    MODULES_RIGHT+=', "battery"'
    DYNAMIC_CONFIGS+=$(
      cat <<'EOF'
    "battery": {
        "states": {
            "warning": 30,
            "critical": 15
        },
        "format": "{capacity}% {icon}",
        "format-full": "{capacity}% {icon}",
        "format-charging": "{capacity}% ",
        "format-plugged": "{capacity}% ",
        "format-alt": "{time} {icon}",
        "format-icons": ["", "", "", "", ""]
    },
EOF
    )
    DYNAMIC_CONFIGS+=$'\n'
  fi

  MODULES_RIGHT+=', "custom/power"'

  if [ ! -f "$WAYBAR_CONFIG_DIR/config.jsonc" ]; then
    cat <<EOF >"$WAYBAR_CONFIG_DIR/config.jsonc"
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,
    "modules-left": ["hyprland/workspaces", "hyprland/submap"],
    "modules-center": ["hyprland/window"],
    "modules-right": [$MODULES_RIGHT],
    "hyprland/workspaces": {
        "format": "{name}",
        "disable-scroll": true,
        "all-outputs": true
    },
    "hyprland/window": {
        "max-length": 50
    },
    "pulseaudio": {
        "format": "{volume}% {icon} {format_source}",
        "format-bluetooth": "{volume}% {icon} {format_source}",
        "format-bluetooth-muted": " {icon} {format_source}",
        "format-muted": " {format_source}",
        "format-source": "{volume}% ",
        "format-source-muted": "",
        "format-icons": {
            "headphone": "",
            "hands-free": "",
            "headset": "",
            "phone": "",
            "portable": "",
            "car": "",
            "default": ["", "", ""]
        },
        "on-click": "pidof wiremix >/dev/null || hyprctl dispatch exec \"[float; size (monitor_w*0.9) (monitor_h*0.9); center] kitty -e wiremix\""
    },
    "clock": {
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>",
        "format-alt": "{:%Y-%m-%d}"
    },
$DYNAMIC_CONFIGS
    "custom/power": {
        "format": " ",
        "tooltip": false,
        "on-click": "wlogout"
    }
}
EOF
  fi

  if [ ! -f "$WAYBAR_CONFIG_DIR/style.css" ]; then
    curl -o "$WAYBAR_CONFIG_DIR/style.css" https://raw.githubusercontent.com/Alexays/Waybar/refs/heads/master/resources/style.css
  fi
fi

if [[ $TUIGREET_SETUP == "true" ]]; then
  apt_install_backports uwsm
  apt_install \
    greetd \
    tuigreet

  if [[ -f /etc/greetd/config.toml && ! -f /etc/greetd/config.toml.original ]]; then
    sudo mv /etc/greetd/config.toml /etc/greetd/config.toml.original
    sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 7

[default_session]
user = "_greetd"
command = "tuigreet --time --asterisks --remember --cmd 'uwsm start hyprland-uwsm.desktop'"
EOF
  fi
  sudo systemctl enable greetd.service
  sudo systemctl set-default graphical.target

  echo "We have set up tuigreet greetd uwsm to start-hyprland"
fi

apt_install network-manager
sudo systemctl enable NetworkManager.service
sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge networkd-dispatcher || true
if command -v netplan >/dev/null 2>&1 && [ -d /etc/netplan ]; then
  if [ -f /etc/netplan/00-installer-config.yaml ]; then
    sudo mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.disabled
  fi
  if [[ ! -f /etc/netplan/01-network-manager-all.yaml ]]; then
    sudo tee /etc/netplan/01-network-manager-all.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
    sudo chmod 600 /etc/netplan/01-network-manager-all.yaml
    sudo netplan generate
    sudo netplan apply
  fi
fi
# We don't want to wait for network on boot
sudo systemctl disable NetworkManager-wait-online.service || true
sudo systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
sudo systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

cat <<EOF

-------------------------
Hyprdebian setup complete!
-------------------------

EOF
if [ ${#UPGRADES[@]} -gt 0 ]; then
  echo "Upgrades"
  echo "-------------------------"
  for upgrade in "${UPGRADES[@]}"; do
    echo "$upgrade"
  done
  echo "-------------------------"
  echo
fi
cat <<EOF
The Hyprland config at "$HYPRLAND_CONF_FILE" is based on the upstream default config when the script creates it.
When thunar is selected, the generated Lua config uses thunar instead of hyprland's default dolphin.
If you prefer to swap out any components you can install replacements and re-configure "$HYPRLAND_CONF_FILE"
If you want to set environmental variables see "$UWSM_ENV_FILE"
If you are not using greetd / tuigreet from this script, I would highly recommend using another uwsm based desktop manager.
A few helpful binds have been added directly to "$HYPR_BIND_TARGET_FILE"

Please reboot to start using Hyprland.

After you get into Hyprland check out the following commands:

- wiremix (audio)
- nmtui (network)
EOF
if has_wifi; then
  cat <<'EOF'
- wlctl (wifi)
EOF
fi
if has_bluetooth; then
  cat <<'EOF'
- bluetui (bluetooth)
EOF
fi
if [[ $THUNAR_SETUP == "true" ]]; then
  cat <<'EOF'
- thunar (file explorer)
EOF
fi
echo
if [[ $NVIDIA_SETUP == "true" ]]; then
  cat <<'EOF'
We've installed proprietary nvidia drivers
and added some configuration for you (see ~/.config/uwsm/env)

EOF
fi
if ! has_desktop_manager && [[ $TUIGREET_SETUP != "true" ]]; then
  cat <<'EOF'
We didn't install tuigreet for you.
You should start Hyprland with uwsm for all environmental variables and user services to work properly.

EOF
fi
cat <<EOF
You should have a look at your config in $XDG_CONFIG_HOME to start your ricing journey.
This script will not overwrite any config changes you make, you can run it multiple times to upgrade hyprland.

-------------------------
EOF
