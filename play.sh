#!/usr/bin/env bash

LOOP=false
SEARCH=""
LYRIC_OFFSET=0.0
NOTIFY=true
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/terminal-player"
MPV_SOCKET="$RUNTIME_DIR/mpv.socket"
CMD_FILE="$RUNTIME_DIR/command"
REASON_FILE="$RUNTIME_DIR/reason"
METADATA_FILE="$RUNTIME_DIR/metadata.json"
MPRIS_STOP_FILE="$RUNTIME_DIR/mpris.stop"
MPRIS_LOG_FILE="$RUNTIME_DIR/mpris.log"

for dep in yt-dlp mpv jq socat jp2a figlet magick curl; do
    command -v $dep >/dev/null||{ echo "Missing: $dep"; exit 1; }
done

for arg in "$@"; do
    if [ "$arg" = "-l" ]; then
        LOOP=true
    elif [ "$arg" = "-n" ]; then
        NOTIFY=false
    else
        SEARCH="$SEARCH $arg"
    fi
done
SEARCH=$(echo "$SEARCH" | sed 's/^ *//;s/ *$//')

if [ -z "$SEARCH" ]; then
    echo "Usage: play search terms [-l]" >&2
    exit 1
fi

METADATA=$(yt-dlp "ytsearch1:$SEARCH" -q --no-warnings --no-download --print-json)
URL=$(echo "$METADATA" | jq -r '.webpage_url')
TITLE=$(echo "$METADATA" | jq -r '.title // "N/A"')
ARTIST=$(echo "$METADATA" | jq -r '.artist // "N/A"')
ALBUM=$(echo "$METADATA" | jq -r '.album // "N/A"')
DATE=$(echo "$METADATA" | jq -r '.upload_date // "N/A"')
UPLOADER=$(echo "$METADATA" | jq -r '.uploader // "N/A"')
THUMB=$(echo "$METADATA" | jq -r '.thumbnail // empty')

TERM_WIDTH=$(tput cols)
COVER_WIDTH=$((TERM_WIDTH / 2))
mkdir -p "$RUNTIME_DIR"
rm -f "$MPV_SOCKET"
: > "$CMD_FILE"
: > "$REASON_FILE"
rm -f "$MPRIS_STOP_FILE"
: > "$MPRIS_LOG_FILE"
echo "mpris init: $(date -Is)" >>"$MPRIS_LOG_FILE"

LYRICS_FILE=$(mktemp /tmp/lyric.XXXXXX.lrc)
COVER_FILE=""

cleanup() {
    [ -n "${stty_orig:-}" ] && stty "$stty_orig" 2>/dev/null
    [ -n "$COVER_FILE" ] && rm -f "$COVER_FILE" "$COVER_FILE.cropped.png"
    [ -n "$LYRICS_FILE" ] && rm -f "$LYRICS_FILE"
    touch "$MPRIS_STOP_FILE" 2>/dev/null
    [ -n "${MPRIS_PID:-}" ] && kill "$MPRIS_PID" 2>/dev/null
    rm -f "$MPV_SOCKET" "$CMD_FILE" "$REASON_FILE" "$METADATA_FILE" "$MPRIS_STOP_FILE"
}
trap cleanup INT TERM EXIT

COVER_LINES=()
if [ -n "$THUMB" ]; then
    COVER_FILE=$(mktemp /tmp/cover.XXXXXX.jpg)
    curl -fsSL "$THUMB" -o "$COVER_FILE"
    
    mapfile -t COVER_LINES < <(jp2a --colors --fill --width=$COVER_WIDTH "$COVER_FILE")
    magick "$COVER_FILE" -resize 128x128^ -gravity center -extent 128x128 "$COVER_FILE.cropped.png"
    
    if [ "$NOTIFY" = true ] && command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical -t 5000 -i "$COVER_FILE.cropped.png" "Terminal-Player" "Playing: $TITLE-$ARTIST"
    fi
fi

INFO_LINES=(
    "Title:   $TITLE"
    "Artist:  $ARTIST"
    "Album:   $ALBUM"
    "Date:    $DATE"
    "Channel: $UPLOADER"
    "URL:     $URL"
    "Keys:    [space]=pause  [s]=stop  [n]=next  [p]=prev  [q]=quit"
    "         [f/b]=seek +/-10s  [m]=mute  [+/-]=volume"
    "Percent: 00:00:00 / 00:00:00 (0%)"
    "Volume:  100%"
)

clear

