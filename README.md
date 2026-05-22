# Hyprdebian

`debian13_hyprland_setup.sh` is a Debian 13 installer and source builder for Hyprland and a practical Hyprland desktop stack. It installs Debian packages, enables the Debian repositories needed by the build, clones Hyprland projects under a build directory, builds them with CMake and Ninja, installs them into `/usr`, and creates user-level configuration for Hyprland, UWSM, optional desktop services, and selected helper tools.

The script is designed for Debian 13 Trixie. It is not a generic Ubuntu, Debian testing, or Debian unstable installer.

## Scope

The script handles:

- Debian 13 validation before any setup work continues.
- Debian `contrib`, `non-free`, `non-free-firmware`, and `trixie-backports` apt source setup.
- GCC 15 setup from Debian sid with low-priority pinning when GCC 15 is not already available.
- Hyprland and related `hyprwm` projects built from source.
- Rust CLI helpers installed with `cargo`.
- UWSM environment setup.
- Theme, cursor, and GTK settings.
- Optional Nvidia proprietary driver setup when Nvidia hardware is detected.
- Optional notification daemon setup.
- Optional Hyprland companion tools such as hyprpaper, hyprlock, hypridle, hyprshot, SwayOSD, Waybar, Thunar, and tuigreet.
- NetworkManager setup for a desktop-oriented networking flow.
- Hyprland Lua config creation from the upstream default config, with script-selected settings merged into that config.

The script intentionally does not manage every possible Hyprland preference. It creates a working baseline and avoids overwriting existing user configuration files when those files already exist.

## Target Platform

Supported target:

- Debian GNU/Linux 13, codename `trixie`

The script checks `/etc/os-release` and exits unless it detects Debian 13 or the `trixie` codename.

Unsupported targets:

- Ubuntu
- Debian 12 Bookworm
- Debian testing after Trixie
- Debian unstable as the base OS
- Fedora, Arch, NixOS, openSUSE, or other distributions

Debian sid is only added temporarily and pinned at low priority so the script can install GCC 15 if required. Sid is disabled again after the GCC install attempt.

## Important Warning

This is a system-changing installer. It uses `sudo` to install packages, write apt source files, install built projects into `/usr`, enable systemd user services, enable system services, and alter parts of the networking/login-manager setup.

Review the script before running it on a machine you care about.

The script may:

- Add files under `/etc/apt/sources.list.d`.
- Add files under `/etc/apt/preferences.d`.
- Install and remove apt packages.
- Install built Hyprland components into `/usr`.
- Run `ldconfig`.
- Enable user services such as `hyprpolkitagent.service`, `hyprpaper.service`, `hypridle.service`, and notification services.
- Enable `NetworkManager.service`.
- Disable boot network wait services.
- Optionally enable `greetd.service`.
- Optionally set the system default target to `graphical.target`.
- Optionally move `/etc/greetd/config.toml` to `/etc/greetd/config.toml.original`.
- Optionally adjust netplan files if the netplan package exists on the system.
- Optionally add the current user to the `video` group for brightness control.

## Quick Start

Run as your normal user, not as root:

```bash
./debian13_hyprland_setup.sh
```

The script will prompt for optional components, print the selected setup environment, and ask for confirmation before making the main changes.

Do not run it with `sudo`:

```bash
sudo ./debian13_hyprland_setup.sh
```

The script exits if it is run directly as the root account. It asks for sudo authentication when privileged actions are needed.

## Non-Interactive Usage

The script can be run non-interactively by exporting the supported variables before execution and setting `DISABLE_CONFIRM=true`.

Example of the complete installation:

```bash
BUILD_DIR="$HOME/hyprdebian" \
DISABLE_CONFIRM=true \
HYPRIDLE_SETUP=true \
HYPRLOCK_SETUP=true \
HYPRPAPER_SETUP=true \
HYPRSHOT_SETUP=true \
NOTIFICATION_DAEMON_PREF=swaync \
NVIDIA_SETUP=false \
SWAYOSD_SETUP=true \
THEME_PREF=dark \
THUNAR_SETUP=true \
TUIGREET_SETUP=true \
WAYBAR_SETUP=true \
./debian13_hyprland_setup.sh
```

Example minimal installation:

