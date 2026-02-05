#!/usr/bin/env bash

LOOP=false
SEARCH=""
LYRIC_OFFSET=1

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

LYRICS_FILE=""
COVER_FILE=""
LYRICS_FILE=$(mktemp /tmp/lyric.XXXXXX.lrc)
trap 'rm -f "$COVER_FILE" "$LYRICS_FILE"; stty ixon echo; exit' INT

if [ -n "$THUMB" ]; then
    COVER_FILE=$(mktemp /tmp/cover.XXXXXX.jpg)
    curl -fsSL "$THUMB" -o "$COVER_FILE"
    if [ -f "$COVER_FILE" ]; then
        mapfile -t COVER_LINES < <(jp2a --colors --fill --width=$COVER_WIDTH "$COVER_FILE")
        magick "$COVER_FILE" -resize 128x128^ -gravity center -extent 128x128 "$COVER_FILE.cropped.png"
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
    "Percent: 00:00:00 / 00:00:00 (0%)"
    "Volume:  100%"
)

clear

max_lines=${#COVER_LINES[@]}
if [ ${#INFO_LINES[@]} -gt $max_lines ]; then
    max_lines=${#INFO_LINES[@]}
fi

for ((i=0; i<max_lines; i++)); do
    printf "%-${COVER_WIDTH}s  %s\n" \
        "${COVER_LINES[i]}" \
        "${INFO_LINES[i]}"
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

#notify-send -u critical -t 5000 -i "$COVER_FILE.cropped.png" "Debug" "$SEARCH"

PYTHON=$(command -v python||command -v python3)||exit 1
"$PYTHON" -m syncedlyrics --synced-only -o="$LYRICS_FILE" "$SEARCH" >>/dev/null 2>/dev/null
if [ ! -f $LYRICS_FILE ]; then
    "$PYTHON" -m syncedlyrics --synced-only -o="$LYRICS_FILE" "[$TITLE] [$ARTIST]" >>/dev/null 2>/dev/null
fi

LYRIC_HEIGHT=24

show_lyrics() {
    local time="$1"
    local mm ss cur last
    mm=${time:3:2}
    ss=${time:6:2}
    cur=$((10#$mm*60 + 10#$ss + LYRIC_OFFSET))
    [ "$cur" -lt 0 ] && cur=0

    last=$(awk -F']' -v t="$cur" '
        {
            gsub(/^\[/,"",$1)
            split($1,ts,":")
            cur=int(ts[1]*60 + ts[2])
            if(cur<=t) last=$2
        }
        END{
            gsub(/\n/,"",last)
            print last
        }
    ' "$LYRICS_FILE")

    local start_line=$((max_lines + 1))

    for ((i=0;i<LYRIC_HEIGHT;i++)); do
        tput cup $((start_line+i)) 0
        printf "%-${TERM_WIDTH}s" ""
    done

    tput cup $start_line 0
    toilet -f small -w $TERM_WIDTH "$last"
}

MPV_ARGS="--no-video --cache=no --input-ipc-server=/tmp/mpvsocket"
$LOOP && MPV_ARGS="$MPV_ARGS --loop"

stty_orig=$(stty -g)

PERCENT="0%"
mpv $MPV_ARGS "$URL" 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"A:"* ]]; then
        PERCENT="${line#*A:}"
        PERCENT="${PERCENT#"${PERCENT%%[![:space:]]*}"}"
        TIME="${PERCENT:0:8}"
        update_percent "$PERCENT"
        update_volume
        show_lyrics "$TIME"
    fi

    read -rsn1 -t 0.01 key < /dev/tty
        if [ "$key" = $'s' ]; then 
            pkill -P $$ mpv 2>/dev/null 
            break
        elif [ "$key" = $'=' ]; then
            echo '{ "command": ["add", "volume", 5] }' | socat - /tmp/mpvsocket
        elif [ "$key" = $'+' ]; then
            echo '{ "command": ["add", "volume", 5] }' | socat - /tmp/mpvsocket
        elif [ "$key" = $'-' ]; then
            echo '{ "command": ["add", "volume", -5] }' | socat - /tmp/mpvsocket
        elif [ "$key" = " " ]; then
            echo '{ "command": ["cycle", "pause"] }' | socat - /tmp/mpvsocket
        fi
done

stty "$stty_orig"
[ -n "$COVER_FILE" ] && rm -f "$COVER_FILE"
rm -f "$LYRICS_FILE"