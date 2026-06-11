# Tiler

A tiny local macOS menu bar app that snaps your windows into custom layouts.
Define tiles (as fractions of a screen), map apps to tiles, and apply a layout
from the menu bar or a global hotkey. Built for ultrawide screens, works with
any number of displays.

## Visual layout editor

Menu bar icon → **Edit Layouts…** opens the editor:

- The canvas shows your screen as a snapping **grid** — click and drag to draw
  a tile, drag a tile to move it, drag its edges/corners to resize.
- Select a tile and use the inspector to **assign apps** (pick from running
  apps with icons, or browse /Applications).
- Manage multiple **layouts** in the sidebar (duplicate, delete), give each a
  name and a **global hotkey**.
- Pick the **grid density** (coarse / medium / fine) and switch between
  screens if you have more than one.
- **Apply** previews the layout on your real windows instantly; **⌘S** saves.
- ⌫ deletes the selected tile, Esc deselects.

Everything is stored in the same `config.json`, so you can still edit it by
hand if you prefer.

## Active layout & slots

Applying a layout (menu, hotkey, or the editor's Apply button) makes it the
**active layout** — marked with a checkmark in the menu. While active, its
tiles act as **slots**:

- **Drag a window** — as soon as the window starts moving, all slots show a
  dashed outline and the slot under your cursor lights up with an accent
  highlight. Release inside it to snap the window there; release outside any
  slot to place the window freely.
- **⌃⌥ ← → ↑ ↓** moves the focused window to the nearest slot in that
  direction.
- Menu → **Deactivate Layout** turns slot behavior off.

## Window placement rules

For each app in a layout:

| Situation | Behavior |
|-----------|----------|
| 1 tile | The app's main window goes in the tile |
| 1 tile + "all windows" | Every window goes in that tile |
| Multiple tiles, multiple windows | Windows are distributed across the tiles (extras stack round-robin) |
| Multiple tiles, **one** window | The window spans the union of all its tiles (fallback) |

A layout can also set **"Minimize other windows"** (`"hideOthers": true` in
JSON): applying it minimizes every window the layout doesn't place.

## Security & privacy

Tiler is local-only by design. The threat model and guarantees:

**No network access.** The app contains no networking code and links no
networking frameworks. Verify yourself:

```sh
otool -L /Applications/Tiler.app/Contents/MacOS/Tiler   # no network libs
```

**No sensitive data.** Tiler stores exactly one file,
`~/.config/tiler/config.json` (created with `600` permissions, written
atomically) containing only layout geometry and app identifiers — never
credentials, window contents, or keystrokes.

**Minimal Accessibility usage.** The Accessibility permission is powerful,
so Tiler deliberately reads only window *geometry* attributes (position,
size, subrole, minimized state) — never window titles, text content, or
values. The global mouse monitor only observes drag/up events to detect
window drags; there is no keystroke monitoring outside Tiler's own editor
window. Nothing observed is ever persisted or transmitted.

**Hardened against injection.** The binary is signed with the hardened
runtime (`codesign --options runtime`), which blocks `DYLD_*` environment
injection, loading of unsigned libraries, and debugger attachment — so the
app's Accessibility privileges can't be hijacked by another local process.
Verify with:

```sh
codesign -d --verbose=2 /Applications/Tiler.app   # flags should include "runtime"
```

**No remote entry points.** No URL scheme, no XPC services, no AppleScript
dictionary, no listening sockets, no shell execution (`Process`/`system` are
never used).

**Why not sandboxed?** The App Sandbox forbids controlling other apps'
windows via the Accessibility API — the core feature. This is the same
tradeoff every macOS window manager (Rectangle, AeroSpace, etc.) makes.

## Build & install

```sh
./build.sh
cp -r build/Tiler.app /Applications/
open /Applications/Tiler.app
```

On first launch macOS will ask you to grant **Accessibility** access
(System Settings → Privacy & Security → Accessibility). This is required to
move other apps' windows.

> **Note:** the app is ad-hoc signed. After rebuilding, macOS may treat it as a
> new app and you'll need to re-toggle the Accessibility permission (remove and
> re-add Tiler in the list).

To start at login: System Settings → General → Login Items → add Tiler.

## Configuration

Config lives at `~/.config/tiler/config.json`. A default is created on first
launch. The visual editor (**Edit Layouts…**) is the easiest way to change it,
but you can also edit the file directly (menu → **Open Config File**, then
**Reload Config**).

```json
{
  "layouts": [
    {
      "name": "Coding",
      "hotkey": "ctrl+alt+1",
      "tiles": [
        { "id": "left",   "x": 0.0,  "y": 0.0, "w": 0.25, "h": 1.0 },
        { "id": "center", "x": 0.25, "y": 0.0, "w": 0.5,  "h": 1.0 },
        { "id": "right",  "x": 0.75, "y": 0.0, "w": 0.25, "h": 1.0 }
      ],
      "assignments": [
        { "app": "com.google.Chrome", "tile": "left" },
        { "app": "dev.zed.Zed",       "tile": "center" },
        { "app": "Terminal",          "tile": "right" }
      ]
    }
  ]
}
```

### Layout options

| Field | Meaning |
|-------|---------|
| `name` | Display name |
| `hotkey` | Optional global shortcut (see below) |
| `hideOthers` | Optional. `true` = minimize all windows the layout doesn't place |

### Tiles

| Field | Meaning |
|-------|---------|
| `id` | Name used by assignments |
| `x`, `y` | Top-left corner as a fraction of the screen (0,0 = top-left) |
| `w`, `h` | Size as a fraction of the screen |
| `screen` | Optional screen index, ordered left → right (default `0`) |

Tiles are placed inside the screen's *visible* frame, so the menu bar and Dock
are automatically respected.

### Assignments

| Field | Meaning |
|-------|---------|
| `app` | Bundle identifier (preferred, e.g. `com.google.Chrome`) or app name (e.g. `Terminal`) |
| `tile` | The tile `id` to place the window in |
| `allWindows` | Optional. `true` = move all the app's windows; default moves only the main window |

To find an app's bundle identifier:

```sh
osascript -e 'id of app "Google Chrome"'
```

### Hotkeys

Optional per layout. Format: modifiers joined with `+`, e.g. `ctrl+alt+1`,
`cmd+shift+f1`, `ctrl+alt+left`. Supported modifiers: `cmd`, `ctrl`, `alt`/`opt`,
`shift`. Keys: letters, digits, `f1`–`f12`, arrows, `space`, `return`, `tab`,
`esc`, and common punctuation.

## How it works

Tiler uses the macOS Accessibility API (`AXUIElement`) to enumerate and move
windows of other apps, and Carbon `RegisterEventHotKey` for global hotkeys.
No private APIs, no SIP changes needed.

## Tips

- Apps that aren't running are simply skipped (logged to Console).
- Minimized windows are unminimized before being placed.
- Some apps enforce minimum window sizes; tiles smaller than that will be
  clamped by the app itself.
