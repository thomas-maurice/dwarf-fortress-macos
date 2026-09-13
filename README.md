# Dwarf Fortress (Steam) + DFHack on Apple Silicon

Running the Steam builds of Dwarf Fortress and DFHack on an Apple Silicon Mac
via Apple's Game Porting Toolkit, without ever running the Windows Steam client.

Everything lives under `~/.df-steam`. The only things installed outside it are
Rosetta 2, `winetricks` (via Homebrew), and the GPTK app bundle in
`/Applications`.

## Prerequisites

- Apple Silicon Mac (M1 or newer), macOS 14 or later
- 16 GB RAM recommended
- You own Dwarf Fortress on Steam
- Homebrew (the normal arm64 one — no x86 Homebrew needed)

## 1. Install GPTK

Apple's official route builds `game-porting-toolkit` from source under an
x86_64 Homebrew, needs full Xcode, and fails often with linker errors. Skip it.
Use Gcenx's prebuilt binary distribution instead — Gcenx is an official WineHQ
macOS package maintainer, so this is a known quantity, though the GPTK
redistribution itself is unofficial and Apple could pull it.

Download the latest release:

<https://github.com/Gcenx/game-porting-toolkit/releases>

Unpack it and move the `.app` to `/Applications`. It's unsigned, so clear the
quarantine flag or Gatekeeper will refuse to open it:

```bash
xattr -dr com.apple.quarantine "/Applications/<bundle name>.app"
```

Find the wine binary inside it — the layout varies between releases:

```bash
find "/Applications/<bundle name>.app" -type f -name wine64
```

Note: with recent Gcenx builds you want `wine64`, not `wine`. The plain `wine`
binary is either absent or wrong.

## 1,5 Alternatively, more recent wine without metal 3d

Head there https://github.com/Gcenx/macOS_Wine_builds/releases?page=2#release-11.0_1 and
install the gstreamer package and this

## 2. Rosetta 2

Required regardless — GPTK's wine is x86_64.

```bash
softwareupdate --install-rosetta --agree-to-license
```

## 3. Environment

Create `~/.df-steam/env.sh` yourself with the content below, correcting the
`WINE` path for your GPTK bundle. `df-steam.sh` sources this file and fails if
it is missing.

```bash
# ~/.df-steam/env.sh — source this for a shell wired to the DF prefix.
#   source ~/.df-steam/env.sh
#
# Edit WINE to point at your GPTK install. Find it with:
#   find /Applications/<bundle>.app -type f -name wine64

export DF_ROOT="$HOME/.df-steam"

# GPTK's wine. Must be wine64, not wine, on recent Gcenx builds.
export WINE="/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"

export WINEPREFIX="$DF_ROOT/prefix"

# esync deadlocks DF's event loop under GPTK. Leave at 0.
export WINEESYNC=0

# Quiet. Unset when debugging.
export WINEDEBUG=-all

# winemenubuilder stalls startup and we don't want .desktop files.
export WINEDLLOVERRIDES="winemenubuilder.exe="

# Where steamcmd puts the game files.
export DF_DIR="$WINEPREFIX/drive_c/DF"
export STEAMCMD_DIR="$DF_ROOT/steamcmd"

# Optional: skip the account prompt in df-steam.sh
# export STEAM_USER="yoursteamname"
```

Then:

```bash
source ~/.df-steam/env.sh
```

## 4. Wine prefix

Create the prefix and set the Windows version to 10, which is what the DF
wiki's Wine recipe calls for.

```bash
arch -x86_64 "$WINE" wineboot -i
arch -x86_64 "$WINE" winecfg          # Applications tab -> Windows 10 -> Apply
```

The GUI is the canonical way to do this and what the wiki describes — if you
already did it there, nothing to redo. `winecfg -v win10` does the same thing
without opening a window.

Avoid the `reg add 'HKCU\Software\Wine' /v Version /d win10` shortcut you'll
see in scripts. It sets the override Wine reads, but winecfg also writes
version information under `HKLM`, so the two aren't strictly equivalent and
some installers check the `HKLM` values.

The `arch -x86_64` prefix isn't always necessary, but several people have hit
cases where wine silently does nothing without it, so it's cheap insurance.

## 5. winetricks

DF needs `msvcp140_atomic_wait` — the same dependency that makes it fail on
bare Windows without the VC++ 2022 redistributable.

```bash
brew install winetricks
WINE="$WINE" WINEPREFIX="$WINEPREFIX" winetricks -q vcrun2022
```

Gcenx's 3.0-x releases specifically note fixed vcrun installers, so this should
behave. If it doesn't, the fallback is a library override for
`msvcp140_atomic_wait` in `winecfg` → Libraries.

## 6. steamcmd and the game files

`steamcmd` is Valve's official CLI Steam client — no window, no CEF, no
webhelper.

```bash
mkdir -p ~/.df-steam/steamcmd && cd ~/.df-steam/steamcmd
curl -sO https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz
tar -xzf steamcmd_osx.tar.gz
./steamcmd.sh +quit          # self-update
```

Then pull both apps into one directory:

```bash
./steamcmd.sh \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir ~/.df-steam/prefix/drive_c/DF \
  +login <your-steam-account> \
  +app_update 975370 validate \
  +app_update 2346660 validate \
  +quit
```

- `975370` — Dwarf Fortress
- `2346660` — DFHack (a separate Steam app, not a Workshop mod)
- `@sSteamCmdForcePlatformType windows` is what makes it fetch Windows depots
  instead of refusing for lack of a Mac build

