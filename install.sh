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

# macOS Sonoma wallpaper — from vinceliuice/WhiteSur-wallpapers (verified working)
WALLPAPER_URL="https://github.com/vinceliuice/WhiteSur-wallpapers/raw/main/4k/Sonoma-light.jpg"
WALLPAPER_DARK_URL="https://github.com/vinceliuice/WhiteSur-wallpapers/raw/main/4k/Sonoma-dark.jpg"

# Apple logo icon (from WhiteSur icon theme, used for whiskermenu button)
APPLE_ICON_URL="https://raw.githubusercontent.com/vinceliuice/WhiteSur-icon-theme/master/src/places/scalable/start-here.svg"

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

# ── Apple logo icon ───────────────────────────────────────────────────────────
# Downloads the WhiteSur start-here.svg (Apple logo) and installs it into the
# hicolor icon theme so `start-here` resolves to the Apple mark system-wide.
install_apple_icon() {
    local icon_dir="$HOME/.local/share/icons/hicolor/scalable/places"
    local icon_path="$icon_dir/start-here.svg"

    # Skip if already installed and not forcing
    if [[ -f "$icon_path" ]] && ! $FORCE; then
        return 0
    fi

    mkdir -p "$icon_dir"
    if curl -fsSL --retry 3 -o "$icon_path" "$APPLE_ICON_URL" 2>/dev/null; then
        # Invalidate icon cache so GTK picks up the new icon immediately
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
        success "Apple logo icon installed: $icon_path"
    else
        warn "Apple icon download failed — whiskermenu will use default start-here icon"
    fi
}

