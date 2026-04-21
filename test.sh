#!/usr/bin/env bash
# =============================================================================
# test.sh — XFCE macOS Theme Verification Suite
#
# Checks that all theme components are properly installed and applied.
# Exits 0 if everything is in order, 1 if any check fails.
#
# Usage:
#   ./test.sh [OPTIONS]
#
# Options:
#   -v, --verbose    Print every check (default: only failures)
#   -h, --help       Show this help message
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

VERBOSE=false
PASS=0
FAIL=0
WARN_COUNT=0

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help)    grep '^#' "$0" | grep -E '(Usage|Options|  -|--)' | sed 's/^# //'; exit 0 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done
}

# ── Test helpers ──────────────────────────────────────────────────────────────
pass() {
    PASS=$((PASS + 1))
    $VERBOSE && echo -e "  ${GREEN}✔${RESET} $*"
}

fail() {
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}✘${RESET} $*"
}

warn_check() {
    WARN_COUNT=$((WARN_COUNT + 1))
    echo -e "  ${YELLOW}⚠${RESET} $*"
}

section() {
    echo -e "\n${BOLD}$*${RESET}"
}

# Checks that a directory exists
assert_dir() {
    local dir="$1" label="${2:-$1}"
    if [[ -d "$dir" ]]; then
        pass "$label exists"
    else
        fail "$label NOT found: $dir"
    fi
}

# Checks that a file exists
assert_file() {
    local file="$1" label="${2:-$1}"
    if [[ -f "$file" ]]; then
        pass "$label exists"
    else
        fail "$label NOT found: $file"
    fi
}

# Checks an xfconf-query value
assert_xfconf() {
    local channel="$1"
    local prop="$2"
    local expected="$3"
    local label="${4:-$prop}"
    local actual
    actual=$(xfconf-query -c "$channel" -p "$prop" 2>/dev/null || echo "__UNSET__")
    if [[ "$actual" == "$expected" ]]; then
        pass "xfconf $channel $prop = $expected"
    else
        fail "$label: expected '$expected', got '$actual'"
    fi
}

# Checks that a command exists
assert_cmd() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        pass "Command available: $cmd"
    else
        fail "Command not found: $cmd"
    fi
}

# Checks that xfconf-query is callable (required for many checks)
check_xfconf_available() {
    if ! command -v xfconf-query &>/dev/null; then
        warn_check "xfconf-query not found — XFCE settings checks will be skipped"
        return 1
    fi
    return 0
}

# ── Individual checks ─────────────────────────────────────────────────────────

check_required_commands() {
    section "Required commands"
    assert_cmd git
    assert_cmd curl
    assert_cmd plank
    assert_cmd xfconf-query
    assert_cmd fc-list
}

check_gtk_theme() {
    section "GTK theme — WhiteSur"
    local base="$HOME/.themes"
    local found=false
    for variant in Light Dark; do
        if [[ -d "$base/WhiteSur-$variant" ]]; then
            pass "Theme directory: $base/WhiteSur-$variant"
            assert_file "$base/WhiteSur-$variant/index.theme" "WhiteSur-$variant index.theme"
            found=true
        fi
    done
    $found || fail "No WhiteSur theme found in $base"
}

check_icons() {
    section "Icon theme — WhiteSur"
    local dir="$HOME/.icons/WhiteSur"
    assert_dir "$dir" "WhiteSur icons"
    assert_file "$dir/index.theme" "WhiteSur icons index.theme"
}

check_cursors() {
    section "Cursor theme — WhiteSur-cursors"
    local dir="$HOME/.icons/WhiteSur-cursors"
    assert_dir "$dir" "WhiteSur-cursors"
    assert_dir "$dir/cursors" "WhiteSur-cursors/cursors"
}

