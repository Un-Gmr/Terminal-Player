#!/usr/bin/env bash

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/terminal-player"
MPV_SOCKET="$RUNTIME_DIR/mpv.socket"
CMD_FILE="$RUNTIME_DIR/command"

for dep in socat jq; do
    command -v "$dep" >/dev/null || { echo "Missing: $dep"; exit 1; }
done

usage() {
    cat <<'EOF'
Usage: playctl <command>

Commands:
  toggle|pause|play-pause
  play
  stop
  next
  prev
  quit
  volup
  voldown
  mute
  seekf
  seekb
  status
EOF
}

send_mpv() {
    local json="$1"
    [ -S "$MPV_SOCKET" ] || { echo "No active player socket at $MPV_SOCKET"; exit 1; }
    echo "$json" | socat - "$MPV_SOCKET" >/dev/null 2>&1
}

set_command() {
    local command="$1"
    mkdir -p "$RUNTIME_DIR"
    printf "%s" "$command" > "$CMD_FILE"
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

case "$1" in
    toggle|pause|play-pause)
        send_mpv '{ "command": ["cycle", "pause"] }'
        ;;
    play)
        send_mpv '{ "command": ["set_property", "pause", false] }'
        ;;
    stop)
        set_command "stop"
        send_mpv '{ "command": ["stop"] }'
        ;;
    next)
        set_command "next"
        send_mpv '{ "command": ["stop"] }'
        ;;
    prev)
        set_command "prev"
        send_mpv '{ "command": ["stop"] }'
        ;;
    quit)
        set_command "quit"
        send_mpv '{ "command": ["stop"] }'
        ;;
    volup)
        send_mpv '{ "command": ["add", "volume", 5] }'
        ;;
    voldown)
        send_mpv '{ "command": ["add", "volume", -5] }'
        ;;
    mute)
        send_mpv '{ "command": ["cycle", "mute"] }'
        ;;
    seekf)
        send_mpv '{ "command": ["seek", 10] }'
        ;;
    seekb)
        send_mpv '{ "command": ["seek", -10] }'
        ;;
    status)
        [ -S "$MPV_SOCKET" ] || { echo "No active player socket at $MPV_SOCKET"; exit 1; }
        pause=$(echo '{ "command": ["get_property", "pause"] }' | socat - "$MPV_SOCKET" 2>/dev/null | jq -r '.data // "N/A"')
        volume=$(echo '{ "command": ["get_property", "volume"] }' | socat - "$MPV_SOCKET" 2>/dev/null | jq -r '.data // "N/A"')
        time_pos=$(echo '{ "command": ["get_property", "time-pos"] }' | socat - "$MPV_SOCKET" 2>/dev/null | jq -r '.data // "N/A"')
        echo "pause=$pause volume=$volume time_pos=$time_pos"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