# ── 1. System dependencies ────────────────────────────────────────────────────
install_dependencies() {
    step "System dependencies"
    # Re-check every run: pacman_install is already idempotent (--needed flag)
    guard "dependencies" || return 0

    # Official Arch/CachyOS repo packages
    # gtk-engine-murrine is AUR-only on Arch; sassc is needed by WhiteSur's install script
    pacman_install git curl wget plank sassc glib2 xfconf \
        xfce4-whiskermenu-plugin xfce4-statusnotifier-plugin \
        xfce4-pulseaudio-plugin xfce4-power-manager network-manager-applet \
        picom rofi

    # AUR packages (requires yay or paru)
    # gtk-engine-murrine provides GTK-2 engine support for legacy apps
    aur_install gtk-engine-murrine || warn "gtk-engine-murrine AUR install failed — GTK-2 apps may look unstyled"
    install_inter_font
    install_apple_icon

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
    local plank_conf_dir="$HOME/.config/plank/dock1"

    # Idempotency: skip only if HideMode is already 0 (never hide) AND force not requested.
    # Checking the actual setting rather than mere file existence ensures HideMode is
    # always enforced even on re-runs over an existing Plank installation.
    if ! $FORCE && grep -q "^HideMode=0" "$plank_conf_dir/settings" 2>/dev/null; then
        info "Already applied (skip): plank  [use --force to reapply]"
        mark_installed "plank"
        return 0
    fi
    guard "plank" || return 0

    mkdir -p "$plank_conf_dir/launchers"

    # Plank settings file
    cat > "$plank_conf_dir/settings" <<'EOF'
[PlankDockPreferences]
#! Whether to show only windows of the current workspace.
CurrentWorkspaceOnly=false
#! The size of dock icons (in pixels).
IconSize=48
#! If 0, always visible; if 1, auto-hides; if 2, intellihides; if 3, window-dodge.
#! HideMode=0 means Plank NEVER hides regardless of overlapping windows.
HideMode=0
#! Time to wait before unhiding the dock (irrelevant when HideMode=0).
UnhideDelay=0
#! Time to wait before hiding the dock (irrelevant when HideMode=0).
HideDelay=300
#! The monitor plug-in name that the dock should show on, or empty for primary monitor.
Monitor=
#! Dock theme.
Theme=Transparent
#! If true, prevents items from being added or removed — must be false so running
#! applications appear in the dock even when they are not pinned.
LockItems=false
#! The position for the dock on the monitor (3 = bottom).
Position=3
#! The alignment for the dock on its axis (3 = center).
Alignment=3
#! The alignment of the items in the dock when they don't fill it (3 = center).
ItemsAlignment=3
#! Whether to show a self-referencing dock item.
ShowDockItem=false
#! If true, dragging an app onto the dock permanently pins it.
#! Running (non-pinned) apps always appear in the dock regardless of this setting.
AutoPinning=false
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

    # Trash dockitem — uses Plank's built-in trash:// URI (shows fill level)
    cat > "$plank_conf_dir/launchers/trash.dockitem" <<'EOF'
[PlankDockItemPreferences]
Launcher=trash://
EOF

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

    # Wallpaper — detect real monitor names, set on every workspace property
    if [[ -n "${WALLPAPER_PATH:-}" && -f "${WALLPAPER_PATH:-}" ]]; then
        info "Setting wallpaper: $WALLPAPER_PATH"

        # Discover connected monitor names (e.g. eDP-1, HDMI-A-1, Virtual1)
        local detected_monitors=()
        if command -v xrandr &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
            while IFS= read -r mon; do
                detected_monitors+=("$mon")
            done < <(xrandr --listmonitors 2>/dev/null | awk 'NR>1{print $NF}' || true)
        fi
        # Always include common fallback names so the XML covers fresh sessions too
        local all_monitors=("${detected_monitors[@]}" "Virtual1" "monitor0" "HDMI-1" "eDP-1" "eDP-2" "HDMI-A-1" "DP-1")

        # Update any already-existing last-image properties (handles custom paths)
        while IFS= read -r screen_prop; do
            xfconf-query -c xfce4-desktop -p "$screen_prop" \
                -s "$WALLPAPER_PATH" --create -t string 2>/dev/null || true
        done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "last-image" || true)

        # Create/update properties for every monitor name we know about
        for mon in "${all_monitors[@]}"; do
            for ws in 0 1; do
                xfconf-query -c xfce4-desktop \
                    -p "/backdrop/screen0/monitor${mon}/workspace${ws}/last-image" \
                    -s "$WALLPAPER_PATH" --create -t string 2>/dev/null || true
                xfconf-query -c xfce4-desktop \
                    -p "/backdrop/screen0/monitor${mon}/workspace${ws}/image-style" \
                    -s 5 --create -t int 2>/dev/null || true
            done
        done
    fi

    configure_xfce_panel

    # Show battery percentage label in the power-manager panel plugin
    xfconf-query -c xfce4-power-manager \
        -p /xfce4-power-manager/show-panel-label -s 1 --create -t int 2>/dev/null || true

    # Hide Trash (and Home) from the desktop — they live in the Plank dock
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-trash \
        -s false --create -t bool 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home \
        -s false --create -t bool 2>/dev/null || true

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

    # Write wallpaper + desktop-icon settings
    # Detect monitors for the XML (same logic as xfconf-query wallpaper section)
    local xml_monitors=()
    if command -v xrandr &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
        while IFS= read -r mon; do
            xml_monitors+=("$mon")
        done < <(xrandr --listmonitors 2>/dev/null | awk 'NR>1{print $NF}' || true)
    fi
    # Always include fallbacks so the file works even without a live display
    xml_monitors+=("Virtual1" "monitor0" "HDMI-1" "eDP-1" "eDP-2" "HDMI-A-1" "DP-1")

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<channel name="xfce4-desktop" version="1.0">'
        if [[ -n "${WALLPAPER_PATH:-}" && -f "${WALLPAPER_PATH:-}" ]]; then
            echo '  <property name="backdrop" type="empty">'
            echo '    <property name="screen0" type="empty">'
            for mon in "${xml_monitors[@]}"; do
                echo "      <property name=\"monitor${mon}\" type=\"empty\">"
                echo '        <property name="workspace0" type="empty">'
                echo "          <property name=\"last-image\" type=\"string\" value=\"${WALLPAPER_PATH}\"/>"
                echo '          <property name="image-style" type="int" value="5"/>'
                echo '        </property>'
                echo '      </property>'
            done
            echo '    </property>'
            echo '  </property>'
        fi
        # Hide Trash and Home from desktop (they live in the Plank dock)
        echo '  <property name="desktop-icons" type="empty">'
        echo '    <property name="file-icons" type="empty">'
        echo '      <property name="show-trash" type="bool" value="false"/>'
        echo '      <property name="show-home" type="bool" value="false"/>'
        echo '    </property>'
        echo '  </property>'
        echo '</channel>'
    } > "$xfconf_dir/xfce4-desktop.xml"
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

    # Stop panel then restart so it picks up the new xfce4-panel.xml config
    if command -v xfce4-panel &>/dev/null; then
        xfce4-panel --quit 2>/dev/null || true
        sleep 1
        xfce4-panel &>/dev/null &
        disown
    fi

    # Kill xfdesktop and restart — --reload doesn't always pick up wallpaper changes
    if command -v xfdesktop &>/dev/null; then
        pkill -x xfdesktop 2>/dev/null || true
        sleep 0.5
        xfdesktop &>/dev/null &
        disown
    fi
}

