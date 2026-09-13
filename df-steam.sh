#!/usr/bin/env bash
#
# df-steam.sh — thin wrapper around steamcmd for Dwarf Fortress + DFHack.
#
#   install   download DF + DFHack (+ any mods listed in ~/.df-steam/mods)
#   run       launch DF with the DFHack console disabled
#   upgrade   re-pull DF, DFHack and mods
#   mods      re-pull mods only (optionally: mods <id> [id...])
#
# Wine/GPTK setup is NOT handled here. Configure it yourself in
# ~/.df-steam/env.sh (WINE, WINEPREFIX, WINEESYNC, DF_DIR, ...).

set -euo pipefail

DF_ROOT="${DF_ROOT:-$HOME/.df-steam}"
ENV_FILE="$DF_ROOT/env.sh"
MODS_FILE="$DF_ROOT/mods"

readonly APPID_DF=975370
readonly APPID_DFHACK=2346660
readonly STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz"

die() { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

[ -f "$ENV_FILE" ] || die "missing $ENV_FILE"
# shellcheck source=/dev/null
source "$ENV_FILE"

: "${DF_DIR:?not set in $ENV_FILE}"
: "${STEAMCMD_DIR:=$DF_ROOT/steamcmd}"

# Ask once per invocation, then reuse.
STEAM_USER="${STEAM_USER:-}"
steam_user() {
    if [ -z "$STEAM_USER" ]; then
        printf 'Steam account name: ' >&2
        read -r STEAM_USER
    fi
    printf '%s\n' "$STEAM_USER"
}

install_steamcmd() {
    [ -f "$STEAMCMD_DIR/steamcmd.sh" ] && return 0
    log "fetching steamcmd into $STEAMCMD_DIR"
    mkdir -p "$STEAMCMD_DIR"
    curl -fsSL "$STEAMCMD_URL" | tar -xz -C "$STEAMCMD_DIR"
    "$STEAMCMD_DIR/steamcmd.sh" +quit || true
}

fetch_games() {
    mkdir -p "$DF_DIR"
    "$STEAMCMD_DIR/steamcmd.sh" \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir "$DF_DIR" \
        +login "$(steam_user)" \
        +app_update "$APPID_DF" validate \
        +app_update "$APPID_DFHACK" validate \
        +quit
}

# Read IDs from ~/.df-steam/mods. Format: one published-file ID per line,
# '#' starts a comment. Blank and whitespace-only lines are ignored.
read_mods_file() {
    [ -f "$MODS_FILE" ] || return 0
    local ids id out=""
    ids="$(sed 's/#.*//' "$MODS_FILE" | tr -s '[:space:]' ' ')"
    for id in $ids; do
        case "$id" in
            *[!0-9]*)
                die "bad entry in $MODS_FILE: '$id'
    Expected a numeric published-file ID. If you pasted a URL, use only the
    number after '?id='." ;;
        esac
        out="$out $id"
    done
    printf '%s\n' "$out"
}

# $* = workshop IDs. Downloads them and copies into DF's mods/ folder.
fetch_mods() {
    local ids="$*" id src name log_file found=0 missing=0
    ids="$(printf '%s' "$ids" | tr -s '[:space:]' ' ')"
    if [ -z "${ids// /}" ]; then
        log "no workshop IDs (nothing in $MODS_FILE) — skipping mods"
        return 0
    fi

    log "fetching workshop items:$(printf ' %s' $ids)"
    # workshop_download_item ignores force_install_dir, so this is a separate
    # run. Where it lands varies by platform (on macOS it's usually
    # ~/Library/Application Support/Steam/...), so capture the output and read
    # the real destination back out of it rather than guessing.
    log_file="$(mktemp -t dfmods)"
    set -- +login "$(steam_user)"
    for id in $ids; do set -- "$@" +workshop_download_item "$APPID_DF" "$id"; done
    "$STEAMCMD_DIR/steamcmd.sh" "$@" +quit 2>&1 | tee "$log_file" || true

    mkdir -p "$DF_DIR/mods"
    for id in $ids; do
        # steamcmd prints: Success. Downloaded item <id> to "<path>" (N bytes)
        src="$(tr '\r' '\n' < "$log_file" \
               | sed -n "s|.*Downloaded item $id to \"\([^\"]*\)\".*|\1|p" \
               | tail -1)"

        # Fall back to the usual locations if the output format changed.
        if [ -z "$src" ] || [ ! -d "$src" ]; then
            for candidate in \
                "$HOME/Library/Application Support/Steam/steamapps/workshop/content/$APPID_DF/$id" \
                "$STEAMCMD_DIR/steamapps/workshop/content/$APPID_DF/$id" \
                "$HOME/Steam/steamapps/workshop/content/$APPID_DF/$id"; do
                [ -d "$candidate" ] && { src="$candidate"; break; }
            done
        fi

        if [ -z "$src" ] || [ ! -d "$src" ]; then
            log "WARNING: $id did not download, skipping"
            missing=$((missing + 1))
            continue
        fi

        rm -rf "$DF_DIR/mods/$id"
        cp -R "$src" "$DF_DIR/mods/$id"
        name="$(sed -n 's/^\[NAME:\(.*\)\]/\1/p' "$DF_DIR/mods/$id/info.txt" 2>/dev/null \
                | tr -d '\r' | head -1)"
        log "installed $id${name:+ ($name)}"
        found=$((found + 1))
    done
    rm -f "$log_file"

    log "$found mod(s) installed into $DF_DIR/mods${missing:+, $missing missing}"
    [ "$found" -gt 0 ] && log "enable them via the Mods button when generating a new world"
    return 0
}

case "${1:-}" in
install)
    install_steamcmd
    fetch_games
    [ -f "$DF_DIR/Dwarf Fortress.exe" ] || die "no Dwarf Fortress.exe in $DF_DIR"
    if [ -f "$DF_DIR/dfhooks.dll" ]; then
        log "DFHack present"
    else
        log "WARNING: no dfhooks.dll — install DFHack manually from
    https://github.com/dfhack/dfhack/releases (version must match DF exactly)"
    fi
    mod_ids="$(read_mods_file)" || exit 1
    fetch_mods "$mod_ids"
    ;;
upgrade)
    fetch_games
    mod_ids="$(read_mods_file)" || exit 1
    fetch_mods "$mod_ids"
    ;;
mods)
    shift
    if [ $# -gt 0 ]; then
        fetch_mods "$@"
    else
        [ -f "$MODS_FILE" ] || die "no IDs given and no $MODS_FILE
    One published-file ID per line, '#' for comments. Find yours at:
    https://steamcommunity.com/id/<you>/myworkshopfiles/?appid=$APPID_DF&browsefilter=mysubscriptions"
        mod_ids="$(read_mods_file)" || exit 1
        fetch_mods "$mod_ids"
    fi
    ;;
run)
    shift
    [ -x "${WINE:?not set in $ENV_FILE}" ] || die "wine not executable: $WINE"
    cd "$DF_DIR"
    # DFHack's external console deadlocks DF's event loop under wine.
    # Use the in-game launcher (backtick) instead.
    DFHACK_DISABLE_CONSOLE=1 arch -x86_64 "$WINE" "Dwarf Fortress.exe" "$@"
    ;;
*)
    echo "usage: $0 {install|run|upgrade|mods [id...]}" >&2
    exit 1
    ;;
esac
