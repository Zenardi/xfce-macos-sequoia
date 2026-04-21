#!/usr/bin/env bash
# =============================================================================
# uninstall.sh — XFCE macOS Theme Uninstaller
#
# Reverses all changes made by install.sh: removes themes, icons, cursors,
# fonts and restores original XFCE settings from backup.
#
# Usage:
#   ./uninstall.sh [OPTIONS]
#
# Options:
#   -n, --dry-run    Show what would be removed without making changes
#   -h, --help       Show this help message
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
step()    { echo -e "\n${BOLD}▶ $*${RESET}"; }

DRY_RUN=false

THEMES_DIR="$HOME/.themes"
ICONS_DIR="$HOME/.icons"
WALLPAPER_DIR="$HOME/.local/share/wallpapers/macos-sequoia"
STATE_FILE="$HOME/.local/share/xfce-macos-theme/.installed"

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run) DRY_RUN=true; shift ;;
            -h|--help)    grep '^#' "$0" | grep -E '(Usage|Options|  -|--)' | sed 's/^# //'; exit 0 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done
}

run() {
    if $DRY_RUN; then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

remove_themes() {
    step "Removing GTK theme"
    for variant in Light Dark; do
        if [[ -d "$THEMES_DIR/WhiteSur-$variant" ]]; then
            run rm -rf "$THEMES_DIR/WhiteSur-$variant"
            success "Removed: WhiteSur-$variant"
        fi
    done
}

remove_icons() {
    step "Removing icon theme"
    if [[ -d "$ICONS_DIR/WhiteSur" ]]; then
        run rm -rf "$ICONS_DIR/WhiteSur"
        success "Removed: WhiteSur icons"
    fi
}

remove_cursors() {
    step "Removing cursor theme"
    if [[ -d "$ICONS_DIR/WhiteSur-cursors" ]]; then
        run rm -rf "$ICONS_DIR/WhiteSur-cursors"
        success "Removed: WhiteSur-cursors"
    fi
    if [[ -d "$ICONS_DIR/default" ]]; then
        run rm -rf "$ICONS_DIR/default"
        success "Removed: default cursor override"
    fi
}

remove_wallpaper() {
    step "Removing wallpaper"
    if [[ -d "$WALLPAPER_DIR" ]]; then
        run rm -rf "$WALLPAPER_DIR"
        success "Removed: macOS Sequoia wallpapers"
    fi
}

remove_plank_autostart() {
    step "Removing Plank autostart"
    local autostart="$HOME/.config/autostart/plank.desktop"
    if [[ -f "$autostart" ]]; then
        run rm -f "$autostart"
        success "Removed Plank autostart entry"
    fi
}

restore_xfce_settings() {
    step "Restoring XFCE settings to system defaults"
    warn "Restoring XFCE appearance settings to defaults..."

    xfconf-query -c xsettings -p /Net/ThemeName           -s "Adwaita"       --create -t string
    xfconf-query -c xsettings -p /Net/IconThemeName        -s "hicolor"       --create -t string
    xfconf-query -c xsettings -p /Gtk/CursorThemeName      -s "Adwaita"       --create -t string
    xfconf-query -c xsettings -p /Gtk/FontName             -s "Sans Regular 11" --create -t string
    xfconf-query -c xfwm4     -p /general/theme            -s "Default"       --create -t string
    # Restore button layout to standard (right side)
    xfconf-query -c xfwm4     -p /general/button_layout    -s "|HMC"          --create -t string

    success "XFCE settings restored to defaults"
}

restore_gtk_configs() {
    step "Removing GTK config overrides"
    run rm -f "$HOME/.gtkrc-2.0"
    run rm -f "$HOME/.config/gtk-3.0/settings.ini"
    run rm -f "$HOME/.config/gtk-4.0/settings.ini"
    success "GTK config files removed"
}

restore_panel() {
    step "Restoring default XFCE panel configuration"
    local panel_xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    if [[ -f "$panel_xml" ]]; then
        run rm -f "$panel_xml"
        success "Removed custom xfce4-panel.xml (XFCE will recreate defaults on next login)"
    fi
    run rm -f "$HOME/.config/xfce4/panel/whiskermenu-1.rc"
    run rm -f "$HOME/.config/xfce4/panel/clock-3.rc"
    run rm -f "$HOME/.config/xfce4/panel/clock-5.rc"  # legacy name from older installs
    success "Panel plugin RC files removed"
}

restore_login_screen() {
    step "Restoring login screen (LightDM)"
    local marker="/etc/lightdm/.xfce-macos-theme"

    # Restore gtk-greeter config
    local gtk_conf="/etc/lightdm/lightdm-gtk-greeter.conf"
    if [[ -f "${gtk_conf}.bak" ]]; then
        run sudo cp -f "${gtk_conf}.bak" "$gtk_conf"
        run sudo rm -f "${gtk_conf}.bak"
        success "Restored $gtk_conf from backup"
    elif [[ -f "$gtk_conf" ]]; then
        run sudo rm -f "$gtk_conf"
        success "Removed $gtk_conf"
    fi

    # Restore slick-greeter config
    local slick_conf="/etc/lightdm/slick-greeter.conf"
    if [[ -f "${slick_conf}.bak" ]]; then
        run sudo cp -f "${slick_conf}.bak" "$slick_conf"
        run sudo rm -f "${slick_conf}.bak"
        success "Restored $slick_conf from backup"
    elif [[ -f "$slick_conf" ]]; then
        run sudo rm -f "$slick_conf"
        success "Removed $slick_conf"
    fi

    # Remove marker
    if [[ -f "$marker" ]]; then
        run sudo rm -f "$marker"
    fi

    # Remove system-wide wallpaper copy
    if [[ -d "/usr/share/backgrounds/macos-sequoia" ]]; then
        run sudo rm -rf "/usr/share/backgrounds/macos-sequoia"
        success "Removed /usr/share/backgrounds/macos-sequoia"
    fi

    # Remove system-wide theme copies (only if we installed them)
    for variant in Light Dark; do
        if [[ -d "/usr/share/themes/WhiteSur-$variant" ]]; then
            run sudo rm -rf "/usr/share/themes/WhiteSur-$variant"
            success "Removed /usr/share/themes/WhiteSur-$variant"
        fi
    done

    # Remove system-wide icon copy
    if [[ -d "/usr/share/icons/WhiteSur" ]]; then
        run sudo rm -rf "/usr/share/icons/WhiteSur"
        success "Removed /usr/share/icons/WhiteSur"
    fi
}

remove_state() {
    step "Clearing installation state"
    if [[ -f "$STATE_FILE" ]]; then
        run rm -f "$STATE_FILE"
        success "State file removed"
    fi
}

main() {
    parse_args "$@"

    echo -e "${BOLD}"
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   XFCE macOS Theme Uninstaller      │"
    echo "  └─────────────────────────────────────┘"
    echo -e "${RESET}"

    if $DRY_RUN; then
        warn "DRY-RUN mode — no changes will be made"
    fi

    remove_themes
    remove_icons
    remove_cursors
    remove_wallpaper
    remove_plank_autostart
    restore_xfce_settings
    restore_gtk_configs
    restore_panel
    restore_login_screen
    remove_state

    echo
    echo -e "${GREEN}${BOLD}  Uninstall complete.${RESET}"
    echo -e "${YELLOW}  Log out and back in to fully apply changes.${RESET}"
    echo
}

main "$@"