```bash
BUILD_DIR="$HOME/hyprdebian" \
DISABLE_CONFIRM=true \
HYPRIDLE_SETUP=false \
HYPRLOCK_SETUP=false \
HYPRPAPER_SETUP=false \
HYPRSHOT_SETUP=false \
NOTIFICATION_DAEMON_PREF=none \
NVIDIA_SETUP=false \
SWAYOSD_SETUP=false \
THEME_PREF=none \
THUNAR_SETUP=false \
TUIGREET_SETUP=false \
WAYBAR_SETUP=false \
./debian13_hyprland_setup.sh
```

## Configuration Variables

`BUILD_DIR`

Directory used for source clones and builds. Defaults to:

```bash
$HOME/hyprdebian
```

`DISABLE_CONFIRM`

Set to `true` to skip the final interactive confirmation. Defaults to confirmation enabled.

`HYPRIDLE_SETUP`

Set to `true` to build and configure hypridle. A minimal `~/.config/hypr/hypridle.conf` is created only if one does not already exist. hypridle is only installed when hyprlock is also selected.

`HYPRLOCK_SETUP`

Set to `true` to build hyprlock. The script installs hyprlock but does not generate a hyprlock theme.

`HYPRPAPER_SETUP`

Set to `true` to build hyprpaper and enable `hyprpaper.service`.

`HYPRSHOT_SETUP`

Set to `true` to install the Hyprshot script into `~/.local/bin/hyprshot`, install `grim` and `slurp`, and append Lua screenshot binds to the generated Hyprland config.

`NOTIFICATION_DAEMON_PREF`

Selects the notification daemon. Supported values:

- `dunst`
- `mako`
- `swaync`
- `none`

When a daemon is selected, the script installs it, creates a minimal config where appropriate, enables its user service, and appends Lua notification binds to the Hyprland config.

`NVIDIA_SETUP`

Set to `true` to install Debian Nvidia packages. This prompt only appears automatically when Nvidia hardware is detected with `lspci`.

`SWAYOSD_SETUP`

Set to `true` to install `swayosd`, `brightnessctl`, and `playerctl`, create a systemd user service if Debian does not provide one, and append commented Lua SwayOSD bind examples to the Hyprland config.

`THEME_PREF`

Controls default Adwaita theme setup. Supported values:

- `dark`
- `light`
- `none`

When enabled, the script writes GTK 3 and GTK 4 settings, adds UWSM theme/cursor environment variables, and applies GNOME interface settings through `gsettings`.

`THUNAR_SETUP`

Set to `true` to install Thunar and related desktop integration packages. When selected, the generated Hyprland Lua config is changed to use:

```lua
local fileManager = "thunar"
```

`TUIGREET_SETUP`

Set to `true` to install and configure greetd with tuigreet and UWSM. This is only offered when the script does not detect an existing login/display manager and `tuigreet` is not already installed.

`WAYBAR_SETUP`

Set to `true` to install Waybar and wlogout, create a minimal Waybar config if missing, and include dynamic modules based on detected Wi-Fi, Ethernet, Bluetooth, and battery hardware.

## Built Hyprland Projects

The script builds these projects from `https://github.com/hyprwm`:

- `hyprwayland-scanner`
- `hyprutils`
- `hyprland-protocols`
- `hyprlang`
- `hyprcursor`
- `hyprgraphics`
- `aquamarine`
- `hyprwire`
- `hyprtoolkit`
- `hyprland-guiutils`
- `hyprpolkitagent`
- `xdg-desktop-portal-hyprland`
- `Hyprland`
- `hyprlauncher`
- `hyprshutdown`

Optional projects:

- `hyprpaper`
- `hyprlock`
- `hypridle`

Most projects are checked out at the latest tag visible in the local clone after fetching tags. `hyprland-protocols` is checked out from `main`.

The script prints an upgrade summary at the end if a project moved from one version/ref to another during the run.

## Build Behavior

Each Hyprland project is cloned under:

```bash
$BUILD_DIR/<project>
```

For existing clones, the script fetches tags and updates before selecting the requested ref. If fetching fails, it warns and continues with the local checkout when possible.

For fresh clones, the script skips a redundant fetch because the clone already has the initial remote data.

Projects are configured with:

```bash
cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
```

The installation libdir is set from `DEB_HOST_MULTIARCH` when available. The compiler is set to GCC 15 and G++ 15 unless `CC` or `CXX` are already exported.

The build parallelism is based on physical CPU cores:

```bash
physical cores minus one
```

with a minimum of one build thread.

## Installed Apt Sources

The script ensures Debian non-free components are available by writing:

```text
/etc/apt/sources.list.d/hyprdebian-nonfree.sources
```

The script ensures backports are available by writing:

```text
/etc/apt/sources.list.d/hyprdebian-backports.sources
```

When GCC 15 is missing, it temporarily writes:

```text
/etc/apt/sources.list.d/hyprdebian-sid.sources
/etc/apt/preferences.d/99-hyprdebian-pin-sid
```

The sid source is pinned at priority `100` and disabled after the GCC install attempt.

## Core Apt Packages

Core build and runtime packages include:

- `build-essential`
- `ca-certificates`
- `cmake`
- `cmake-extras`
- `curl`
- `dpkg-dev`
- `git`
- `ninja-build`
- `pkg-config`
- `fontconfig`
- `fonts-cantarell`
- `fonts-font-awesome`
- `adwaita-icon-theme`
- `gsettings-desktop-schemas`
- `libglib2.0-bin`
- `gnome-keyring`
- `libpam-gnome-keyring`
- `qt6-wayland`
- `qtwayland5`
- `rtkit`
- `cargo`
- `rustc`
- `libclang-dev`
- `libpipewire-0.3-dev`

The script installs selected XKB packages from `trixie-backports` to keep runtime and development package versions aligned:

- `libxkbcommon0`
- `libxkbcommon-dev`
- `libxkbcommon-x11-0`
- `libxkbcommon-x11-dev`
- `libxkbregistry0`
- `wayland-protocols`

## Hyprland Build Dependencies

Dependencies are installed near the project that requires them. The script currently includes dependencies such as:

- `libpugixml-dev`
- `libpixman-1-dev`
- `libcairo2-dev`
- `librsvg2-dev`
- `libtomlplusplus-dev`
- `libzip-dev`
- `libdrm-dev`
- `libgles2-mesa-dev`
- `libheif-dev`
- `libjpeg-dev`
- `libjxl-dev`
- `libmagic-dev`
- `libspng-dev`
- `libwebp-dev`
- `hwdata`
- `libdisplay-info-dev`
- `libgbm-dev`
- `libgles-dev`
- `libinput-dev`
- `libseat-dev`
- `libwayland-dev`
- `libabsl-dev`
- `libiniparser-dev`
- `libpolkit-agent-1-dev`
- `libpolkit-qt6-1-dev`
- `qml6-module-qtquick-controls`
- `qml6-module-qtquick-layouts`
- `qt6-base-dev`
- `qt6-declarative-dev`
- `libspa-0.2-dev`
- `libsystemd-dev`
- `glslang-dev`
- `glslang-tools`
- `libegl-dev`
- `libglaze-dev`
- `libliftoff-dev`
- `liblua5.4-dev`
- `libmuparser-dev`
- `libopengl-dev`
- `libpango1.0-dev`
- `libre2-dev`
- `libudev-dev`
- `libxcb1-dev`
- `libudis86-dev`
- `libxcb-composite0-dev`
- `libxcb-ewmh-dev`
- `libxcb-errors-dev`
- `libxcb-icccm4-dev`
- `libxcb-render-util0-dev`
- `libxcb-res0-dev`
- `libxcb-xinput-dev`
- `libxcb-xfixes0-dev`
- `libxcursor-dev`

## Rust Tools

The script installs:

- `wiremix`

When matching hardware is detected, it may also install:

- `bluetui`
- `wlctl`

Cargo install behavior is configured defensively. If `CARGO_HOME` or `CARGO_INSTALL_ROOT` points to an unwritable location such as `/usr/local/cargo`, the script falls back to the user's:

```bash
$HOME/.cargo
```

The script also adds the Cargo bin directory to `PATH` in `~/.bashrc` when needed.

## Generated User Config

The main Hyprland config created by the script is:

```bash
~/.config/hypr/hyprland.lua
```