# ── 8a. XFCE Panel (macOS menu-bar style) ─────────────────────────────────────
configure_xfce_panel() {
    info "Configuring XFCE panel (macOS menu-bar style)..."

    local xfconf_dir="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    local panel_conf_dir="$HOME/.config/xfce4/panel"
    mkdir -p "$xfconf_dir" "$panel_conf_dir"

    # Write complete xfce4-panel.xml with only panel-1 (top menu bar).
    # Panel-2 (bottom taskbar) is deliberately omitted from the panels array.
    #
    # macOS menu bar layout (left → right) — 8 plugins, no logout button:
    #   [Apple/whiskermenu] [──expand──] [clock (centered)] [──expand──]
    #   [statusnotifier(Wi-Fi)] [pulseaudio(Vol)] [power-manager(Bat%)] [systray]
    cat > "$xfconf_dir/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
  </property>
  <property name="panels" type="empty">
    <property name="panel-1" type="empty">
      <property name="autohide-behavior" type="uint" value="0"/>
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="size" type="uint" value="24"/>
      <property name="nrows" type="uint" value="1"/>
      <property name="length" type="uint" value="100"/>
      <property name="length-adjust" type="bool" value="true"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-rgba" type="array">
        <value type="double" value="0.1"/>
        <value type="double" value="0.1"/>
        <value type="double" value="0.1"/>
        <value type="double" value="0.82"/>
      </property>
      <property name="icon-size" type="uint" value="14"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <!-- 1: Apple / Whisker Menu (far left) — session actions inside the menu -->
    <property name="plugin-1" type="string" value="whiskermenu">
      <property name="show-button-title" type="bool" value="false"/>
      <property name="show-button-icon" type="bool" value="true"/>
      <property name="button-icon" type="string" value="start-here"/>
    </property>
    <!-- 2: Expanding separator — pushes clock to center -->
    <property name="plugin-2" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <!-- 3: Clock (centered) — macOS format: Mon Apr 21  2:35 PM -->
    <property name="plugin-3" type="string" value="clock">
      <property name="digital-format" type="string" value="%a %b %-e  %I:%M %p"/>
      <property name="mode" type="uint" value="2"/>
      <property name="show-frame" type="bool" value="false"/>
    </property>
    <!-- 4: Expanding separator — pushes right-side items to far right -->
    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <!-- 5: StatusNotifier — Wi-Fi (nm-applet) + modern tray icons (macOS right side) -->
    <property name="plugin-5" type="string" value="statusnotifier">
      <property name="single-row" type="bool" value="true"/>
      <property name="icon-size" type="int" value="14"/>
    </property>
    <!-- 6: Volume — PulseAudio / PipeWire -->
    <property name="plugin-6" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="show-notifications" type="bool" value="true"/>
    </property>
    <!-- 7: Battery / Power Manager (shows percentage) -->
    <property name="plugin-7" type="string" value="power-manager-plugin"/>
    <!-- 8: Legacy notification area (X11 tray icons) -->
    <property name="plugin-8" type="string" value="systray">
      <property name="size-max" type="uint" value="20"/>
      <property name="icon-size" type="uint" value="0"/>
      <property name="square-icons" type="bool" value="true"/>
    </property>
  </property>
</channel>
EOF

    # whiskermenu-1.rc: Apple logo, no title, session actions visible in menu
    cat > "$panel_conf_dir/whiskermenu-1.rc" <<'EOF'
button-icon=start-here
show-button-title=false
show-button-icon=true
profile=Default
launcher-show-name=true
launcher-show-description=false
show-session-buttons=true
EOF

    # clock-3.rc: centered, macOS-style date+time
    cat > "$panel_conf_dir/clock-3.rc" <<'EOF'
digital-format=%a %b %-e  %I:%M %p
mode=2
show-frame=false
EOF

    # Belt-and-suspenders: also set panel-2 to always-hide via xfconf-query
    xfconf-query -c xfce4-panel -p /panels/panel-2/autohide-behavior \
        -s 2 --create -t uint 2>/dev/null || true

    # Also apply panel-1 properties live via xfconf-query
    xfconf-query -c xfce4-panel -p /panels/panel-1/position        -s "p=6;x=0;y=0" --create -t string
    xfconf-query -c xfce4-panel -p /panels/panel-1/size            -s 24             --create -t uint
    xfconf-query -c xfce4-panel -p /panels/panel-1/length          -s 100            --create -t uint
    xfconf-query -c xfce4-panel -p /panels/panel-1/length-adjust   -s true           --create -t bool
    xfconf-query -c xfce4-panel -p /panels/panel-1/position-locked -s true           --create -t bool
    # Transparent panel background — picom will render the frosted-glass blur through it
    xfconf-query -c xfce4-panel -p /panels/panel-1/background-style -s 0 --create -t uint 2>/dev/null || true

    info "xfce4-panel.xml and plugin RC files written"
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

    # GTK CSS: transparent panel background so picom frosted-glass blur shows through.
    # Appended only if the rule is not already present (idempotent).
    local gtk3_css="$gtk3_dir/gtk.css"
    if ! grep -q "xfce4-panel.background" "$gtk3_css" 2>/dev/null; then
        cat >> "$gtk3_css" <<'EOF'

/* xfce-macos-theme: transparent panel so picom blur is visible */
.xfce4-panel.background {
    background-color: transparent;
    background-image: none;
}
EOF
    fi

    mark_installed "gtk2"
    success "GTK-2/3/4 config files written"
}

