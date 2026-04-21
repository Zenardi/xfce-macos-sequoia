# XFCE macOS Theme

> Transform your **CachyOS / Arch Linux XFCE** desktop into a pixel-perfect replica of **macOS Sequoia** — complete with WhiteSur GTK theme, matching icons & cursors, Plank dock, and the official Sequoia wallpaper.

![macOS Sequoia XFCE Preview](https://raw.githubusercontent.com/vinceliuice/WhiteSur-gtk-theme/master/preview.png)

---

## What gets installed

| Component | Source |
|-----------|--------|
| **GTK Theme** | [WhiteSur-gtk-theme](https://github.com/vinceliuice/WhiteSur-gtk-theme) |
| **Icon Theme** | [WhiteSur-icon-theme](https://github.com/vinceliuice/WhiteSur-icon-theme) |
| **Cursor Theme** | [WhiteSur-cursors](https://github.com/vinceliuice/WhiteSur-cursors) |
| **Fonts** | [Inter](https://rsms.me/inter/) (closest open-source to SF Pro) via AUR |
| **Wallpaper** | macOS Sequoia (Light or Dark variant) |
| **Dock** | [Plank](https://launchpad.net/plank) |
| **Top Panel** | macOS-style menu bar (whiskermenu, statusnotifier, clock) |
| **Login Screen** | LightDM — macOS wallpaper + WhiteSur GTK/icon theme |
| **XFCE settings** | Applied via `xfconf-query` (theme, icons, cursors, compositor, panel) |

---

## Prerequisites

- **OS:** CachyOS or any Arch-based distro with XFCE
- **AUR helper:** `yay` or `paru` (optional, needed for Inter fonts)
- **Internet connection** (themes are cloned from GitHub on first run)

---

## Quick start

```bash
git clone https://github.com/your-username/xfce-macos-theme.git
cd xfce-macos-theme
chmod +x install.sh uninstall.sh test.sh
./install.sh
```

Log out and back in (or restart XFCE) to fully apply all changes.

---

## Usage

### install.sh

```
./install.sh [OPTIONS]

Options:
  -d, --dark       Install the dark variant (macOS Sequoia Dark)
  -l, --light      Install the light variant (default)
  -n, --dry-run    Preview what would be done — no changes made
  -f, --force      Re-install all components even if already present
  -h, --help       Show help
```

**Examples:**

```bash
# Default light theme
./install.sh

# Dark theme
./install.sh --dark

# Preview without making changes
./install.sh --dry-run

# Re-install everything from scratch
./install.sh --force
```

### uninstall.sh

```
./uninstall.sh [OPTIONS]

Options:
  -n, --dry-run    Preview what would be removed
  -h, --help       Show help
```

```bash
./uninstall.sh         # Remove all theme components
./uninstall.sh --dry-run  # Preview removals
```

### test.sh

Verifies the installation is complete and correct. Run after `install.sh` to confirm everything is working.

```
./test.sh [OPTIONS]

Options:
  -v, --verbose    Print all checks (default: only failures)
  -h, --help       Show help
```

```bash
./test.sh           # Run verification suite
./test.sh --verbose # Show every check result
```

Exit code `0` = all checks passed. Exit code `1` = at least one check failed.

---

## What the installer does

1. **Checks & installs system packages** — `git`, `curl`, `plank`, `gtk-engine-murrine`, `sassc`, `xfce4-whiskermenu-plugin`, `xfce4-statusnotifier-plugin`
2. **Clones and installs WhiteSur GTK theme** into `~/.themes`
3. **Clones and installs WhiteSur icon theme** into `~/.icons`
4. **Clones and installs WhiteSur cursor theme** into `~/.icons`
5. **Installs Inter font** via AUR helper (skipped gracefully if no AUR helper)
6. **Downloads the macOS Sequoia wallpaper** to `~/.local/share/wallpapers/macos-sequoia/`
7. **Configures Plank dock** with macOS-style settings (transparent, autohide, zoom, bottom-center) and adds it to XFCE autostart
8. **Applies XFCE settings** via `xfconf-query`:
   - GTK theme, icon theme, cursor theme, fonts
   - Window manager theme & left-side window buttons (macOS style)
   - Compositor enabled for smooth rendering
   - Top panel configured as macOS menu bar (whiskermenu + statusnotifier + clock)
   - Writes `xfce4-panel.xml` so only panel-1 (top bar) is listed — panel-2 (bottom taskbar) is hidden
9. **Writes GTK-2 / GTK-3 / GTK-4 config files** for apps that don't respect xfconf
10. **Themes the LightDM login screen** — copies wallpaper and WhiteSur theme/icons to system directories, writes greeter config

---

## Login Screen

The installer automatically themes the **LightDM** greeter (both `lightdm-gtk-greeter` and `lightdm-slick-greeter` are supported). This step requires `sudo` for the following operations:

- Copying the macOS Sequoia wallpaper to `/usr/share/backgrounds/macos-sequoia/`
- Installing the WhiteSur GTK theme to `/usr/share/themes/` (so the greeter can read it)
- Installing the WhiteSur icon theme to `/usr/share/icons/`
- Writing `/etc/lightdm/lightdm-gtk-greeter.conf` (or `slick-greeter.conf`)

The original greeter config is backed up to `<conf>.bak` before overwriting. The uninstaller restores the backup automatically.

If `sudo` is unavailable or fails, the login screen step emits warnings and continues — it will not abort the installation.

---

## Idempotency

The installer tracks installed components in:

```
~/.local/share/xfce-macos-theme/.installed
```

Re-running `./install.sh` without `--force` will skip already-installed components, making it safe to run multiple times or after partial failures.

---

## File layout

```
xfce-macos-theme/
├── install.sh       # Main installer (idempotent)
├── uninstall.sh     # Removes all changes
├── test.sh          # Verification suite
└── README.md        # This file
```

Theme assets and configs are downloaded/generated at runtime and live entirely inside your home directory — with the exception of the login screen step, which writes to `/etc/lightdm/`, `/usr/share/backgrounds/macos-sequoia/`, `/usr/share/themes/` and `/usr/share/icons/` using `sudo`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Wallpaper not changing | Log out and back in; or right-click desktop → Desktop Settings |
| Old icons still showing | Run `gtk-update-icon-cache ~/.icons/WhiteSur` and re-log |
| Plank not starting | Run `plank &` manually, check autostart: `~/.config/autostart/plank.desktop` |
| Theme reverts after reboot | Ensure `xfce4-session` is managing your session correctly |
| Inter font not found | Install manually: `yay -S ttf-inter` |

---

## Uninstalling

```bash
./uninstall.sh
```

This removes all theme files, restores XFCE settings to Adwaita defaults, and clears the state file. A log-out/in is needed to fully revert.

---

## License

Scripts in this repository are released under the [MIT License](LICENSE).
The bundled themes (WhiteSur) are © [Vince Liuice](https://github.com/vinceliuice) — see their respective licenses.