max_lines=${#COVER_LINES[@]}
[ ${#INFO_LINES[@]} -gt $max_lines ] && max_lines=${#INFO_LINES[@]}

for ((i=0; i<max_lines; i++)); do
    printf "%-${COVER_WIDTH}s  %s\n" "${COVER_LINES[i]}" "${INFO_LINES[i]}"
done

PERCENT_LINE=$(( ${#INFO_LINES[@]} - 2 ))
VOLUME_LINE=$((PERCENT_LINE + 1 ))
LAST_PERCENT="00:00:00 / 00:00:00 (0%)"

update_percent() {
    local percent="$1"
    LAST_PERCENT="$percent"
    tput cup $PERCENT_LINE $COVER_WIDTH
    printf "  Percent: %s  " "$percent"
    tput cup $((max_lines+1)) 0
}

send_mpv_command() {
    local cmd_json="$1"
    [ -S "$MPV_SOCKET" ] || return 1
    echo "$cmd_json" | socat - "$MPV_SOCKET" >/dev/null 2>&1
}

queue_reason() {
    local reason="$1"
    printf "%s" "$reason" > "$REASON_FILE"
}

set_command() {
    local command="$1"
    printf "%s" "$command" > "$CMD_FILE"
}

read_command() {
    [ -s "$CMD_FILE" ] || return 1
    tr -d '\r\n' < "$CMD_FILE"
    : > "$CMD_FILE"
}

update_volume() {
    local vol
    vol=$(echo '{ "command": ["get_property", "volume"] }' | socat - "$MPV_SOCKET" 2>/dev/null | jq -r '.data // "N/A"')
    vol=${vol%.*}
    tput cup $VOLUME_LINE $COVER_WIDTH
    printf "  Volume:  %s%%  " "$vol"
    tput cup $((max_lines+2)) 0
}

PYTHON=$(command -v python||command -v python3)||exit 1
"$PYTHON" -m syncedlyrics --synced-only -o="$LYRICS_FILE" "$SEARCH" >>/dev/null 2>/dev/null
[ ! -s "$LYRICS_FILE" ] && "$PYTHON" -m syncedlyrics --synced-only -o="$LYRICS_FILE" "[$TITLE] [$ARTIST]" >>/dev/null 2>/dev/null

LYRIC_HEIGHT=24
LAST_LYRIC=""
LYRIC_START=$(( ${#COVER_LINES[@]} + 1 ))
LAST_LYRIC_SECOND=-1
LOOP_TICK=0
VOLUME_REFRESH_EVERY=50

show_lyrics() {
    local time_s="$1"
    local cur last

    cur=$(awk -v t="$time_s" -v off="$LYRIC_OFFSET" 'BEGIN { printf "%.0f", (t + off) * 1000 }')
    [ "$cur" -lt 0 ] && cur=0

    last=$(awk -F']' -v t="$cur" '
        {
            gsub(/^\[/,"",$1)
            split($1,ts,":")
            split(ts[2],ms,".")
            cur=int(ts[1]*60000 + ts[2]*1000)
            if(cur<=t) last=$2
        }
        END{ gsub(/\n/,"",last); print last }
    ' "$LYRICS_FILE")

    [ "$last" = "$LAST_LYRIC" ] && return
    LAST_LYRIC="$last"

    for ((i=0; i<LYRIC_HEIGHT; i++)); do
        tput cup $((LYRIC_START+i)) 0
        tput el
    done

    tput cup $LYRIC_START 0
    if [ -n "$last" ]; then
        figlet -f small -w $TERM_WIDTH "$last"
    fi
}

MPV_ARGS="--no-video --input-ipc-server=$MPV_SOCKET"
MPV_FORCE_TITLE="${TITLE} - ${ARTIST}"
$LOOP && MPV_ARGS="$MPV_ARGS --loop"

TRACK_ID="$(date +%s)-$$"
jq -n \
    --arg title "$TITLE" \
    --arg artist "$ARTIST" \
    --arg album "$ALBUM" \
    --arg url "$URL" \
    --arg art_url "$THUMB" \
    --arg track_id "$TRACK_ID" \
    '{title:$title,artist:$artist,album:$album,url:$url,art_url:$art_url,track_id:$track_id}' > "$METADATA_FILE"

if [ -t 0 ]; then
    stty_orig=$(stty -g)
fi

MPRIS_BRIDGE="${MPRIS_BRIDGE:-}"
if [ -z "$MPRIS_BRIDGE" ]; then
    if command -v terminal-player-mpris >/dev/null 2>&1; then
        MPRIS_BRIDGE="$(command -v terminal-player-mpris)"
    elif [ -f "$(cd "$(dirname "$0")" && pwd)/terminal_player_mpris.py" ]; then
        MPRIS_BRIDGE="$(cd "$(dirname "$0")" && pwd)/terminal_player_mpris.py"
    fi
fi

if [ -n "$MPRIS_BRIDGE" ]; then
    echo "mpris bridge path: $MPRIS_BRIDGE" >>"$MPRIS_LOG_FILE"
    MPRIS_PYTHON=""
    for py in python3 python; do
        if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import dbus_next' >/dev/null 2>&1; then
            MPRIS_PYTHON="$py"
            break
        fi
    done

    if [ -n "$MPRIS_PYTHON" ]; then
        echo "mpris python: $MPRIS_PYTHON" >>"$MPRIS_LOG_FILE"
        echo "mpris bus: ${DBUS_SESSION_BUS_ADDRESS:-unset}" >>"$MPRIS_LOG_FILE"
        "$MPRIS_PYTHON" "$MPRIS_BRIDGE" --runtime-dir "$RUNTIME_DIR" >>"$MPRIS_LOG_FILE" 2>&1 &
        MPRIS_PID=$!
        echo "mpris pid: $MPRIS_PID" >>"$MPRIS_LOG_FILE"
        sleep 0.2
        if ! kill -0 "$MPRIS_PID" 2>/dev/null; then
            echo "MPRIS bridge exited early. See: $MPRIS_LOG_FILE" >&2
            echo "mpris status: exited early" >>"$MPRIS_LOG_FILE"
        else
            echo "mpris status: running" >>"$MPRIS_LOG_FILE"
        fi
    else
        echo "MPRIS bridge disabled: python with dbus-next not found" >>"$MPRIS_LOG_FILE"
    fi
else
    echo "MPRIS bridge disabled: bridge script not found" >>"$MPRIS_LOG_FILE"
fi

handle_control() {
    local ctrl="$1"
    case "$ctrl" in
        stop)
            queue_reason "stop"
            send_mpv_command '{ "command": ["stop"] }'
            return 10
            ;;
        next)
            queue_reason "next"
            send_mpv_command '{ "command": ["stop"] }'
            return 11
            ;;
        prev)
            queue_reason "prev"
            send_mpv_command '{ "command": ["stop"] }'
            return 12
            ;;
        quit)
            queue_reason "quit"
            send_mpv_command '{ "command": ["stop"] }'
            return 13
            ;;
        pause|play-pause|toggle)
            send_mpv_command '{ "command": ["cycle", "pause"] }'
            ;;
        play)
            send_mpv_command '{ "command": ["set_property", "pause", false] }'
            ;;
        volup)
            send_mpv_command '{ "command": ["add", "volume", 2.5] }'
            update_volume
            ;;
        voldown)
            send_mpv_command '{ "command": ["add", "volume", -2.5] }'
            update_volume
            ;;
        mute)
            send_mpv_command '{ "command": ["cycle", "mute"] }'
            update_volume
            ;;
        seekf)
            send_mpv_command '{ "command": ["seek", 10] }'
            ;;
        seekb)
            send_mpv_command '{ "command": ["seek", -10] }'
            ;;
    esac
    return 0
}