# ── 9b. Browser GTK theme integration ────────────────────────────────────────
# Browsers (Firefox, Chromium) are often launched outside the XFCE session bus
# and do not read xfconf settings. Exporting GTK_THEME as a real environment
# variable is the only reliable way to force them to use the WhiteSur theme.
# Also installs the WhiteSur Firefox chrome CSS for a macOS-style browser UI.
configure_browser_theme() {
    step "Browser GTK theme integration"
    local marker="$HOME/.local/share/xfce-macos-theme/.browser-theme"
    guard "browser-theme" -f "$marker" || return 0

    local gtk_theme
    [[ "$VARIANT" == "dark" ]] && gtk_theme="WhiteSur-Dark" || gtk_theme="WhiteSur-Light"

    # ── 1. Export GTK_THEME in ~/.profile (login shell, picked up by app launchers)
    local profile="$HOME/.profile"
    touch "$profile"
    if grep -q "^export GTK_THEME=" "$profile" 2>/dev/null; then
        sed -i "s|^export GTK_THEME=.*|export GTK_THEME=\"$gtk_theme\"|" "$profile"
    else
        printf '\n# xfce-macos-theme: force GTK theme for browsers and non-XFCE apps\nexport GTK_THEME="%s"\n' "$gtk_theme" >> "$profile"
    fi
    info "GTK_THEME=$gtk_theme written to $profile"

    # ── 2. systemd user environment (apps launched via D-Bus activation)
    local env_dir="$HOME/.config/environment.d"
    mkdir -p "$env_dir"
    printf 'GTK_THEME=%s\n' "$gtk_theme" > "$env_dir/xfce-macos-gtk.conf"
    info "GTK_THEME written to $env_dir/xfce-macos-gtk.conf"

    # ── 3. WhiteSur Firefox chrome theme (macOS-style tab bar + window controls)
    local gtk_theme_dir="$TMP_DIR/WhiteSur-gtk-theme"
    if [[ ! -d "$gtk_theme_dir" ]]; then
        info "Cloning WhiteSur GTK theme for Firefox tweaks..."
        git clone --depth=1 "$GTK_THEME_REPO" "$gtk_theme_dir" 2>/dev/null || true
    fi
    if [[ -f "$gtk_theme_dir/tweaks.sh" ]]; then
        if command -v firefox &>/dev/null || [[ -d "$HOME/.mozilla/firefox" ]]; then
            info "Installing WhiteSur Firefox chrome theme..."
            bash "$gtk_theme_dir/tweaks.sh" --color "${VARIANT^}" --firefox 2>/dev/null \
                || warn "Firefox chrome theme install failed — run after first Firefox launch"
        else
            info "Firefox not found — skipping Firefox chrome theme"
        fi
    fi

    # ── 4. Chromium / Chrome flags (force GTK3 rendering)
    for flags_file in \
        "$HOME/.config/chromium-flags.conf" \
        "$HOME/.config/google-chrome-flags.conf" \
        "$HOME/.config/chrome-flags.conf"; do
        local app_dir
        app_dir="$(dirname "$flags_file")"
        # Only write if the browser config dir already exists (i.e. browser is installed)
        if [[ -d "$app_dir" ]]; then
            if ! grep -q "gtk-version" "$flags_file" 2>/dev/null; then
                echo "--gtk-version=3" >> "$flags_file"
                info "Added --gtk-version=3 to $flags_file"
            fi
        fi
    done

    mark_installed "browser-theme"
    success "Browser GTK theme integration configured"
}
# Installs picom and configures it with dual_kawase blur so the panel appears
# with the translucent frosted-glass effect seen on the macOS menu bar.
configure_picom() {
    step "Picom compositor (frosted-glass blur)"
    local conf="$HOME/.config/picom.conf"
    local autostart="$HOME/.config/autostart/picom.desktop"

    guard "picom" -f "$conf" || return 0

    mkdir -p "$(dirname "$conf")" "$HOME/.config/autostart"

    cat > "$conf" <<'EOF'
# picom.conf — generated by xfce-macos-theme
# Provides the frosted-glass background blur visible through the transparent
# XFCE panel, matching the macOS Sequoia menu-bar vibrancy effect.

backend = "glx";
vsync = true;

# Blur — dual_kawase gives the closest approximation to macOS Core Image blur
blur-background = true;
blur-method = "dual_kawase";
blur-strength = 8;
blur-background-exclude = [
    "window_type = 'tooltip'",
    "class_g = 'slop'"
];

# Shadows (macOS-style soft window shadows)
shadow = true;
shadow-radius = 14;
shadow-opacity = 0.35;
shadow-offset-x = -7;
shadow-offset-y = -7;
shadow-exclude = [
    "window_type = 'dock'",
    "window_type = 'tooltip'",
    "_GTK_FRAME_EXTENTS@:c"
];

# Opacity rules — make the panel semi-transparent so blur shows through
opacity-rule = [
    "85:class_g = 'Xfce4-panel'"
];

# Fading
fading = true;
fade-in-step = 0.028;
fade-out-step = 0.03;
fade-exclude = [];

# Rounded corners (matches WhiteSur theme style)
corner-radius = 8;
rounded-corners-exclude = [
    "window_type = 'dock'",
    "window_type = 'tooltip'"
];
EOF

    # Autostart entry — picom starts with every session
    cat > "$autostart" <<'EOF'
[Desktop Entry]
Type=Application
Name=Picom Compositor
Comment=Lightweight compositor with blur for macOS-style panel
Exec=picom --config /home/USER/.config/picom.conf
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    # Replace the placeholder with the real home path
    sed -i "s|/home/USER|$HOME|g" "$autostart"

    # Start picom immediately if a display is available
    if [[ -n "${DISPLAY:-}" ]]; then
        # Kill any existing picom instance first
        local picom_pid
        picom_pid=$(pgrep -x picom | head -1 || true)
        if [[ -n "$picom_pid" ]]; then
            kill "$picom_pid" 2>/dev/null || true
            sleep 0.5
        fi
        picom --config "$conf" --daemon 2>/dev/null || \
            info "picom start deferred — will start on next login"
    fi

    mark_installed "picom"
    success "Picom configured with frosted-glass blur"
}

