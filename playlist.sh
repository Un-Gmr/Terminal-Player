#!/bin/bash

[ -t 0 ] && stty -ixon

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

play_playlist() {
    local lines=("${@}")
    for line in "${lines[@]}"; do
        if $quit; then
            break
        fi

        if $NOTIFY; then
            play "$line" &
        else
            play "$line" -n &
        fi

        pid=$!
        
        while kill -0 $pid 2>/dev/null; do
            read -rsn1 -t 0.1 key < /dev/tty
            if [[ $key == "q" ]]; then
                pkill mpv
                sleep .1
                kill $pid 2>/dev/null
                quit=true
                break
            fi
        done
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