The script no longer creates or relies on a separate `hyprdebian-binds.conf` file.

The generated Lua config is based on Hyprland's upstream default Lua config:

```bash
$BUILD_DIR/Hyprland/example/hyprland.lua
```

If that file is missing from the working tree, the script attempts to recreate it from the Hyprland git checkout:

```bash
git -C "$BUILD_DIR/Hyprland" show HEAD:example/hyprland.lua
```

If the git object is unavailable, it falls back to:

```bash
/usr/share/hypr/hyprland.lua
```

If none of those sources exist, the script exits with an error instead of creating an incomplete config.

When Thunar is selected, the script updates the Lua config so Hyprland's file manager variable uses `thunar`.

Additional Lua binds can be appended for:

- Notification controls
- Screenshots through Hyprshot
- SwayOSD examples

The append helper checks for a marker string before writing, so rerunning the script should not duplicate these generated blocks.

## Other Generated Config Files

The script may create:

```bash
~/.config/uwsm/env
~/.config/gtk-3.0/settings.ini
~/.config/gtk-4.0/settings.ini
~/.config/xdg-desktop-portal/portals.conf
~/.config/hypr/hypridle.conf
~/.config/dunst/dunstrc
~/.config/mako/config
~/.config/waybar/config.jsonc
~/.config/waybar/style.css
```

Most files are only created when missing. Existing user config is generally left in place.

## UWSM Environment

The script writes environment variables to:

```bash
~/.config/uwsm/env
```

Base variables include:

- `QT_AUTO_SCREEN_SCALE_FACTOR`
- `QT_WAYLAND_DISABLE_WINDOWDECORATION`
- `QT_QPA_PLATFORM`
- `QT_QPA_PLATFORMTHEME`
- `ELECTRON_OZONE_PLATFORM_HINT`
- `XDG_PICTURES_DIR`
- `HYPRSHOT_DIR`
- `SSH_AUTH_SOCK`

Theme setup may add or update:

- `GTK_THEME`
- `HYPRCURSOR_SIZE`
- `HYPRCURSOR_THEME`
- `XCURSOR_SIZE`
- `XCURSOR_THEME`

Nvidia setup may add:

- `LIBVA_DRIVER_NAME`
- `__GLX_VENDOR_LIBRARY_NAME`
- `NVD_BACKEND`
- `MOZ_DISABLE_RDD_SANDBOX`

## Login Manager Behavior

The script checks for common enabled or active display managers:

- `gdm.service`
- `gdm3.service`
- `greetd.service`
- `lightdm.service`
- `lxdm.service`
- `ly.service`
- `sddm.service`
- `slim.service`
- `xdm.service`

If an existing display manager is detected, the script does not prompt to install tuigreet and prints the detected service list.

If no display manager is detected, the script can install:

- `uwsm`
- `greetd`
- `tuigreet`

It configures greetd to run:

```bash
tuigreet --time --asterisks --remember --cmd 'uwsm start hyprland-uwsm.desktop'
```

## Network Behavior

The script installs and enables NetworkManager:

```bash
NetworkManager.service
```

It removes `networkd-dispatcher` if present, disables network wait services, and masks `systemd-networkd-wait-online.service` where possible.

If netplan is installed and `/etc/netplan` exists, it may:

- Move `/etc/netplan/00-installer-config.yaml` to `/etc/netplan/00-installer-config.yaml.disabled`.
- Create `/etc/netplan/01-network-manager-all.yaml` if missing.
- Run `netplan generate`.
- Run `netplan apply`.

## Optional Component Details

### hyprpaper

Builds and installs `hyprpaper`, then enables:

```bash
hyprpaper.service
```

No wallpaper config is generated.

### hyprlock

Builds and installs `hyprlock`.

No lock screen theme is generated.

### hypridle

Requires hyprlock to be selected. Creates `~/.config/hypr/hypridle.conf` if missing.

The generated config:

- Locks through `hyprlock`.
- Dims brightness before lock.
- Locks the session.
- Turns DPMS off.
- Suspends later.
- Uses battery-aware suspend logic when a battery is detected.

### hyprshot

Installs `grim`, `slurp`, and the Hyprshot script. Adds Lua binds:

- `PRINT` for region screenshot
- `ALT + PRINT` for window screenshot
- `SHIFT + PRINT` for output screenshot