# ── 10b. Autostart entries (nm-applet) ────────────────────────────────────────
# Ensures nm-applet (Wi-Fi / network indicator) is running at login so the
# StatusNotifier plugin in the panel shows the Wi-Fi icon on the right side,
# matching the macOS menu bar network indicator.
configure_autostart() {
    step "Autostart entries (nm-applet)"
    local nm_desktop="$HOME/.config/autostart/nm-applet.desktop"

    guard "nm-applet-autostart" -f "$nm_desktop" || return 0

    mkdir -p "$HOME/.config/autostart"

    cat > "$nm_desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Network Manager Applet
Comment=Network status indicator for XFCE panel
Exec=nm-applet
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

    # Start nm-applet in this session immediately if not already running
    if [[ -n "${DISPLAY:-}" ]] && ! pgrep -x nm-applet &>/dev/null; then
        nm-applet &
        disown
        info "nm-applet started for this session"
    fi

    mark_installed "nm-applet-autostart"
    success "nm-applet autostart configured"
}

# ── 12. Rofi Spotlight launcher ───────────────────────────────────────────────
# Installs rofi and themes it to look like macOS Spotlight: centred panel,
# blurred background, rounded corners, Inter font, WhiteSur colours.
# Bound to Super+Space (same position as macOS Command+Space) via XFCE shortcuts.
configure_rofi() {
    step "Rofi Spotlight launcher (Super+Space)"
    local rofi_dir="$HOME/.config/rofi"
    local conf="$rofi_dir/config.rasi"
    guard "rofi" -f "$conf" || return 0

    mkdir -p "$rofi_dir"

    # Choose colours based on dark/light variant
    local bg_colour icon_fg sel_bg sel_fg txt_fg
    if [[ "$VARIANT" == "dark" ]]; then
        bg_colour="#1e1e1e"
        txt_fg="#f0f0f0"
        sel_bg="#3d7aed"
        sel_fg="#ffffff"
        icon_fg="#ababab"
    else
        bg_colour="#f5f5f7"
        txt_fg="#1d1d1f"
        sel_bg="#0071e3"
        sel_fg="#ffffff"
        icon_fg="#555555"
    fi

    # Write the rofi theme file (macOS Spotlight style)
    cat > "$rofi_dir/spotlight.rasi" <<EOF
/* xfce-macos-theme: Spotlight-style rofi theme */
* {
    font:            "Inter Regular 14";
    background:      ${bg_colour}e6;   /* ~90% opacity */
    background-alt:  ${bg_colour}cc;
    foreground:      ${txt_fg};
    selected-bg:     ${sel_bg};
    selected-fg:     ${sel_fg};
    border-colour:   ${icon_fg}44;
}

window {
    transparency:        "real";
    width:               640px;
    border-radius:       12px;
    border:              1px solid @border-colour;
    background-color:    @background;
    padding:             8px;
    x-offset:           0;
    y-offset:           -80px;   /* slightly above center — Spotlight position */
    location:            center;
}

mainbox {
    background-color:   transparent;
    children:           [ inputbar, listview ];
    spacing:            6px;
}

inputbar {
    background-color:   transparent;
    border-radius:       8px;
    padding:             6px 12px;
    spacing:             8px;
    children:            [ prompt, entry ];
}

prompt {
    background-color:   transparent;
    text-color:         @foreground;
    padding:            4px 0;
}

entry {
    background-color:   transparent;
    text-color:         @foreground;
    placeholder-color:  ${icon_fg};
    placeholder:        "Search apps, files, commands…";
    cursor:             text;
}

listview {
    background-color:   transparent;
    columns:            1;
    lines:              8;
    scrollbar:          false;
    spacing:            2px;
}

element {
    background-color:   transparent;
    border-radius:       6px;
    padding:             8px 12px;
    spacing:             10px;
    children:            [ element-icon, element-text ];
}

element selected.normal {
    background-color:   @selected-bg;
    text-color:         @selected-fg;
}

element-icon {
    size:               24px;
    vertical-align:     0.5;
}

element-text {
    text-color:         inherit;
    vertical-align:     0.5;
}
EOF

    # Main rofi config — use drun (app launcher) as default mode
    cat > "$conf" <<EOF
configuration {
    modi:           "drun,run,window";
    show-icons:     true;
    drun-display-format: "{name}";
    display-drun:   "  Apps";
    display-run:    "  Run";
    display-window: "  Windows";
    terminal:       "xfce4-terminal";
    icon-theme:     "WhiteSur";
    sidebar-mode:   false;
}

@theme "$rofi_dir/spotlight.rasi"
EOF

    # Bind Super+Space in XFCE keyboard shortcuts (mirrors Command+Space on macOS)
    xfconf-query -c xfce4-keyboard-shortcuts \
        -p "/commands/custom/<Super>space" \
        -s "rofi -show drun" --create -t string 2>/dev/null || true

    # Also bind Super+Shift+Space for window switcher (like macOS Exposé)
    xfconf-query -c xfce4-keyboard-shortcuts \
        -p "/commands/custom/<Super><Shift>space" \
        -s "rofi -show window" --create -t string 2>/dev/null || true

    mark_installed "rofi"
    success "Rofi Spotlight launcher configured — press Super+Space to launch"
}