Expect a Steam Guard prompt on first login.

Afterwards, `hack/` should sit next to `data/`, with `dfhooks.dll` in the same
folder. If DFHack didn't land there, download the release matching your DF
version from <https://github.com/dfhack/dfhack/releases> and unzip it into
`$DF_DIR` manually. **Versions must match exactly** — DFHack 53.16 only
supports DF 53.16.

## 7. Launching

```bash
cd ~/.df-steam/prefix/drive_c/DF
DFHACK_DISABLE_CONSOLE=1 arch -x86_64 "$WINE" "Dwarf Fortress.exe"
```

`DFHACK_DISABLE_CONSOLE` is the critical one. DFHack's external Windows console
deadlocks DF's event loop under Wine — the window renders, the UI ignores every
click, CPU sits at 0%. The DFHack docs describe this variable as intended for
situations where DFHack cannot run in a terminal window, which is exactly this.

You lose nothing: `gui/launcher` (backtick), the hotkeys overlay, and
`gui/quickcmd` all work in-game, and that's how most people use DFHack anyway.

DF loads DFHack itself via `dfhooks`, so there's no separate launcher to invoke.

## The script

`df-steam.sh` covers steps 6 and 7 only — steamcmd and launching. GPTK, the
prefix, and winetricks (steps 1–5) are yours to do by hand.

```bash
mkdir -p ~/.df-steam
cp env.sh df-steam.sh ~/.df-steam/
chmod +x ~/.df-steam/df-steam.sh
$EDITOR ~/.df-steam/env.sh        # set WINE to your GPTK wine64

~/.df-steam/df-steam.sh install   # steamcmd + game files + mods
~/.df-steam/df-steam.sh run       # launch
~/.df-steam/df-steam.sh upgrade   # re-pull DF, DFHack and mods
~/.df-steam/df-steam.sh mods      # re-pull mods only
```

It sources `env.sh` and bails if `DF_DIR` or `WINE` aren't set.

### Steam Workshop mods

Without the Steam client nothing subscribes or auto-downloads, so list the
published-file IDs yourself in `~/.df-steam/mods`, one per line, `#` for
comments:

```
# Mods Placeholder (for installing mods after world creation)
3155983736

# Some Other Mod
2920806963
```

Find your IDs at
`https://steamcommunity.com/id/<you>/myworkshopfiles/?appid=975370&browsefilter=mysubscriptions`
— each item's URL ends in `?id=<number>`.

`install` and `upgrade` both read this file and fetch whatever's listed; if the
file is absent they just skip the mods step. `df-steam.sh mods` re-pulls them
on their own, and `df-steam.sh mods 3155983736` grabs a one-off without editing
the file.

Under the hood: `workshop_download_item` ignores `force_install_dir` and writes
to `$STEAMCMD_DIR/steamapps/workshop/content/975370/<id>/`, so the script copies
each item into `$DF_DIR/mods/<id>/`. This is the same manual copy Windows Steam
users do when DF's automatic import from the workshop folder doesn't fire.

Mods are enabled per-world: hit the **Mods** button on the world-generation
parameters screen and move them into the right-hand box, after the VANILLA
entries. Once a world is generated, DF copies what it used into
`data/installed_mods/` — that's the copy the game actually reads, so deleting
something from `mods/` later won't remove it from an existing save.

It sources `env.sh` and bails if `DF_DIR` or `WINE` aren't set.

## Troubleshooting

**UI frozen, 0% CPU, buttons do nothing** — DFHack's console. Confirm by
renaming `dfhooks.dll` to `dfhooks.dll.off` and relaunching. Fix is
`DFHACK_DISABLE_CONSOLE=1`.

**Hang during worldgen** — check whether it's actually spinning first:

```bash
top -pid $(pgrep -f 'Dwarf Fortress.exe' | head -1)
```

One core near 100% means it's working, just slow — worldgen is single-threaded
x86 code under Rosetta under Wine. 0% means it's blocked. Generate a small
region with 50 years of history while diagnosing; it makes "slow" and "hung"
distinguishable.

**Noise you can ignore:**

- `wine: Read access denied for device L"\??\Z:\"` — appears in known-working
  GPTK logs
- `vkCreateInstance failed with error -3` / `Unable to initialize Vulkan` —
  GPTK translates to Metal via D3DMetal, not MoltenVK. Irrelevant to DF.
- `thread_get_state failed on Apple Silicon - faking zero debug registers` —
  normal for GPTK

**Check `stderr.log`** in `$DF_DIR`. DFHack logs load failures there.

## Caveats

- None of this is supported. Bay 12 cancelled the native macOS build, and the
  Steam version isn't officially supported on macOS — a DF or macOS update can
  break it with no recourse.
- GPTK 3.0 targets macOS 14+; Apple's current toolkit is GPTK 4, targeting
  macOS 27. If you upgrade macOS and things break at the runtime level,
  version mismatch between OS and toolkit is the first thing to check.
- No Steam Workshop and no Cloud saves, since the client never runs. Workshop
  mods can be fetched separately with `steamcmd` if you want them.
- If you ever want the Steam client badly enough, the leads worth trying are
  <https://github.com/domschl/WinSteamOnMac> and
  <https://github.com/jungwuk-ryu/switchyard-wine> — the latter is
  Developer-ID-signed and notarized, ships without Apple's GPTK files (you
  supply the overlay), and is regression-tested against Steam.