check_wallpaper() {
    section "Wallpaper — macOS Sequoia"
    local dir="$HOME/.local/share/wallpapers/macos-sequoia"
    assert_dir "$dir" "Wallpaper directory"
    local found=false
    for wp in "$dir"/*.jpg "$dir"/*.png; do
        [[ -f "$wp" ]] && found=true && pass "Wallpaper file: $wp"
    done
    $found || fail "No wallpaper image found in $dir"
}

check_plank() {
    section "Plank dock"
    assert_cmd plank
    assert_file "$HOME/.config/autostart/plank.desktop" "Plank autostart"
    assert_dir  "$HOME/.config/plank/dock1"              "Plank config dir"
    assert_file "$HOME/.config/plank/dock1/settings"     "Plank settings file"
}

check_xfce_settings() {
    section "XFCE xfconf settings"
    check_xfconf_available || return 0

    local theme
    theme=$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || echo "")
    if [[ "$theme" == WhiteSur* ]]; then
        pass "GTK theme set: $theme"
    else
        fail "GTK theme not set to WhiteSur (got: '${theme:-<unset>}')"
    fi

    local icons
    icons=$(xfconf-query -c xsettings -p /Net/IconThemeName 2>/dev/null || echo "")
    if [[ "$icons" == WhiteSur* ]]; then
        pass "Icon theme set: $icons"
    else
        fail "Icon theme not set to WhiteSur (got: '${icons:-<unset>}')"
    fi

    local cursor
    cursor=$(xfconf-query -c xsettings -p /Gtk/CursorThemeName 2>/dev/null || echo "")
    if [[ "$cursor" == WhiteSur* ]]; then
        pass "Cursor theme set: $cursor"
    else
        fail "Cursor theme not set to WhiteSur (got: '${cursor:-<unset>}')"
    fi

    local wm_theme
    wm_theme=$(xfconf-query -c xfwm4 -p /general/theme 2>/dev/null || echo "")
    if [[ "$wm_theme" == WhiteSur* ]]; then
        pass "WM theme set: $wm_theme"
    else
        fail "WM theme not set to WhiteSur (got: '${wm_theme:-<unset>}')"
    fi

    local btn_layout
    btn_layout=$(xfconf-query -c xfwm4 -p /general/button_layout 2>/dev/null || echo "")
    # macOS buttons are on the left — expect close/min/max before the pipe
    if [[ "$btn_layout" =~ ^C ]]; then
        pass "Window buttons on left (macOS style): $btn_layout"
    else
        warn_check "Window buttons may not be in macOS style: '$btn_layout'"
    fi

    assert_xfconf xfwm4 /general/use_compositing "true" "Compositor"
}

check_gtk_config_files() {
    section "GTK config files"
    assert_file "$HOME/.config/gtk-3.0/settings.ini" "GTK-3 settings.ini"
    assert_file "$HOME/.config/gtk-4.0/settings.ini" "GTK-4 settings.ini"

    # Verify theme reference inside the file
    if grep -q "WhiteSur" "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null; then
        pass "gtk-3.0/settings.ini references WhiteSur"
    else
        fail "gtk-3.0/settings.ini does not reference WhiteSur"
    fi
}

check_fonts() {
    section "Fonts"
    if fc-list | grep -qi "Inter"; then
        pass "Inter font available"
    else
        warn_check "Inter font not found — UI uses fallback sans-serif"
    fi
}

check_panel() {
    section "XFCE panel (macOS layout)"
    local xfconf_dir="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    assert_file "$xfconf_dir/xfce4-panel.xml" "xfce4-panel.xml"

    # Verify the XML removes panel-2 (only panel-1 listed)
    if [[ -f "$xfconf_dir/xfce4-panel.xml" ]]; then
        if grep -q 'value="1"' "$xfconf_dir/xfce4-panel.xml" && \
           ! grep -q 'panel-2' "$xfconf_dir/xfce4-panel.xml"; then
            pass "Panel XML: only panel-1 defined (bottom taskbar removed)"
        else
            warn_check "Panel XML may still reference panel-2"
        fi
        if grep -q 'whiskermenu' "$xfconf_dir/xfce4-panel.xml"; then
            pass "Panel XML: whiskermenu plugin defined"
        else
            fail "Panel XML: whiskermenu plugin NOT found"
        fi
        if grep -q 'statusnotifier' "$xfconf_dir/xfce4-panel.xml"; then
            pass "Panel XML: statusnotifier plugin defined"
        else
            fail "Panel XML: statusnotifier plugin NOT found"
        fi
    fi

    assert_file "$HOME/.config/xfce4/panel/whiskermenu-1.rc" "whiskermenu-1.rc"
    assert_file "$HOME/.config/xfce4/panel/clock-5.rc"       "clock-5.rc"

    # Verify plugins are installed
    if pacman -Qi xfce4-whiskermenu-plugin &>/dev/null 2>&1; then
        pass "Package installed: xfce4-whiskermenu-plugin"
    else
        fail "Package NOT installed: xfce4-whiskermenu-plugin"
    fi
    if pacman -Qi xfce4-statusnotifier-plugin &>/dev/null 2>&1; then
        pass "Package installed: xfce4-statusnotifier-plugin"
    else
        fail "Package NOT installed: xfce4-statusnotifier-plugin"
    fi
}

check_login_screen() {
    section "Login screen (LightDM)"
    local marker="/etc/lightdm/.xfce-macos-theme"
    if [[ -f "$marker" ]]; then
        pass "Login screen marker present (configure_login_screen ran)"
    else
        warn_check "Login screen not configured yet (run ./install.sh)"
        return 0
    fi

    # Check whichever greeter config was written
    if [[ -f /etc/lightdm/lightdm-gtk-greeter.conf ]]; then
        if grep -q "WhiteSur" /etc/lightdm/lightdm-gtk-greeter.conf 2>/dev/null; then
            pass "lightdm-gtk-greeter.conf references WhiteSur theme"
        else
            fail "lightdm-gtk-greeter.conf does not reference WhiteSur"
        fi
        if grep -q "macos-sequoia" /etc/lightdm/lightdm-gtk-greeter.conf 2>/dev/null; then
            pass "lightdm-gtk-greeter.conf references macOS wallpaper"
        else
            warn_check "lightdm-gtk-greeter.conf: wallpaper path not found"
        fi
    elif [[ -f /etc/lightdm/slick-greeter.conf ]]; then
        if grep -q "WhiteSur" /etc/lightdm/slick-greeter.conf 2>/dev/null; then
            pass "slick-greeter.conf references WhiteSur theme"
        else
            fail "slick-greeter.conf does not reference WhiteSur"
        fi
    else
        warn_check "No greeter config found in /etc/lightdm/"
    fi

    if [[ -d /usr/share/backgrounds/macos-sequoia ]]; then
        pass "System wallpaper dir: /usr/share/backgrounds/macos-sequoia"
    else
        warn_check "System wallpaper not copied yet"
    fi
}


check_state_file() {
    section "Installation state"
    local state="$HOME/.local/share/xfce-macos-theme/.installed"
    if [[ -f "$state" ]]; then
        pass "State file present: $state"
        local components
        components=$(wc -l < "$state")
        pass "Recorded components: $components"
    else
        warn_check "State file not found (was install.sh run?)"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo -e "${BOLD}"
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   XFCE macOS Theme — Test Suite     │"
    echo "  └─────────────────────────────────────┘"
    echo -e "${RESET}"

    check_required_commands
    check_gtk_theme
    check_icons
    check_cursors
    check_wallpaper
    check_plank
    check_panel
    check_login_screen
    check_xfce_settings
    check_gtk_config_files
    check_fonts
    check_state_file

    # ── Summary ───────────────────────────────────────────────────────────────
    echo
    echo -e "${BOLD}════ Results ════${RESET}"
    echo -e "  ${GREEN}Passed : $PASS${RESET}"
    if [[ $FAIL -gt 0 ]]; then
        echo -e "  ${RED}Failed : $FAIL${RESET}"
    fi
    if [[ $WARN_COUNT -gt 0 ]]; then
        echo -e "  ${YELLOW}Warnings: $WARN_COUNT${RESET}"
    fi
    echo

    if [[ $FAIL -gt 0 ]]; then
        echo -e "${RED}Some checks failed. Run ./install.sh to fix missing components.${RESET}"
        exit 1
    else
        echo -e "${GREEN}${BOLD}All checks passed!${RESET}"
        exit 0
    fi
}

main "$@"