# ── 13. Login screen (LightDM) ────────────────────────────────────────────────
configure_login_screen() {
    step "Login screen (LightDM)"
    # Idempotency: check if we've already configured it
    local marker="/etc/lightdm/.xfce-macos-theme"
    guard "login-screen" -f "$marker" || return 0

    # Detect installed greeter
    local greeter="lightdm-gtk-greeter"  # CachyOS XFCE default
    if [[ -f /etc/lightdm/lightdm.conf ]]; then
        local detected
        detected=$(grep -Po '(?<=greeter-session=)\S+' /etc/lightdm/lightdm.conf 2>/dev/null || true)
        [[ -n "$detected" ]] && greeter="$detected"
    fi
    # Also detect by which greeter binary is installed
    [[ ! -f "/usr/bin/lightdm-gtk-greeter" ]] && \
        [[ -f "/usr/bin/lightdm-slick-greeter" ]] && greeter="lightdm-slick-greeter"

    info "Detected greeter: $greeter"

    # Install greeter package if needed
    case "$greeter" in
        lightdm-gtk-greeter)   pacman_install lightdm-gtk-greeter ;;
        lightdm-slick-greeter) pacman_install lightdm-slick-greeter ;;
    esac

    # Copy wallpaper to system-wide location (needs sudo)
    local sys_wp_dir="/usr/share/backgrounds/macos-sequoia"
    local sys_wp="$sys_wp_dir/sequoia-${VARIANT}.jpg"
    if [[ -f "${WALLPAPER_PATH:-}" ]]; then
        sudo mkdir -p "$sys_wp_dir" || warn "sudo mkdir failed for $sys_wp_dir"
        sudo cp -f "$WALLPAPER_PATH" "$sys_wp" || warn "sudo cp wallpaper failed"
    fi

    # Install GTK theme system-wide so greeter can use it
    local gtk_theme
    [[ "$VARIANT" == "dark" ]] && gtk_theme="WhiteSur-Dark" || gtk_theme="WhiteSur-Light"
    if [[ -d "$THEMES_DIR/$gtk_theme" ]] && [[ ! -d "/usr/share/themes/$gtk_theme" ]]; then
        sudo cp -r "$THEMES_DIR/$gtk_theme" /usr/share/themes/ \
            || warn "sudo cp GTK theme to /usr/share/themes/ failed"
        info "Installed $gtk_theme to /usr/share/themes/"
    fi

    # Install icon theme system-wide
    if [[ -d "$ICONS_DIR/WhiteSur" ]] && [[ ! -d "/usr/share/icons/WhiteSur" ]]; then
        sudo cp -r "$ICONS_DIR/WhiteSur" /usr/share/icons/ \
            || warn "sudo cp icons to /usr/share/icons/ failed"
        info "Installed WhiteSur icons to /usr/share/icons/"
    fi

    # Write greeter config
    local font_name="Inter Regular 13"
    fc-list 2>/dev/null | grep -qi "Inter" || font_name="Sans Regular 13"

    case "$greeter" in
        lightdm-gtk-greeter)
            local conf="/etc/lightdm/lightdm-gtk-greeter.conf"
            sudo cp -n "$conf" "${conf}.bak" 2>/dev/null || true
            sudo tee "$conf" > /dev/null <<EOF
