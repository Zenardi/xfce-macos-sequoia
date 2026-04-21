#!/usr/bin/env bash
# =============================================================================
# install.sh — XFCE macOS Theme Installer
#
# Transforms a fresh CachyOS/Arch XFCE desktop into a macOS Sequoia look-alike.
# Installs: WhiteSur GTK theme, WhiteSur icons, WhiteSur cursors, Inter/SF Pro
# fonts, macOS Sequoia wallpaper, Plank dock, and configures XFCE settings.
#
# Usage:
#   ./install.sh [OPTIONS]
#
# Options:
#   -d, --dark       Use dark variant (default: light)
#   -l, --light      Use light variant (default)
#   -n, --dry-run    Show what would be done without making changes
#   -f, --force      Re-install even if already installed
#   -h, --help       Show this help message
#
# Requirements: CachyOS / Arch Linux with XFCE, internet connection
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}▶ $*${RESET}"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
VARIANT="light"          # light | dark
DRY_RUN=false
FORCE=false

# ── Paths ─────────────────────────────────────────────────────────────────────
THEMES_DIR="$HOME/.themes"
ICONS_DIR="$HOME/.icons"
FONTS_DIR="$HOME/.local/share/fonts"
WALLPAPER_DIR="$HOME/.local/share/wallpapers/macos-sequoia"
STATE_FILE="$HOME/.local/share/xfce-macos-theme/.installed"
BACKUP_DIR="$HOME/.local/share/xfce-macos-theme/backup"
TMP_DIR="$(mktemp -d /tmp/xfce-macos-theme.XXXXXX)"

# ── Upstream sources ──────────────────────────────────────────────────────────
GTK_THEME_REPO="https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
ICON_THEME_REPO="https://github.com/vinceliuice/WhiteSur-icon-theme.git"
CURSOR_THEME_REPO="https://github.com/vinceliuice/WhiteSur-cursors.git"

# macOS Sequoia wallpaper (public mirror)
WALLPAPER_URL="https://github.com/dreamer-shan/macOS-Sequoia-Wallpapers/raw/main/Sequoia%20Light.jpg"
WALLPAPER_DARK_URL="https://github.com/dreamer-shan/macOS-Sequoia-Wallpapers/raw/main/Sequoia%20Dark.jpg"

# ── Parse arguments ───────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dark)    VARIANT="dark"; shift ;;
            -l|--light)   VARIANT="light"; shift ;;
            -n|--dry-run) DRY_RUN=true; shift ;;
            -f|--force)   FORCE=true; shift ;;
            -h|--help)    usage; exit 0 ;;
            *)            error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
}

usage() {
    grep '^#' "$0" | grep -E '(Usage|Options|  -|--)' | sed 's/^# //'
}

# ── Idempotency helpers ───────────────────────────────────────────────────────

# Returns 0 (true) if a component is recorded as already installed
is_installed() {
    local component="$1"
    [[ -f "$STATE_FILE" ]] && grep -qxF "$component" "$STATE_FILE"
}

# Records a component as installed in the state file
mark_installed() {
    local component="$1"
    mkdir -p "$(dirname "$STATE_FILE")"
    grep -qxF "$component" "$STATE_FILE" 2>/dev/null || echo "$component" >> "$STATE_FILE"
}

