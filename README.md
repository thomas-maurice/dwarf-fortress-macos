# Dwarf Fortress (Steam) + DFHack on Apple Silicon

Running the Steam builds of Dwarf Fortress and DFHack on an Apple Silicon Mac
under Wine, without ever running the Windows Steam client.

Everything lives under `~/.df-steam`. The only things installed outside it are
Rosetta 2, `winetricks` (via Homebrew), a Wine app bundle in `/Applications`,
and — for the WineHQ route — GStreamer.framework.

## Why this shape

Two decisions drive the whole setup:

- **No Windows Steam client.** The client crash-loops under Wine:
  `steamwebhelper` calls `WSALookupServiceBegin`, Wine doesn't implement
  Windows' Network Location Awareness namespace, and Chromium's error path hits
  an `int3` — an endless stream of `Unhandled exception 0x80000003`. `steamcmd`
  fetches the same Steam depots with no UI to crash. You lose Workshop
  subscriptions and Cloud saves; you keep everything else.
- **No DirectX anywhere.** DF v50+ composites its graphics in C++ and blits
  them through SDL — it's software-rendered and issues no DirectX calls. That
  means D3DMetal, the entire reason Apple's Game Porting Toolkit exists, does
  nothing for us. Any working Wine will do.

## Prerequisites

- Apple Silicon Mac (M1 or newer)
- 16 GB RAM recommended
- You own Dwarf Fortress on Steam
- Homebrew (the normal arm64 one — no x86 Homebrew needed)

## 1. Pick a Wine

Two routes. **Route A is the better default for DF.** Route B is what you want
only if you also intend to run DirectX games out of the same setup.

### Route A — WineHQ (recommended)

The official WineHQ macOS packages, maintained by Gcenx (an official WineHQ
macOS package maintainer since 2021). Current Wine, no Apple redistribution
grey area.

Releases are tagged by Wine version at
<https://github.com/Gcenx/macOS_Wine_builds/releases>. The naming isn't
labelled by branch, so:

| Tag shape | Branch |
|---|---|
| `11.0`, `11.0_1`, `12.0` — minor version **zero** | stable |
| `11.6`, `11.16` — non-zero minor | devel (bundles staging too) |

A `_N` suffix is a repackage counter and is orthogonal to the branch. Take the
newest zero-minor tag — at time of writing **11.0_1** (16 April 2026).

Staging is the wrong choice here: its several hundred out-of-tree patches
target anti-cheat, DRM, and exotic Win32 APIs. DF needs none of that, and every
extra patch is regression surface.

