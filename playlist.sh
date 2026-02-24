#!/bin/bash

[ -t 0 ] && stty -ixon >> /dev/null

filename=$1
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
PLAYLIST_DIR="$XDG_DATA_HOME/play/playlists"
mkdir -p $PLAYLIST_DIR >> /dev/zero
filepath="$PLAYLIST_DIR/${filename}.txt"

if [ $# -lt 1 ]; then
    echo "Usage: playlist filename [-l] [-s] [-n]" >&2
    echo "Playlist dir: ~/.local/share/play/playlists" >&2
    exit 1
fi

filename=$1
shift

NOTIFY=true
loop=false
shuffle=false

for arg in "$@"; do
    case $arg in
        -l) loop=true ;;
        -s) shuffle=true ;;
        -n) NOTIFY=false ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [ ! -f "$filepath" ]; then
    echo "File not found: $filepath" >&2
    exit 1
fi

mapfile -t original_lines < "$filepath"

quit=false

if command -v play >/dev/null 2>&1; then
    PLAY_BIN="play"
else
    PLAY_BIN="$(cd "$(dirname "$0")" && pwd)/play.sh"
fi

play_playlist() {
    local lines=("${@}")
    local idx=0

    while [ "$idx" -lt "${#lines[@]}" ]; do
        if $quit; then
            break
        fi

        line="${lines[$idx]}"
        if $NOTIFY; then
            "$PLAY_BIN" "$line"
        else
            "$PLAY_BIN" "$line" -n
        fi

        rc=$?
        case "$rc" in
            12)
                if [ "$idx" -gt 0 ]; then
                    idx=$((idx - 1))
                fi
                ;;
            13)
                quit=true
                ;;
            *)
                idx=$((idx + 1))
                ;;
        esac
    done
}

if $loop; then
    while ! $quit; do
        if $shuffle; then
            mapfile -t shuffled_lines < <(printf '%s\n' "${original_lines[@]}" | shuf)
            play_playlist "${shuffled_lines[@]}"
        else
            play_playlist "${original_lines[@]}"
        fi
    done
else
    if $shuffle; then
        mapfile -t shuffled_lines < <(printf '%s\n' "${original_lines[@]}" | shuf)
        play_playlist "${shuffled_lines[@]}"
    else
        play_playlist "${original_lines[@]}"
    fi
fi
