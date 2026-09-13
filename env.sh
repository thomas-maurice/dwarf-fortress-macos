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
# export STEAM_USER="your-steam-username"