[greeter]
background=$sys_wp
theme-name=$gtk_theme
icon-theme-name=WhiteSur
font-name=$font_name
cursor-theme-name=WhiteSur-cursors
cursor-theme-size=24
indicators=~host;~spacer;~clock;~spacer;~power
clock-format=%a %b %-e  %I:%M %p
position=50%,center 50%,center
EOF
            ;;
        lightdm-slick-greeter)
            local conf="/etc/lightdm/slick-greeter.conf"
            sudo cp -n "$conf" "${conf}.bak" 2>/dev/null || true
            sudo tee "$conf" > /dev/null <<EOF
[Greeter]
background=$sys_wp
theme-name=$gtk_theme
icon-theme-name=WhiteSur
font-name=$font_name
cursor-theme-name=WhiteSur-cursors
cursor-theme-size=24
EOF
            ;;
        *)
            warn "Unsupported greeter: $greeter — skipping login screen config"
            return 0
            ;;
    esac

    # Leave a marker so we don't overwrite on subsequent runs
    sudo touch "$marker" || warn "sudo touch $marker failed"
    mark_installed "login-screen"
    success "Login screen themed (greeter: $greeter)"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo
    echo -e "${BOLD}════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  macOS ${VARIANT^} theme applied successfully!${RESET}"
    echo -e "${BOLD}════════════════════════════════════════${RESET}"
    echo
    echo "  GTK Theme    : WhiteSur-${VARIANT^}"
    echo "  Icons        : WhiteSur"
    echo "  Cursors      : WhiteSur-cursors"
    echo "  Dock         : Plank (autostart enabled)"
    echo "  Wallpaper    : macOS Sequoia ${VARIANT^}"
    echo "  Top Panel    : macOS-style (24px, 8-plugin, frosted-glass)"
    echo "  Compositor   : picom (dual_kawase blur + shadows)"
    echo "  Browser      : GTK_THEME exported — Firefox chrome theme applied"
    echo "  Spotlight    : rofi (Super+Space) — macOS-style app launcher"
    echo "  Wi-Fi tray   : nm-applet (autostart configured)"
    echo "  Login Screen : LightDM — macOS wallpaper + WhiteSur theme"
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
    configure_browser_theme
    configure_picom
    configure_autostart
    configure_rofi
    configure_login_screen

    print_summary
}

main "$@"