**GStreamer first.** These builds are compiled against GStreamer.framework and
list it as a requirement. Each release links the version it was tested with —
11.0_1 wants
[1.28.1](https://gstreamer.freedesktop.org/data/pkg/osx/1.28.1/gstreamer-1.0-1.28.1-universal.pkg).
It must be installed **for all users** — Wine looks in `/Library/Frameworks/`,
and a user-only install lands in `~/Library/Frameworks/` where it won't be
found.

The package isn't notarized by Apple, so macOS will refuse it with *"Apple
could not verify ... is free of malware"*. That's expected — GStreamer's
official builds come from freedesktop.org, not the App Store. Check you
downloaded it from `gstreamer.freedesktop.org` rather than a mirror, then clear
the quarantine flag the browser set and install from the CLI, which sidesteps
the Gatekeeper double-click check:

```bash
xattr -dr com.apple.quarantine ~/Downloads/gstreamer-1.0-1.28.1-universal.pkg
sudo installer -pkg ~/Downloads/gstreamer-1.0-1.28.1-universal.pkg -target /
ls -d /Library/Frameworks/GStreamer.framework    # verify
```

`-target /` is what makes it an all-users install. If you'd rather use the GUI:
try to open the pkg, let it fail, then go to **System Settings → Privacy &
Security**, scroll to the Security section, and click **Open Anyway**. On recent
macOS the right-click → Open trick no longer works for this particular message.

Only one GStreamer can be installed at a time — the framework occupies the
`Versions/1.0` slot regardless of release, and 1.0 is the *API* version. That's
fine: GStreamer is ABI-stable across 1.x, so a build tested against 1.28.1 runs
against 1.28.5. Newer `.pkg`s overwrite in place; install the newest 1.x and
stop thinking about it.

DF almost certainly doesn't need it — DF handles audio through SDL2 and has no
video cutscenes — but installing it removes a whole class of confusing startup
errors.

Then unpack the release, move the `Wine *` bundle to `/Applications`, and
continue to step 2.

### Route B — Game Porting Toolkit

Only worth it for DirectX games. GPTK's Wine is pinned by Apple at **7.7** — a
patched version of CrossOver's fork — and will never move. That age is exactly
what breaks the Steam client, and it's four major versions behind current Wine.

Apple ships no app bundle. Their route is a developer `.dmg` plus building Wine
yourself under an x86_64 Homebrew with a pinned Command Line Tools version and
a hand-installed MinGW from a 2023 Homebrew commit. Skip it. Use Gcenx's
prebuilt distribution instead:
<https://github.com/Gcenx/game-porting-toolkit/releases>

It bundles GStreamer, so the step above doesn't apply. Note the GPTK bundle
redistributes Apple's D3DMetal, which isn't clearly permitted — Apple could
pull it.

### Either route

Move the `.app` to `/Applications`. It's unsigned, so clear the quarantine flag
or Gatekeeper will refuse it:

```bash
xattr -dr com.apple.quarantine "/Applications/<bundle name>.app"
```

Find the wine binary — the layout varies between releases:

```bash
find "/Applications/<bundle name>.app" -type f -name wine64
```

Use `wine64`, not `wine`. On recent builds the plain `wine` binary is absent or
wrong.

## 2. Rosetta 2

Required for both routes — Wine here is x86_64 either way.

```bash
softwareupdate --install-rosetta --agree-to-license
```

## 3. Environment

Create `~/.df-steam/env.sh` yourself with the content below, correcting the
`WINE` path for your bundle. `df-steam.sh` sources this file and fails if it's
missing.

```bash
# ~/.df-steam/env.sh — source this for a shell wired to the DF prefix.
#   source ~/.df-steam/env.sh
#
# Edit WINE to point at your Wine install. Find it with:
#   find /Applications/<bundle>.app -type f -name wine64

export DF_ROOT="$HOME/.df-steam"

# Must be wine64, not wine.
export WINE="/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64"

export WINEPREFIX="$DF_ROOT/prefix"

# esync deadlocks DF's event loop. Leave at 0.
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

Switching Wine builds later is just editing `WINE` here — but note that opening
a prefix with a newer Wine triggers a one-way upgrade. If you ever want to try
another build, `ditto` the prefix to a new directory first and point both
`WINE` and `WINEPREFIX` at the copy, so the original stays as a fallback.

## 4. Wine prefix

Create the prefix and set the Windows version to 10, which is what the DF
wiki's Wine recipe calls for.

```bash
arch -x86_64 "$WINE" wineboot -i
arch -x86_64 "$WINE" winecfg          # Applications tab -> Windows 10 -> Apply
```

The GUI is the canonical way to do this and what the wiki describes.
`winecfg -v win10` does the same thing without opening a window.

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

On the GPTK route winetricks will warn that your Wine is old (7.7) and suggest
upgrading. It's reporting accurately but nothing can be done — that's the
version Apple pinned. `vcrun2022` still installs. Verify either way:

```bash
ls "$WINEPREFIX/drive_c/windows/system32/" | grep -i msvcp140
```

If it's missing, the fallback is a library override for `msvcp140_atomic_wait`
in `winecfg` → Libraries.

## 6. steamcmd and the game files

`steamcmd` is Valve's official CLI Steam client — no window, no CEF, no
webhelper.

```bash
mkdir -p ~/.df-steam/steamcmd && cd ~/.df-steam/steamcmd
curl -sO https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz
tar -xzf steamcmd_osx.tar.gz
./steamcmd.sh +quit          # self-update
```

**Authenticate once interactively** before scripting it. Run `./steamcmd.sh`,
then `login <your-account>` at the `Steam>` prompt and enter your password and
Steam Guard code. Credentials cache, and every later `+login <user>` goes
through without prompting.

The password prompt is echo-suppressed — you'll see nothing while typing. If
Enter produces a literal `^M` instead of submitting, steamcmd left your
terminal in raw mode (usually after a Ctrl-C at the password prompt). Fix with
`stty sane`, pressing **Ctrl-J** instead of Enter to submit it, or just open a
fresh terminal tab.

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

The first download in any steamcmd run stalls for a few minutes while it
self-updates and initialises. Subsequent items start in seconds. It's a
per-invocation cost, not per-item.

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

`df-steam.sh` covers steps 6 and 7 only — steamcmd and launching. The Wine
install, the prefix, and winetricks (steps 1–5) are yours to do by hand.

```bash
mkdir -p ~/.df-steam
cp env.sh df-steam.sh mods ~/.df-steam/
chmod +x ~/.df-steam/df-steam.sh
$EDITOR ~/.df-steam/env.sh        # set WINE to your wine64

~/.df-steam/df-steam.sh install   # steamcmd + game files + mods
~/.df-steam/df-steam.sh run       # launch
~/.df-steam/df-steam.sh upgrade   # re-pull DF, DFHack and mods
~/.df-steam/df-steam.sh mods      # re-pull mods only
```

It sources `env.sh` and bails if `DF_DIR` or `WINE` aren't set. It also saves
and restores your terminal state, so an interrupted steamcmd password prompt
won't leave the tty wedged.

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
— each item's URL ends in `?id=<number>`. Blank lines and comment-only lines
are ignored; anything non-numeric is rejected with an error rather than passed
to steamcmd.

`install` and `upgrade` both read this file and fetch whatever's listed; if the
file is absent they skip the mods step. `df-steam.sh mods` re-pulls them on
their own, and `df-steam.sh mods 3155983736` grabs a one-off without editing
the file.

Under the hood: `workshop_download_item` ignores `force_install_dir` and writes
somewhere else entirely — on macOS that's usually
`~/Library/Application Support/Steam/steamapps/workshop/content/975370/<id>/`.
The script reads the real destination back out of steamcmd's own output rather
than assuming, then copies each item into `$DF_DIR/mods/<id>/`. This is the same
manual copy Windows Steam users do when DF's automatic import from the workshop
folder doesn't fire.

Mods are enabled per-world: hit the **Mods** button on the world-generation
parameters screen and move them into the right-hand box, after the VANILLA
entries. Once a world is generated, DF copies what it used into
`data/installed_mods/` — that's the copy the game actually reads, so deleting
something from `mods/` later won't remove it from an existing save.

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

**Workshop mod names print mangled** — `info.txt` uses CRLF, so the trailing
`\r` rewinds the cursor. The script strips it; if you're parsing by hand, pipe
through `tr -d '\r'`.

**Noise you can ignore:**

- `wine: Read access denied for device L"\??\Z:\"` — appears in known-working
  logs
- `vkCreateInstance failed with error -3` / `Unable to initialize Vulkan` —
  Steam probing for Vulkan. Irrelevant to DF.
- `PosixFileOpen: RESOLVE_BENEATH unsupported` — steamcmd noise; that's a Linux
  `openat2` flag macOS doesn't implement, and it falls back cleanly
- `thread_get_state failed on Apple Silicon - faking zero debug registers` —
  normal under GPTK

**Check `stderr.log`** in `$DF_DIR`. DFHack logs load failures there.

## Caveats

- None of this is supported. Bay 12 cancelled the native macOS build, and the
  Steam version isn't officially supported on macOS — a DF or macOS update can
  break it with no recourse.
- No Workshop subscriptions and no Cloud saves, since the client never runs.
  Mods are handled by ID list instead, as above.
- On the GPTK route: GPTK 3.0 targets macOS 14+, while Apple's current toolkit
  is GPTK 4, targeting macOS 27. If you upgrade macOS and things break at the
  runtime level, version mismatch between OS and toolkit is the first thing to
  check.
- If you ever want the Steam client badly enough, newer Wine is the most likely
  route — the `WSALookupServiceBegin` gap is exactly the kind of thing fixed
  since 7.7. Otherwise the leads are
  <https://github.com/domschl/WinSteamOnMac> and
  <https://github.com/jungwuk-ryu/switchyard-wine>, the latter
  Developer-ID-signed, notarized, and regression-tested against Steam.