while read -r line; do
    ((LOOP_TICK++))

    if [[ "$line" =~ ^A: ]]; then
        PERCENT=${line:3}
        [ -n "$PERCENT" ] && update_percent "$PERCENT"

        elapsed="${PERCENT%%/*}"
        elapsed="${elapsed#"${elapsed%%[![:space:]]*}"}"
        elapsed="${elapsed%%.*}"
        if [[ "$elapsed" =~ ^[0-9]+:[0-9]{2}:[0-9]{2}$ ]]; then
            IFS=':' read -r hh mm ss <<< "$elapsed"
            current_second=$((10#$hh * 3600 + 10#$mm * 60 + 10#$ss))
            if [ "$current_second" -ne "$LAST_LYRIC_SECOND" ]; then
                show_lyrics "$current_second"
                LAST_LYRIC_SECOND=$current_second
            fi
        fi
    fi

    if [ $((LOOP_TICK % VOLUME_REFRESH_EVERY)) -eq 0 ]; then
        update_volume
    fi

    if cmd=$(read_command); then
        handle_control "$cmd"
        rc=$?
        if [ "$rc" -ge 10 ]; then
            break
        fi
    fi

    read -rsn1 -t 0.05 key < /dev/tty 2>/dev/null
    if [ "$key" = $'s' ]; then
        set_command "stop"
        handle_control "stop"
        break
    elif [ "$key" = $'n' ]; then
        set_command "next"
        handle_control "next"
        break
    elif [ "$key" = $'p' ]; then
        set_command "prev"
        handle_control "prev"
        break
    elif [ "$key" = $'q' ]; then
        set_command "quit"
        handle_control "quit"
        break
    elif [ "$key" = "=" ] || [ "$key" = "+" ]; then
        set_command "volup"
        handle_control "volup"
    elif [ "$key" = "-" ]; then
        set_command "voldown"
        handle_control "voldown"
    elif [ "$key" = " " ]; then
        set_command "toggle"
        handle_control "toggle"
    elif [ "$key" = "m" ]; then
        set_command "mute"
        handle_control "mute"
    elif [ "$key" = "f" ]; then
        set_command "seekf"
        handle_control "seekf"
    elif [ "$key" = "b" ]; then
        set_command "seekb"
        handle_control "seekb"
    fi
done < <(mpv $MPV_ARGS --force-media-title="$MPV_FORCE_TITLE" "$URL" 2>&1)

reason=$(cat "$REASON_FILE" 2>/dev/null)
case "$reason" in
    stop) exit 10 ;;
    next) exit 11 ;;
    prev) exit 12 ;;
    quit) exit 13 ;;
esac
exit 0
