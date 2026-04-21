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

# Wrapper that respects --dry-run and --force
should_run() {
    local component="$1"
    if $DRY_RUN; then
        info "[dry-run] Would install: $component"
        return 1  # skip actual work
    fi
    if ! $FORCE && is_installed "$component"; then
        info "Already installed (skip): $component — use --force to reinstall"
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

# Installs one or more pacman packages (skips if already present)
pacman_install() {
    local pkgs=("$@")
    local missing=()
    for pkg in "${pkgs[@]}"; do
        pacman -Qi "$pkg" &>/dev/null || missing+=("$pkg")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0
    info "Installing packages: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
}

# Installs one or more AUR packages
aur_install() {
    if [[ -z "$AUR_HELPER" ]]; then
        warn "No AUR helper (yay/paru) found — skipping AUR package: $*"
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

# ── 1. System dependencies ────────────────────────────────────────────────────
install_dependencies() {
    step "System dependencies"
    should_run "dependencies" || return 0

    pacman_install git curl wget plank xfconf gtk-engine-murrine sassc
    # Optionally install SF Pro equivalent fonts from AUR
    if [[ -n "$AUR_HELPER" ]]; then
        aur_install ttf-inter || warn "ttf-inter AUR install failed — will fall back to system sans-serif"
    fi

    mark_installed "dependencies"
    success "Dependencies ready"
}

# ── 2. GTK theme (WhiteSur) ───────────────────────────────────────────────────
install_gtk_theme() {
    step "GTK theme — WhiteSur"
    should_run "gtk-theme" || return 0

    local dest="$TMP_DIR/WhiteSur-gtk-theme"
    info "Cloning WhiteSur GTK theme..."
    git clone --depth=1 "$GTK_THEME_REPO" "$dest"

    mkdir -p "$THEMES_DIR"
    # The installer script copies themes to ~/.themes
    bash "$dest/install.sh" \
        --dest "$THEMES_DIR" \
        --color "${VARIANT^}" \
        --nautilus-style mojave \
        --round

    # Also install the GDM/login theme for completeness (optional, needs sudo)
    # bash "$dest/tweaks.sh" -g   # uncomment if you want GDM styling

    mark_installed "gtk-theme"
    success "GTK theme installed: WhiteSur-${VARIANT^}"
}

# ── 3. Icon theme (WhiteSur) ──────────────────────────────────────────────────
install_icons() {
    step "Icon theme — WhiteSur"
    should_run "icons" || return 0

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
    should_run "cursors" || return 0

    local dest="$TMP_DIR/WhiteSur-cursors"
    info "Cloning WhiteSur cursor theme..."
    git clone --depth=1 "$CURSOR_THEME_REPO" "$dest"

    mkdir -p "$ICONS_DIR"
    # Cursor themes live in ~/.icons/<name>
    cp -r "$dest/dist/WhiteSur-cursors" "$ICONS_DIR/"

    # Register default cursor via index.theme
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
    should_run "fonts" || return 0

    mkdir -p "$FONTS_DIR"

    # Try to install Inter from AUR (closest open-source to SF Pro)
    if [[ -n "$AUR_HELPER" ]]; then
        aur_install ttf-inter 2>/dev/null || true
    fi

    # Rebuild font cache
    fc-cache -f "$FONTS_DIR"

    mark_installed "fonts"
    success "Fonts configured"
}

# ── 6. Wallpaper ──────────────────────────────────────────────────────────────
install_wallpaper() {
    step "Wallpaper — macOS Sequoia"
    should_run "wallpaper" || return 0

    mkdir -p "$WALLPAPER_DIR"

    local url filename
    if [[ "$VARIANT" == "dark" ]]; then
        url="$WALLPAPER_DARK_URL"
        filename="sequoia-dark.jpg"
    else
        url="$WALLPAPER_URL"
        filename="sequoia-light.jpg"
    fi

    local dest="$WALLPAPER_DIR/$filename"

    if [[ ! -f "$dest" ]] || $FORCE; then
        info "Downloading macOS Sequoia wallpaper..."
        if ! curl -fsSL --retry 3 -o "$dest" "$url"; then
            warn "Primary wallpaper download failed — trying fallback..."
            # Fallback: generate a simple gradient placeholder
            if command -v convert &>/dev/null; then
                if [[ "$VARIANT" == "dark" ]]; then
                    convert -size 3840x2160 gradient:'#1a1a2e-#16213e' "$dest" 2>/dev/null || true
                else
                    convert -size 3840x2160 gradient:'#e8eaf6-#9fa8da' "$dest" 2>/dev/null || true
                fi
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
    should_run "plank" || return 0

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
    should_run "xfce-settings" || return 0

    # Backup current settings
    mkdir -p "$BACKUP_DIR"
    xfconf-query -c xsettings -l 2>/dev/null > "$BACKUP_DIR/xsettings.txt" || true
    xfconf-query -c xfwm4    -l 2>/dev/null > "$BACKUP_DIR/xfwm4.txt"    || true
    xfconf-query -c xfce4-desktop -l 2>/dev/null > "$BACKUP_DIR/xfce4-desktop.txt" || true

    local gtk_theme icon_theme font_name wm_theme cursor_theme

    if [[ "$VARIANT" == "dark" ]]; then
        gtk_theme="WhiteSur-Dark"
        wm_theme="WhiteSur-Dark"
    else
        gtk_theme="WhiteSur-Light"
        wm_theme="WhiteSur-Light"
    fi
    icon_theme="WhiteSur"
    cursor_theme="WhiteSur-cursors"

    # Detect best available font
    if fc-list | grep -qi "Inter"; then
        font_name="Inter Regular 13"
    elif fc-list | grep -qi "SF Pro"; then
        font_name="SF Pro Display Regular 13"
    else
        font_name="Sans Regular 13"
    fi

    info "Applying GTK theme: $gtk_theme"
    xfconf-query -c xsettings -p /Net/ThemeName         -s "$gtk_theme"     --create -t string
    xfconf-query -c xsettings -p /Net/IconThemeName      -s "$icon_theme"    --create -t string
    xfconf-query -c xsettings -p /Gtk/CursorThemeName    -s "$cursor_theme"  --create -t string
    xfconf-query -c xsettings -p /Gtk/CursorThemeSize    -s 24               --create -t int
    xfconf-query -c xsettings -p /Gtk/FontName           -s "$font_name"     --create -t string
    xfconf-query -c xsettings -p /Gtk/MonospaceFontName  -s "Monospace Regular 12" --create -t string
    xfconf-query -c xsettings -p /Xft/Antialias          -s 1                --create -t int
    xfconf-query -c xsettings -p /Xft/Hinting            -s 1                --create -t int
    xfconf-query -c xsettings -p /Xft/HintStyle          -s "hintslight"     --create -t string
    xfconf-query -c xsettings -p /Xft/RGBA               -s "rgb"            --create -t string

    info "Applying window manager theme: $wm_theme"
    xfconf-query -c xfwm4 -p /general/theme              -s "$wm_theme"      --create -t string
    xfconf-query -c xfwm4 -p /general/title_font         -s "$font_name"     --create -t string
    xfconf-query -c xfwm4 -p /general/button_layout      -s "C|HM"           --create -t string
    # Buttons on the left (macOS style: close/min/max on left)
    xfconf-query -c xfwm4 -p /general/button_layout      -s "CMH|"           --create -t string

    # Wallpaper — iterate over all monitors and workspaces
    if [[ -n "${WALLPAPER_PATH:-}" && -f "${WALLPAPER_PATH:-}" ]]; then
        info "Setting wallpaper: $WALLPAPER_PATH"
        local screen_prop
        for screen_prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "last-image" || true); do
            xfconf-query -c xfce4-desktop -p "$screen_prop" -s "$WALLPAPER_PATH" --create -t string
        done
        # Also set via common default path
        xfconf-query -c xfce4-desktop \
            -p /backdrop/screen0/monitorVirtual1/workspace0/last-image \
            -s "$WALLPAPER_PATH" --create -t string 2>/dev/null || true
        xfconf-query -c xfce4-desktop \
            -p /backdrop/screen0/monitor0/workspace0/last-image \
            -s "$WALLPAPER_PATH" --create -t string 2>/dev/null || true
        xfconf-query -c xfce4-desktop \
            -p /backdrop/screen0/monitorHDMI-1/workspace0/last-image \
            -s "$WALLPAPER_PATH" --create -t string 2>/dev/null || true
    fi

    # Compositor — enable for smooth macOS feel
    xfconf-query -c xfwm4 -p /general/use_compositing      -s true  --create -t bool
    xfconf-query -c xfwm4 -p /general/frame_opacity         -s 85    --create -t int
    xfconf-query -c xfwm4 -p /general/inactive_opacity      -s 95    --create -t int

    # Taskbar / Panel: move panel to top (macOS menu-bar style)
    configure_xfce_panel

    mark_installed "xfce-settings"
    success "XFCE settings applied"
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
    should_run "gtk2" || return 0

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
