# GitHub Copilot Instructions

## Project overview

This project automates applying a macOS Sequoia look-and-feel to a fresh
**CachyOS / Arch Linux XFCE** desktop. It installs and configures:

- **WhiteSur GTK theme** (light and dark variants)
- **WhiteSur icon theme** + Apple logo (`start-here.svg`) for the Whisker Menu
- **WhiteSur cursor theme**
- **Inter font** (falls back to system sans-serif on conflict)
- **macOS Sonoma wallpaper** (4k, from `vinceliuice/WhiteSur-wallpapers`)
- **Plank dock** (always-visible, Trash dockitem, macOS-style)
- **XFCE panel** (single top bar mimicking macOS menu bar)
- **LightDM greeter** (login screen theming)

---

## Repository structure

```
install.sh      — main installer (~1000 lines)
uninstall.sh    — reverses all install.sh changes
test.sh         — post-install verification suite
config/         — static assets (whiskermenu RC, picom config, etc.)
README.md
LICENSE
```

---

## Shell scripting conventions

All scripts follow these strict rules:

### Safety flags
Every script starts with:
```bash
set -euo pipefail
```
Never use `&&`-chains for conditionals — use `if` blocks instead, because a
falsy left-hand side under `set -e` will exit the script:

```bash
# BAD — exits the script if the directory doesn't exist
[[ -d "/some/dir" ]] && rm -rf "/some/dir" && echo "done"

# GOOD
if [[ -d "/some/dir" ]]; then
    rm -rf "/some/dir"
    echo "done"
fi
```

### Idempotency — the `guard()` pattern
Every installer step is gated by `guard()`, which skips the step when:
- `--dry-run` is active, OR
- a filesystem condition proves the step is already done AND `--force` is not set

```bash
guard "component-name" -d "$TARGET_DIR" || return 0
# ... do work ...
mark_installed "component-name"
```

`guard` accepts any `test` expression as its second+ arguments. Always prefer
a real filesystem check (`-f`, `-d`) over state-file-only checks.

### Logging helpers
Use the four structured helpers — never raw `echo` for user-facing output:

| Helper      | Colour  | Prefix     | Purpose                        |
|-------------|---------|------------|--------------------------------|
| `info`      | blue    | `[INFO]`   | progress / neutral info        |
| `success`   | green   | `[OK]`     | step completed successfully    |
| `warn`      | yellow  | `[WARN]`   | non-fatal issue, continuing    |
| `error`     | red     | `[ERROR]`  | fatal, writes to stderr        |
| `step`      | bold    | `▶ …`      | major section heading          |

### Package management
- `pacman_install pkg…` — installs from official repos; pre-checks with
  `pacman -Si` and skips unknown packages (never hard-fails on missing packages)
- `aur_install pkg…` — installs from AUR via `paru`/`yay`; silently captures
  output and greps for conflict keywords before printing a clean warning
- Both functions are idempotent: they check `pacman -Qi` before installing

### Process management
Never use `pkill`/`killall` — they are banned in this environment.
Use `pgrep` to find PIDs, then `kill <PID>`:
```bash
PID=$(pgrep -x xfdesktop | head -1)
[[ -n "$PID" ]] && kill "$PID" || true
sleep 0.5
xfdesktop &>/dev/null &
disown
```

---

## Key design decisions

### Panel layout (macOS menu bar)
Single top panel, 28px, position `p=6;x=0;y=0`, semi-transparent dark
background (`rgba 0.1/0.1/0.1/0.82`). Plugin order (left → right):

```
[whiskermenu(Apple)] [←expand→] [clock(center)] [←expand→]
[pulseaudio] [power-manager] [statusnotifier] [systray] [sep] [actions]
```

Plugin IDs in `xfce4-panel.xml` must match RC filenames:
- `plugin-1` → `whiskermenu-1.rc`
- `plugin-3` → `clock-3.rc`

Panel-2 (bottom taskbar) is removed by omitting it from the `panels` array.

### xfconf dual-write strategy
Settings are applied two ways for reliability:
1. **`xfconf-query`** — talks to the live `xfconfd` daemon via DBUS (instant,
   but only works inside an active XFCE session)
2. **XML channel files** (`~/.config/xfce4/xfconf/xfce-perchannel-xml/*.xml`)
   — written directly so settings persist after logout even if DBUS was
   unavailable during the install run

Always do both. The `write_xfce_xml_settings()` function handles the XML side.

### Wallpaper monitor detection
XFCE stores wallpaper per monitor name (e.g. `eDP-2`, not `monitor0`).
Always detect the real monitor name via `xrandr --listmonitors` and augment
with a hardcoded fallback list (`Virtual1`, `monitor0`, `HDMI-1`, `eDP-1`,
`eDP-2`, `HDMI-A-1`, `DP-1`).

### Upstream sources (verified working)
| Asset           | Source                                                      |
|-----------------|-------------------------------------------------------------|
| GTK theme       | `vinceliuice/WhiteSur-gtk-theme` (cloned, `install.sh`)    |
| Icons           | `vinceliuice/WhiteSur-icon-theme` (cloned, `install.sh`)   |
| Cursors         | `vinceliuice/WhiteSur-cursors` (`dist/` layout)            |
| Wallpaper dark  | `vinceliuice/WhiteSur-wallpapers` `4k/Sonoma-dark.jpg`     |
| Wallpaper light | `vinceliuice/WhiteSur-wallpapers` `4k/Sonoma-light.jpg`    |
| Apple icon      | `vinceliuice/WhiteSur-icon-theme` `master` branch `src/places/scalable/start-here.svg` |

> ⚠️ The `dreamer-shan/macOS-Sequoia-Wallpapers` source is **dead (404)** — do
> not use it.

### Plank dock
- `HideMode=0` — always visible (never auto-hide)
- `trash.dockitem` uses `Launcher=trash://` (Plank built-in, shows fill level)
- Desktop trash icon hidden via `xfce4-desktop show-trash=false`

### LightDM login screen
- Detects greeter from `/etc/lightdm/lightdm.conf` (`greeter-session=` key)
- Supports `lightdm-gtk-greeter` and `slick-greeter`
- Copies wallpaper to `/usr/share/backgrounds/macos-sequoia/` (requires sudo)
- Writes marker `/etc/lightdm/.xfce-macos-theme` for idempotency

---

## Testing

`test.sh` is the verification suite. Run after install:

```bash
./test.sh
```

Key checks:
- GTK/icon/cursor theme dirs exist
- xfconf values match expected theme
- `xfce4-panel.xml` contains `whiskermenu` and `statusnotifier`
- `whiskermenu-1.rc` and `clock-3.rc` exist
- `xfce4-pulseaudio-plugin` and `xfce4-whiskermenu-plugin` installed
- LightDM marker + greeter config reference WhiteSur

When adding a new installer step, always add a corresponding `check_*` function
to `test.sh` and call it from `main()`.

---

## Adding a new installer step — checklist

1. Write a function `install_foo()` / `configure_foo()`
2. Gate entry with `guard "foo" -<test> <path> || return 0`
3. Call `mark_installed "foo"` on success
4. Add the function call to `main()` in `install.sh`
5. Add reverse logic to `uninstall.sh` (use `if` blocks, not `&&` chains)
6. Add a `check_foo()` function to `test.sh` and call it from `main()`
7. Run `shellcheck install.sh uninstall.sh test.sh` — must pass with zero warnings
