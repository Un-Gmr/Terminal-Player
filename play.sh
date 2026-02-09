#!/usr/bin/env bash

LOOP=false
SEARCH=""
LYRIC_OFFSET=0.0

for dep in yt-dlp mpv jq socat jp2a figlet magick; do
    command -v $dep >/dev/null||{ echo "Missing: $dep"; exit 1; }
done

for arg in "$@"; do
    if [ "$arg" = "-l" ]; then
        LOOP=true
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

LYRICS_FILE=$(mktemp /tmp/lyric.XXXXXX.lrc)
trap 'stty "$stty_orig"; rm -f "$COVER_FILE" "$LYRICS_FILE" "$COVER_FILE.cropped.png"; exit' INT TERM EXIT

if [ -n "$THUMB" ]; then
    COVER_FILE=$(mktemp /tmp/cover.XXXXXX.jpg)
    curl -fsSL "$THUMB" -o "$COVER_FILE"
    if [ -f "$COVER_FILE" ] && command -v notify-send >/dev/null 2>&1; then
        mapfile -t COVER_LINES < <(jp2a --colors --fill --width=$COVER_WIDTH "$COVER_FILE")
        magick "$COVER_FILE" -resize 128x128^ -gravity center -extent 128x128 "$COVER_FILE.cropped.png"
        #notify-send -u critical -t 5000 -i "$COVER_FILE.cropped.png" "Terminal-Player" "Playing: $TITLE-$ARTIST"
    fi
fi

INFO_LINES=(
    "Title:   $TITLE"
    "Artist:  $ARTIST"
    "Album:   $ALBUM"
    "Date:    $DATE"
    "Channel: $UPLOADER"
    "URL:     $URL"
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
VOLUME_LINE=$((PERCENT_LINE + 1))

update_percent() {
    local percent="$1"
    tput cup $PERCENT_LINE $COVER_WIDTH
    printf "  Percent: %s  " "$percent"
    tput cup $((max_lines+1)) 0
}

update_volume() {
    local vol
    vol=$(echo '{ "command": ["get_property", "volume"] }' | socat - /tmp/mpvsocket 2>/dev/null | jq -r '.data // "N/A"')
    vol=${vol%.*}
    tput cup $VOLUME_LINE $COVER_WIDTH
    printf "  Volume:  %s%%  " "$vol"
    tput cup $((max_lines+2)) 0
}

PYTHON=$(command -v python||command -v python3)||exit 1
"$PYTHON" -m syncedlyrics --synced-only -o="$LYRICS_FILE" "$SEARCH" >>/dev/null 2>/dev/null
[ ! -s "$LYRICS_FILE" ] && "$PYTHON" -m syncedlyrics --synced-only -o="$LYRICS_FILE" "[$TITLE] [$ARTIST]" >>/dev/null 2>/dev/null

LLYRIC_HEIGHT=24
LAST_LYRIC=""
LYRIC_START=$(( ${#COVER_LINES[@]} + 1 ))

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

    for ((i=0;i<LYRIC_HEIGHT;i++)); do
        tput cup $((LYRIC_START+i)) 0
        printf "%-${TERM_WIDTH}s" ""
    done

    tput cup $LYRIC_START 0
    figlet -f small -w=$TERM_WIDTH "$last"
}

MPV_ARGS="--no-video --input-ipc-server=/tmp/mpvsocket"
$LOOP && MPV_ARGS="$MPV_ARGS --loop"

stty_orig=$(stty -g)

mpv $MPV_ARGS "$URL" >> /dev/null 2>/dev/null &

MPV_PID=$!

while kill -0 $MPV_PID 2>/dev/null; do
    TIME_MS=$(echo '{ "command": ["get_property", "time-pos"] }' | socat - /tmp/mpvsocket 2>/dev/null | jq -r '.data // 0')
    show_lyrics "$TIME_MS"

    read -rsn1 -t 0.05 key < /dev/tty
    if [ "$key" = $'s' ]; then 
        pkill -P $$ mpv 2>/dev/null 
        break
    elif [ "$key" = "=" ] || [ "$key" = "+" ]; then
        echo '{ "command": ["add", "volume", 5] }' | socat - /tmp/mpvsocket
    elif [ "$key" = "-" ]; then
        echo '{ "command": ["add", "volume", -5] }' | socat - /tmp/mpvsocket
    elif [ "$key" = " " ]; then
        echo '{ "command": ["cycle", "pause"] }' | socat - /tmp/mpvsocket
    fi

    sleep 0.05
done &

stty "$stty_orig"
[ -n "$COVER_FILE" ] && rm -f "$COVER_FILE"
rm -f "$LYRICS_FILE"
rm -f "$COVER_FILE.cropped.png"