### SwayOSD

Installs `brightnessctl`, `playerctl`, and `swayosd`.

The script adds commented Lua examples for multimedia keys because the upstream Hyprland default config already binds the XF86 keys. To use SwayOSD for those keys, remove or replace the upstream default XF86 binds in `hyprland.lua`.

### Thunar

Installs:

- `eject`
- `ffmpegthumbnailer`
- `gvfs`
- `gvfs-backends`
- `gvfs-fuse`
- `thunar`
- `thunar-archive-plugin`
- `thunar-volman`
- `tumbler`

The generated Hyprland Lua config uses Thunar as the file manager when this option is selected.

### Waybar

Installs:

- `waybar`
- `wlogout`

Creates `~/.config/waybar/config.jsonc` if missing.

The generated config always includes:

- Hyprland workspaces
- Hyprland submap
- Hyprland window title
- PulseAudio module
- Clock
- Power button through `wlogout`

It conditionally adds:

- Wi-Fi module when Wi-Fi hardware is detected
- Ethernet module when Ethernet is detected
- Bluetooth module when Bluetooth is detected
- Battery module when a battery is detected

If `~/.config/waybar/style.css` is missing, the script downloads Waybar's upstream example stylesheet.

### Notification Daemons

For `dunst`, the script installs `dunst`, creates a small `dunstrc` if missing, enables `dunst.service`, and appends Lua notification binds.

For `mako`, the script installs `mako-notifier`, creates a minimal config with a Do Not Disturb mode if missing, enables `mako.service`, and appends Lua notification binds.

For `swaync`, the script installs `sway-notification-center`, enables `swaync.service`, and appends Lua notification binds.

## Idempotency and Reruns

The script is intended to be rerunnable.

On rerun the script should:

- Reuse existing clones under `BUILD_DIR`.
- Fetch updates where possible.
- Keep existing user config files unless a specific merge/update is implemented.
- Avoid duplicate generated bind blocks by checking for marker strings.
- Rebuild and reinstall Hyprland projects when refs change.
- Use existing generated configs when present.

It still performs package installs and source builds on rerun, so it is not a no-op.

## Troubleshooting

### `gsettings: command not found`

The script installs `libglib2.0-bin`, which provides `gsettings`.

### `Package 'hwdata', required by 'virtual:world', not found`

Aquamarine's build can require `hwdata` through pkg-config dependency resolution. The script includes `hwdata` in the Aquamarine dependency list.

### `libxkbcommon` or `libxkbregistry` version conflicts

The script installs the relevant XKB runtime and development packages from `trixie-backports` together so the versions stay aligned:

- `libxkbcommon0`
- `libxkbcommon-dev`
- `libxkbcommon-x11-0`
- `libxkbcommon-x11-dev`
- `libxkbregistry0`

### Cargo permission errors under `/usr/local/cargo`

If inherited Cargo environment variables point to unwritable paths, the script falls back to `~/.cargo` for both `CARGO_HOME` and `CARGO_INSTALL_ROOT`.

### Git clone appears hung after receiving objects

The script now skips a redundant fetch immediately after a fresh clone. Existing clones still fetch updates, but fetch failures are reported as warnings, and the script continues with the local checkout when possible.

### Qt QML plugin CMake warnings

Some Qt QML plugin warnings can appear while building `hyprpolkitagent`. They are warnings from Qt/CMake integration and do not necessarily indicate a failed installation. Check the final build command exit status before treating them as fatal.

### Existing `hyprland.conf`

This installer's generated Hyprland target is `~/.config/hypr/hyprland.lua`. An old `~/.config/hypr/hyprland.conf` may still exist from previous experiments or manual setup, but it is not the target generated by the current script.

## Development Checks

Before committing script changes, run:

```bash
bash -n debian13_hyprland_setup.sh
shellcheck debian13_hyprland_setup.sh
```

The script should pass both checks.

## Repository Contents

Expected tracked files:

- `debian13_hyprland_setup.sh`
- `README.md`

The source/build checkout directory `hyprdebian/` should not be committed.

## Commit Style

Use the conventional commit style for maintenance changes. Example:

```text
chore: document Debian 13 Hyprland builder
```