# Guard: returns 1 (skip) if dry-run mode, or if the given filesystem
# condition is already true and --force is not set.
#
# Usage:  guard "label" -d /some/dir    (any 'test' expression)
#         guard "label"                 (no fs check — only skips in dry-run)
#
# When the condition is met and we skip, the component is marked as installed
# so the state file stays consistent.
guard() {
    local component="$1"; shift  # remaining args are the 'test' expression
    if $DRY_RUN; then
        info "[dry-run] Would apply: $component"
        return 1
    fi
    if [[ $# -gt 0 ]] && ! $FORCE && test "$@" 2>/dev/null; then
        info "Already applied (skip): $component  [use --force to reapply]"
        mark_installed "$component"
        return 1
    fi
    return 0
}

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# ── Package manager detection ─────────────────────────────────────────────────
detect_pkg_manager() {
    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"
    elif command -v yay &>/dev/null; then
        AUR_HELPER="yay"
    else
        AUR_HELPER=""
    fi

    if ! command -v pacman &>/dev/null; then
        error "pacman not found. This script targets CachyOS / Arch Linux."
        exit 1
    fi
}

# Installs one or more official-repo packages (skips already-present ones).
# Prints a warning and continues if a package is not found in the repos.
pacman_install() {
    local pkgs=("$@")
    local missing=()
    for pkg in "${pkgs[@]}"; do
        pacman -Qi "$pkg" &>/dev/null || missing+=("$pkg")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0

    # Filter out packages that don't exist in the repos to avoid hard failures
    local available=()
    for pkg in "${missing[@]}"; do
        if pacman -Si "$pkg" &>/dev/null; then
            available+=("$pkg")
        else
            warn "Package not found in official repos (skipping): $pkg"
        fi
    done
    [[ ${#available[@]} -eq 0 ]] && return 0

    info "Installing packages: ${available[*]}"
    sudo pacman -S --needed --noconfirm "${available[@]}"
}

# Installs one or more AUR packages via yay/paru (skips if no AUR helper).
aur_install() {
    if [[ -z "$AUR_HELPER" ]]; then
        warn "No AUR helper (yay/paru) found — skipping AUR package(s): $*"
        return 0
    fi
    local pkgs=("$@")
    local missing=()
    for pkg in "${pkgs[@]}"; do
        pacman -Qi "$pkg" &>/dev/null || missing+=("$pkg")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0
    info "Installing AUR packages: ${missing[*]}"
    "$AUR_HELPER" -S --needed --noconfirm "${missing[@]}"
}

# Installs the Inter font via AUR, handling package conflicts gracefully.
# ttf-inter conflicts with any package that provides the virtual ttf-opensans
# (e.g. ttf-google-fonts-typewolf). Rather than hardcoding a package name,
# we capture the AUR helper output silently and parse it for conflict errors.
install_inter_font() {
    [[ -z "$AUR_HELPER" ]] && return 0
    pacman -Qi ttf-inter &>/dev/null && return 0  # already installed

    info "Installing AUR package: ttf-inter"
    local output exit_code
    output=$("$AUR_HELPER" -S --needed --noconfirm ttf-inter 2>&1) && return 0
    exit_code=$?

    if echo "$output" | grep -qi "conflict"; then
        # Extract the conflicting package name from paru/yay output:
        # ":: Conflicts found:\n    <pkg>: <reason>"
        local conflict_detail
        conflict_detail=$(echo "$output" \
            | grep -A3 "Conflicts found" \
            | grep -v "^::\|Conflicts found\|Conflicting" \
            | head -1 | xargs)
        warn "ttf-inter has a package conflict${conflict_detail:+: $conflict_detail}"
        warn "To install Inter manually, resolve the conflict first:"
        warn "  ${AUR_HELPER} -S ttf-inter  (interactive — choose which package to replace)"
        warn "Falling back to system sans-serif font."
    else
        warn "ttf-inter install failed (exit $exit_code) — falling back to system sans-serif"
        echo "$output" >&2
    fi
}

# ── 1. System dependencies ────────────────────────────────────────────────────
install_dependencies() {
    step "System dependencies"
    # Re-check every run: pacman_install is already idempotent (--needed flag)
    guard "dependencies" || return 0

    # Official Arch/CachyOS repo packages
    # gtk-engine-murrine is AUR-only on Arch; sassc is needed by WhiteSur's install script
    pacman_install git curl wget plank sassc glib2 xfconf

    # AUR packages (requires yay or paru)
    # gtk-engine-murrine provides GTK-2 engine support for legacy apps
    aur_install gtk-engine-murrine || warn "gtk-engine-murrine AUR install failed — GTK-2 apps may look unstyled"
    install_inter_font

    mark_installed "dependencies"
    success "Dependencies ready"
}

# ── 2. GTK theme (WhiteSur) ───────────────────────────────────────────────────
install_gtk_theme() {
    step "GTK theme — WhiteSur"
    # Idempotency: skip if the target theme directory already exists
    guard "gtk-theme" -d "$THEMES_DIR/WhiteSur-${VARIANT^}" || return 0

    local dest="$TMP_DIR/WhiteSur-gtk-theme"
    info "Cloning WhiteSur GTK theme..."
    git clone --depth=1 "$GTK_THEME_REPO" "$dest"

    mkdir -p "$THEMES_DIR"
    # --nautilus / --round are valid WhiteSur flags; Nautilus is omitted since XFCE uses Thunar
    bash "$dest/install.sh" \
        --dest "$THEMES_DIR" \
        --color "${VARIANT^}" \
        --round

    # Also install the GDM/login theme for completeness (optional, needs sudo)
    # bash "$dest/tweaks.sh" -g   # uncomment if you want GDM styling

    mark_installed "gtk-theme"
    success "GTK theme installed: WhiteSur-${VARIANT^}"
}

# ── 3. Icon theme (WhiteSur) ──────────────────────────────────────────────────
install_icons() {
    step "Icon theme — WhiteSur"
    # Idempotency: skip if icon theme directory already exists
    guard "icons" -d "$ICONS_DIR/WhiteSur" || return 0

    local dest="$TMP_DIR/WhiteSur-icon-theme"
    info "Cloning WhiteSur icon theme..."
    git clone --depth=1 "$ICON_THEME_REPO" "$dest"

    mkdir -p "$ICONS_DIR"
    bash "$dest/install.sh" --dest "$ICONS_DIR"

    mark_installed "icons"
    success "Icons installed: WhiteSur"
}

# ── 4. Cursor theme (WhiteSur) ────────────────────────────────────────────────
install_cursors() {
    step "Cursor theme — WhiteSur"
    # Idempotency: skip if cursor theme directory already exists
    guard "cursors" -d "$ICONS_DIR/WhiteSur-cursors" || return 0

    local dest="$TMP_DIR/WhiteSur-cursors"
    info "Cloning WhiteSur cursor theme..."
    git clone --depth=1 "$CURSOR_THEME_REPO" "$dest"

    mkdir -p "$ICONS_DIR"
    # The repo layout is: dist/index.theme + dist/cursors/
    # Copy dist/ as the named theme directory
    cp -rp "$dest/dist" "$ICONS_DIR/WhiteSur-cursors"

    # Register as the system default cursor
    local default_cursor="$ICONS_DIR/default"
    mkdir -p "$default_cursor"
    cat > "$default_cursor/index.theme" <<EOF
[Icon Theme]
Name=Default
Comment=Default cursor theme
Inherits=WhiteSur-cursors
EOF

    mark_installed "cursors"
    success "Cursor theme installed: WhiteSur-cursors"
}

# ── 5. Fonts ──────────────────────────────────────────────────────────────────
install_fonts() {
    step "Fonts"
    # Idempotency: skip if Inter is already available system-wide
    if ! $FORCE && fc-list 2>/dev/null | grep -qi "Inter"; then
        info "Already applied (skip): fonts  [use --force to reapply]"
        mark_installed "fonts"
        return 0
    fi
    guard "fonts" || return 0

    mkdir -p "$FONTS_DIR"
    # Inter is installed via install_dependencies; rebuild cache so it's visible
    fc-cache -f "$FONTS_DIR"

    mark_installed "fonts"
    success "Fonts configured"
}

# ── 6. Wallpaper ──────────────────────────────────────────────────────────────
install_wallpaper() {
    step "Wallpaper — macOS Sequoia"

    local filename
    filename="sequoia-${VARIANT}.jpg"
    local dest="$WALLPAPER_DIR/$filename"

    # Idempotency: skip if wallpaper file already exists
    guard "wallpaper" -f "$dest" || { WALLPAPER_PATH="$dest"; return 0; }

    mkdir -p "$WALLPAPER_DIR"

    local url
    if [[ "$VARIANT" == "dark" ]]; then
        url="$WALLPAPER_DARK_URL"
    else
        url="$WALLPAPER_URL"
    fi

    info "Downloading macOS Sequoia wallpaper..."
    if ! curl -fsSL --retry 3 -o "$dest" "$url"; then
        warn "Primary wallpaper download failed — trying fallback..."
        if command -v convert &>/dev/null; then
            if [[ "$VARIANT" == "dark" ]]; then
                convert -size 3840x2160 gradient:'#1a1a2e-#16213e' "$dest" 2>/dev/null || true
            else
                convert -size 3840x2160 gradient:'#e8eaf6-#9fa8da' "$dest" 2>/dev/null || true
            fi
        fi
    fi

    WALLPAPER_PATH="$dest"
    mark_installed "wallpaper"
    success "Wallpaper ready: $dest"
}

# ── 7. Plank dock ─────────────────────────────────────────────────────────────
configure_plank() {
    step "Plank dock"
    # Idempotency: skip if settings file already exists
    guard "plank" -f "$HOME/.config/plank/dock1/settings" || return 0

    # Write Plank preferences via dconf (if available) or direct config file
    local plank_conf_dir="$HOME/.config/plank/dock1"
    mkdir -p "$plank_conf_dir/launchers"

    # Plank settings file
    cat > "$plank_conf_dir/settings" <<'EOF'
[PlankDockPreferences]
#! Whether to show only windows of the current workspace.
CurrentWorkspaceOnly=false
#! The size of dock icons (in pixels).
IconSize=48
#! If 0, the dock is visible; if 1, it auto-hides; if 2, it intellihides.
HideMode=1
#! Time to wait before hiding the dock.
UnhideDelay=0
#! Time to wait before hiding the dock.
HideDelay=300
#! The monitor plug-in name that the dock should show on, or empty to use the primary monitor.
Monitor=
#! List of themes to use.
Theme=Transparent
#! If true, the dock won't hide when it overlaps with an active window.
LockItems=false
#! The position for the dock on the monitor.
Position=3
#! The alignment for the dock on its axis.
Alignment=3
#! The alignment of the items in the dock when they don't fill it.
ItemsAlignment=3
#! Whether to show an indicator for each open application.
ShowDockItem=false
#! Whether to automatically pin items that the user docks.
AutoPinning=true
ZoomEnabled=true
ZoomPercent=125
EOF

    # Common macOS-style launcher entries
    local launchers=(
        "org.xfce.thunar.dockitem"
        "org.gnome.TextEditor.dockitem"
        "xfce4-terminal.dockitem"
        "firefox.dockitem"
    )
    for launcher in "${launchers[@]}"; do
        local app="${launcher%.dockitem}"
        cat > "$plank_conf_dir/launchers/$launcher" <<EOF
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/${app}.desktop
EOF
    done

    # Add Plank to XFCE autostart
    local autostart_dir="$HOME/.config/autostart"
    mkdir -p "$autostart_dir"
    cat > "$autostart_dir/plank.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Plank
Comment=Dock for the XFCE desktop
Exec=plank
StartupNotify=false
Terminal=false
Hidden=false
EOF

    mark_installed "plank"
    success "Plank dock configured with autostart"
}

# ── 8. XFCE settings via xfconf-query ────────────────────────────────────────
apply_xfce_settings() {
    step "XFCE settings"
    $DRY_RUN && { info "[dry-run] Would apply XFCE settings"; return 0; }

    local expected_theme="WhiteSur-${VARIANT^}"
    local current_theme
    current_theme=$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)

    # Idempotency: only skip if the theme is ALREADY set to the expected value
    if [[ "$current_theme" == "$expected_theme" ]] && ! $FORCE; then
        info "Already applied (skip): xfce-settings  [use --force to reapply]"
        mark_installed "xfce-settings"
        return 0
    fi

    # Backup current settings once (before any changes)
    if [[ ! -f "$BACKUP_DIR/xsettings.txt" ]]; then
        mkdir -p "$BACKUP_DIR"
        xfconf-query -c xsettings     -l 2>/dev/null > "$BACKUP_DIR/xsettings.txt"     || true
        xfconf-query -c xfwm4         -l 2>/dev/null > "$BACKUP_DIR/xfwm4.txt"         || true
        xfconf-query -c xfce4-desktop -l 2>/dev/null > "$BACKUP_DIR/xfce4-desktop.txt" || true
    fi

    local gtk_theme icon_theme font_name wm_theme cursor_theme
    if [[ "$VARIANT" == "dark" ]]; then
        gtk_theme="WhiteSur-Dark"; wm_theme="WhiteSur-Dark"
    else
        gtk_theme="WhiteSur-Light"; wm_theme="WhiteSur-Light"
    fi
    icon_theme="WhiteSur"
    cursor_theme="WhiteSur-cursors"

    if fc-list 2>/dev/null | grep -qi "Inter"; then
        font_name="Inter Regular 13"
    elif fc-list 2>/dev/null | grep -qi "SF Pro"; then
        font_name="SF Pro Display Regular 13"
    else
        font_name="Sans Regular 13"
    fi

    info "Applying settings via xfconf-query..."
    xfconf-query -c xsettings -p /Net/ThemeName        -s "$gtk_theme"           --create -t string
    xfconf-query -c xsettings -p /Net/IconThemeName     -s "$icon_theme"          --create -t string
    xfconf-query -c xsettings -p /Gtk/CursorThemeName   -s "$cursor_theme"        --create -t string
    xfconf-query -c xsettings -p /Gtk/CursorThemeSize   -s 24                     --create -t int
    xfconf-query -c xsettings -p /Gtk/FontName          -s "$font_name"           --create -t string
    xfconf-query -c xsettings -p /Gtk/MonospaceFontName -s "Monospace Regular 12" --create -t string
    xfconf-query -c xsettings -p /Xft/Antialias         -s 1                      --create -t int
    xfconf-query -c xsettings -p /Xft/Hinting           -s 1                      --create -t int
    xfconf-query -c xsettings -p /Xft/HintStyle         -s "hintslight"           --create -t string
    xfconf-query -c xsettings -p /Xft/RGBA              -s "rgb"                  --create -t string

    xfconf-query -c xfwm4 -p /general/theme            -s "$wm_theme"  --create -t string
    xfconf-query -c xfwm4 -p /general/title_font       -s "$font_name" --create -t string
    xfconf-query -c xfwm4 -p /general/button_layout    -s "CMH|"       --create -t string
    xfconf-query -c xfwm4 -p /general/use_compositing  -s true         --create -t bool
    xfconf-query -c xfwm4 -p /general/frame_opacity    -s 85           --create -t int
    xfconf-query -c xfwm4 -p /general/inactive_opacity -s 95           --create -t int

    # Wallpaper — set on every known monitor/workspace property path
    if [[ -n "${WALLPAPER_PATH:-}" && -f "${WALLPAPER_PATH:-}" ]]; then
        info "Setting wallpaper: $WALLPAPER_PATH"
        local screen_prop
        for screen_prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "last-image" || true); do
            xfconf-query -c xfce4-desktop -p "$screen_prop" \
                -s "$WALLPAPER_PATH" --create -t string
        done
        for monitor_path in \
            /backdrop/screen0/monitorVirtual1/workspace0/last-image \
            /backdrop/screen0/monitor0/workspace0/last-image \
            /backdrop/screen0/monitorHDMI-1/workspace0/last-image; do
            xfconf-query -c xfce4-desktop -p "$monitor_path" \
                -s "$WALLPAPER_PATH" --create -t string 2>/dev/null || true
        done
    fi

    configure_xfce_panel

    # Write XML channel files directly as a reliable on-disk fallback.
    # xfconf-query talks to xfconfd via DBUS (live updates), but the XML files
    # are what XFCE reads on next login. Writing both guarantees persistence.
    write_xfce_xml_settings "$gtk_theme" "$wm_theme" "$icon_theme" \
                             "$cursor_theme" "$font_name"

    # Signal running XFCE daemons to reload without requiring a full logout
    reload_xfce_session

    mark_installed "xfce-settings"
    success "XFCE settings applied"
}

# Writes XFCE XML channel config files directly so settings survive the next
# login even if xfconfd was not reachable during the install run.
write_xfce_xml_settings() {
    local gtk_theme="$1" wm_theme="$2" icon_theme="$3"
    local cursor_theme="$4" font_name="$5"
    local xfconf_dir="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$xfconf_dir"

    info "Writing XFCE XML channel files for persistence..."

    cat > "$xfconf_dir/xsettings.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="$gtk_theme"/>
    <property name="IconThemeName" type="string" value="$icon_theme"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeName" type="string" value="$cursor_theme"/>
    <property name="CursorThemeSize" type="int" value="24"/>
    <property name="FontName" type="string" value="$font_name"/>
    <property name="MonospaceFontName" type="string" value="Monospace Regular 12"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
</channel>
EOF

    cat > "$xfconf_dir/xfwm4.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="$wm_theme"/>
    <property name="title_font" type="string" value="$font_name"/>
    <property name="button_layout" type="string" value="CMH|"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="frame_opacity" type="int" value="85"/>
    <property name="inactive_opacity" type="int" value="95"/>
  </property>
</channel>
EOF

    # Write wallpaper setting if available
    if [[ -n "${WALLPAPER_PATH:-}" && -f "${WALLPAPER_PATH:-}" ]]; then
        cat > "$xfconf_dir/xfce4-desktop.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="$WALLPAPER_PATH"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitorVirtual1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="$WALLPAPER_PATH"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
    fi
}

# Signal running XFCE session daemons to reload configuration without logout.
reload_xfce_session() {
    info "Signalling XFCE daemons to reload..."

    # Restart xfsettingsd — picks up GTK theme, fonts, cursor, DPI changes
    if command -v xfsettingsd &>/dev/null; then
        pkill -x xfsettingsd 2>/dev/null || true
        sleep 0.5
        xfsettingsd --no-daemon &>/dev/null &
        disown
    fi

    # Reload panel (picks up position / size changes)
    if command -v xfce4-panel &>/dev/null; then
        xfce4-panel -r &>/dev/null & disown
    fi

    # Signal xfce4-desktop to redraw wallpaper
    if command -v xfdesktop &>/dev/null; then
        xfdesktop --reload &>/dev/null & disown 2>/dev/null || true
    fi
}

# ── 8a. XFCE Panel (macOS menu-bar style) ─────────────────────────────────────
configure_xfce_panel() {
    info "Configuring XFCE panel (macOS menu-bar style)..."

    # Panel 1 — top menu bar
    xfconf-query -c xfce4-panel -p /panels/panel-1/position         -s "p=6;x=960;y=0" --create -t string
    xfconf-query -c xfce4-panel -p /panels/panel-1/size             -s 28               --create -t uint
    xfconf-query -c xfce4-panel -p /panels/panel-1/length           -s 100              --create -t uint
    xfconf-query -c xfce4-panel -p /panels/panel-1/length-adjust    -s true             --create -t bool
    xfconf-query -c xfce4-panel -p /panels/panel-1/position-locked  -s true             --create -t bool
    xfconf-query -c xfce4-panel -p /panels/panel-1/enter-opacity    -s 95               --create -t uint
    xfconf-query -c xfce4-panel -p /panels/panel-1/leave-opacity    -s 85               --create -t uint

    # Autohide the bottom taskbar panel if it exists (panel-2)
    xfconf-query -c xfce4-panel -p /panels/panel-2/autohide-behavior -s 1 --create -t uint 2>/dev/null || true
}

# ── 9. GTK-2 compatibility ────────────────────────────────────────────────────
configure_gtk2() {
    step "GTK-2 compatibility"
    # Idempotency: skip if config already references WhiteSur
    if ! $FORCE && grep -q "WhiteSur" "$HOME/.gtkrc-2.0" 2>/dev/null; then
        info "Already applied (skip): gtk2  [use --force to reapply]"
        mark_installed "gtk2"
        return 0
    fi
    guard "gtk2" || return 0

    local gtk2_conf="$HOME/.gtkrc-2.0"
    if [[ "$VARIANT" == "dark" ]]; then
        cat > "$gtk2_conf" <<'EOF'
gtk-theme-name = "WhiteSur-Dark"
gtk-icon-theme-name = "WhiteSur"
gtk-font-name = "Inter Regular 13"
gtk-cursor-theme-name = "WhiteSur-cursors"
gtk-cursor-theme-size = 24
gtk-toolbar-style = GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size = GTK_ICON_SIZE_SMALL_TOOLBAR
gtk-button-images = 0
gtk-menu-images = 0
gtk-enable-event-sounds = 1
gtk-enable-input-feedback-sounds = 0
gtk-xft-antialias = 1
gtk-xft-hinting = 1
gtk-xft-hintstyle = "hintslight"
gtk-xft-rgba = "rgb"
EOF
    else
        cat > "$gtk2_conf" <<'EOF'
gtk-theme-name = "WhiteSur-Light"
gtk-icon-theme-name = "WhiteSur"
gtk-font-name = "Inter Regular 13"
gtk-cursor-theme-name = "WhiteSur-cursors"
gtk-cursor-theme-size = 24
gtk-toolbar-style = GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size = GTK_ICON_SIZE_SMALL_TOOLBAR
gtk-button-images = 0
gtk-menu-images = 0
gtk-enable-event-sounds = 1
gtk-enable-input-feedback-sounds = 0
gtk-xft-antialias = 1
gtk-xft-hinting = 1
gtk-xft-hintstyle = "hintslight"
gtk-xft-rgba = "rgb"
EOF
    fi

    # GTK-3 settings
    local gtk3_dir="$HOME/.config/gtk-3.0"
    mkdir -p "$gtk3_dir"
    cat > "$gtk3_dir/settings.ini" <<EOF
[Settings]
gtk-theme-name=$([ "$VARIANT" = "dark" ] && echo "WhiteSur-Dark" || echo "WhiteSur-Light")
gtk-icon-theme-name=WhiteSur
gtk-font-name=Inter Regular 13
gtk-cursor-theme-name=WhiteSur-cursors
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR
gtk-button-images=false
gtk-menu-images=false
gtk-enable-event-sounds=true
gtk-enable-input-feedback-sounds=false
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
EOF

    # GTK-4 settings
    local gtk4_dir="$HOME/.config/gtk-4.0"
    mkdir -p "$gtk4_dir"
    cp "$gtk3_dir/settings.ini" "$gtk4_dir/settings.ini"

    mark_installed "gtk2"
    success "GTK-2/3/4 config files written"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo
    echo -e "${BOLD}════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  macOS ${VARIANT^} theme applied successfully!${RESET}"
    echo -e "${BOLD}════════════════════════════════════════${RESET}"
    echo
    echo "  GTK Theme  : WhiteSur-${VARIANT^}"
    echo "  Icons      : WhiteSur"
    echo "  Cursors    : WhiteSur-cursors"
    echo "  Dock       : Plank (autostart enabled)"
    echo "  Wallpaper  : macOS Sequoia ${VARIANT^}"
    echo
    echo -e "${YELLOW}  → Log out and back in (or run: xfce4-panel -r)${RESET}"
    echo -e "${YELLOW}    to fully apply panel and compositor changes.${RESET}"
    echo
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo -e "${BOLD}"
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   XFCE macOS Theme Installer        │"
    echo "  │   Variant: ${VARIANT}                       │"
    echo "  └─────────────────────────────────────┘"
    echo -e "${RESET}"

    if $DRY_RUN; then
        warn "DRY-RUN mode — no changes will be made"
    fi

    detect_pkg_manager

    install_dependencies
    install_gtk_theme
    install_icons
    install_cursors
    install_fonts
    install_wallpaper
    configure_plank
    apply_xfce_settings
    configure_gtk2

    print_summary
}

main "$@"
