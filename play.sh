#!/usr/bin/env bash

LOOP=false
SEARCH=""
LYRIC_OFFSET=1.0
DOWNLOAD=false
SHOW_LYRICS=true
FILEMODE=false
FILEPATH=""

BASE_DIR="$HOME/songs"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/terminal-player"
MPV_SOCKET="$RUNTIME_DIR/mpv.socket"
CMD_FILE="$RUNTIME_DIR/command"
REASON_FILE="$RUNTIME_DIR/reason"
METADATA_FILE="$RUNTIME_DIR/metadata.json"
EXTRADATA_FILE="$RUNTIME_DIR/extradata.json"
MPRIS_STOP_FILE="$RUNTIME_DIR/mpris.stop"
MPRIS_LOG_FILE="$RUNTIME_DIR/mpris.log"

for dep in yt-dlp mpv jq socat jp2a figlet magick curl; do
  command -v $dep >/dev/null || {
    echo "Missing: $dep"
    exit 1
  }
done

while [[ $# -gt 0 ]]; do
  case "$1" in
  -l | -L | --loop) LOOP=true ;;
  -n | --no-lyrics) SHOW_LYRICS=false ;;
  -d) DOWNLOAD=true ;;
  -f)
    FILEMODE=true
    FILEPATH="$2"
    shift
    ;;
  -L) LOOP=true ;;
  *) SEARCH="$SEARCH $1" ;;
  esac
  shift
done

SEARCH=$(echo "$SEARCH" | sed 's/^ *//;s/ *$//')
SAFE_QUERY=$(echo "$SEARCH" | sed 's#[/:*?"<>|]#_#g')
DEFAULT_DIR="$BASE_DIR/$SAFE_QUERY"
mkdir -p "$BASE_DIR"

if [ -d "$DEFAULT_DIR" ] && [ "$DOWNLOAD" = false ] && [ "$FILEMODE" = false ]; then
  FILEMODE=true
  FILEPATH="$DEFAULT_DIR"
fi

if [ "$DOWNLOAD" = true ]; then
  OUTDIR="$DEFAULT_DIR"
  mkdir -p "$OUTDIR"
  METADATA=$(yt-dlp "ytsearch1:$SEARCH" -q --print-json --skip-download)
  URL=$(echo "$METADATA" | jq -r '.webpage_url')
  TITLE=$(echo "$METADATA" | jq -r '.title')
  ARTIST=$(echo "$METADATA" | jq -r '.artist // .uploader // "N/A"')
  ALBUM=$(echo "$METADATA" | jq -r '.album // "N/A"')
  DATE=$(echo "$METADATA" | jq -r '.upload_date // "N/A"')
  UPLOADER=$(echo "$METADATA" | jq -r '.uploader // "N/A"')
  THUMB=$(echo "$METADATA" | jq -r '.thumbnail // empty')

  yt-dlp -x --audio-format mp3 --audio-quality 0 \
    --embed-thumbnail --embed-metadata \
    --convert-thumbnails jpg \
    -o "$OUTDIR/%(title)s.%(ext)s" "$URL"

  [ -n "$THUMB" ] && curl -fsSL "$THUMB" -o "$OUTDIR/cover.jpg"

  if [ "$SHOW_LYRICS" = true ]; then
    PYTHON=$(command -v python3 || command -v python)
    [ -n "$PYTHON" ] && "$PYTHON" -m syncedlyrics --synced-only -o="$OUTDIR/lyrics.lrc" "$SEARCH" >/dev/null 2>&1
  fi

  jq -n \
    --arg title "$TITLE" \
    --arg artist "$ARTIST" \
    --arg album "$ALBUM" \
    --arg date "$DATE" \
    --arg uploader "$UPLOADER" \
    --arg url "$URL" \
    --arg art_url "$THUMB" \
    --arg track_id "$(date +%s)-$$" \
    '{title:$title,artist:$artist,album:$album,date:$date,channel:$uploader,url:$url,art_url:$art_url,track_id:$track_id}' \
    >"$OUTDIR/metadata.json"

  echo "Saved to: $OUTDIR"
  exit 0
fi

# Stream mode (not downloading, not file/directory)
if [ "$FILEMODE" = false ]; then
  METADATA=$(yt-dlp "ytsearch1:$SEARCH" -q --print-json --skip-download)
  URL=$(echo "$METADATA" | jq -r '.webpage_url')
  TITLE=$(echo "$METADATA" | jq -r '.title')
  ARTIST=$(echo "$METADATA" | jq -r '.artist // .uploader // "N/A"')
  ALBUM=$(echo "$METADATA" | jq -r '.album // "N/A"')
  DATE=$(echo "$METADATA" | jq -r '.upload_date // "N/A"')
  UPLOADER=$(echo "$METADATA" | jq -r '.uploader // "N/A"')
  THUMB=$(echo "$METADATA" | jq -r '.thumbnail // empty')

  mkdir -p "$RUNTIME_DIR"
  COVER="$RUNTIME_DIR/cover.jpg"
  [ -n "$THUMB" ] && curl -fsSL "$THUMB" -o "$COVER"
  LYRICS="$RUNTIME_DIR/lyrics.lrc"
  if [ "$SHOW_LYRICS" = true ]; then
    PYTHON=$(command -v python3 || command -v python)
    [ -n "$PYTHON" ] && "$PYTHON" -m syncedlyrics --synced-only -o="$LYRICS" "$SEARCH" >/dev/null 2>&1
  fi

  jq -n \
    --arg title "$TITLE" \
    --arg artist "$ARTIST" \
    --arg album "$ALBUM" \
    --arg date "$DATE" \
    --arg uploader "$UPLOADER" \
    --arg url "$URL" \
    --arg art_url "$THUMB" \
    --arg track_id "$(date +%s)-$$" \
    '{title:$title,artist:$artist,album:$album,date:$date,channel:$uploader,url:$url,art_url:$art_url,track_id:$track_id}' \
    >"$METADATA_FILE"
fi

if [ "$FILEMODE" = true ]; then
  if [ -d "$FILEPATH" ]; then
    MP3=$(find "$FILEPATH" -maxdepth 1 -iname "*.mp3" | head -n1)
    URL="$MP3"
    COVER=$(find "$FILEPATH" -maxdepth 1 \( -iname "*.jpg" -o -iname "*.png" \) | head -n1)
    LYRICS="$FILEPATH/lyrics.lrc"
    METADATA_FILE="$FILEPATH/metadata.json"
    EXTRADATA_FILE="$FILEPATH/extradata.json"
    TITLE=$(basename "$MP3")
    TITLE="${TITLE%.mp3}"
  else
    URL="$FILEPATH"
    TITLE=$(basename "$FILEPATH")
    TITLE="${TITLE%.mp3}"
    COVER=""
    METADATA_FILE=""
    EXTRADATA_FILE=""
  fi
fi

mkdir -p "$RUNTIME_DIR"
rm -f "$MPV_SOCKET" "$CMD_FILE" "$REASON_FILE" "$MPRIS_STOP_FILE"
: >"$CMD_FILE"
: >"$REASON_FILE"
: >"$MPRIS_LOG_FILE"

# Load metadata and extradata
if [ -f "$METADATA_FILE" ]; then
  TITLE=$(jq -r '.title // "'"$TITLE"'"' "$METADATA_FILE")
  ARTIST=$(jq -r '.artist // empty' "$METADATA_FILE")
  ALBUM=$(jq -r '.album // empty' "$METADATA_FILE")
  DATE=$(jq -r '.date // empty' "$METADATA_FILE")
  UPLOADER=$(jq -r '.channel // empty' "$METADATA_FILE")
  URL=$(jq -r '.url // "'"$URL"'"' "$METADATA_FILE")
fi

if [ -f "$EXTRADATA_FILE" ]; then
  [ -z "$ARTIST" ] && ARTIST=$(jq -r '.artist // empty' "$EXTRADATA_FILE")
  [ -z "$ALBUM" ] && ALBUM=$(jq -r '.album // empty' "$EXTRADATA_FILE")
  [ -z "$DATE" ] && DATE=$(jq -r '.date // empty' "$EXTRADATA_FILE")
  [ -z "$UPLOADER" ] && UPLOADER=$(jq -r '.channel // empty' "$EXTRADATA_FILE")
fi

TERM_WIDTH=$(tput cols)
COVER_WIDTH=$((TERM_WIDTH / 2))

# Load cover
COVER_LINES=()
if [ -n "$COVER" ] && [ -f "$COVER" ]; then
  mapfile -t COVER_LINES < <(jp2a --colors --fill --width=$COVER_WIDTH "$COVER")
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
for ((i = 0; i < max_lines; i++)); do
  printf "%-${COVER_WIDTH}s  %s\n" "${COVER_LINES[i]}" "${INFO_LINES[i]}"
done

PERCENT_LINE=$((${#INFO_LINES[@]} - 2))
VOLUME_LINE=$((PERCENT_LINE + 1))
LYRICS_FILE=$(mktemp)
[ "$SHOW_LYRICS" = true ] && [ -f "$LYRICS" ] && cp "$LYRICS" "$LYRICS_FILE"

LAST_LYRIC=""
LYRIC_HEIGHT=24
LYRIC_START=$((${#COVER_LINES[@]} + 1))
LAST_LYRIC_SECOND=-1
LOOP_TICK=0
VOLUME_REFRESH_EVERY=50

update_percent() {
  local percent="$1"
  tput cup $PERCENT_LINE $COVER_WIDTH
  printf "  Percent: %s  " "$percent"
  tput cup $((max_lines + 2)) 0
}

update_volume() {
  [ ! -S "$MPV_SOCKET" ] && return
  vol=$(echo '{ "command": ["get_property", "volume"] }' | socat - "$MPV_SOCKET" 2>/dev/null | jq -r '.data // "N/A"')
  vol=${vol%.*}
  tput cup $VOLUME_LINE $COVER_WIDTH
  printf "  Volume: %s%%  " "$vol"
  tput cup $((max_lines + 2)) 0
}

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

  for ((i = 0; i < LYRIC_HEIGHT; i++)); do
    tput cup $((LYRIC_START + i)) 0
    tput el
  done

  tput cup $LYRIC_START 0
  if [ -n "$last" ]; then
    figlet -f small -w $TERM_WIDTH "$last"
  fi
}

send_mpv_command() {
  [ ! -S "$MPV_SOCKET" ] && return
  echo "$1" | socat - "$MPV_SOCKET" >/dev/null 2>&1
}
queue_reason() { printf "%s" "$1" >"$REASON_FILE"; }
set_command() { printf "%s" "$1" >"$CMD_FILE"; }
read_command() {
  [ -s "$CMD_FILE" ] || return 1
  tr -d '\r\n' <"$CMD_FILE"
  : >"$CMD_FILE"
}

MPV_ARGS="--no-video --no-cache --input-ipc-server=$MPV_SOCKET"
$LOOP && MPV_ARGS="$MPV_ARGS --loop"

# safer elapsed parser
parse_elapsed() {
  local elapsed="$1"
  elapsed="${elapsed%%.*}"
  IFS=':' read -r h m s <<<"0:0:0"
  parts=(${elapsed//:/ })
  if [ ${#parts[@]} -eq 3 ]; then
    h=${parts[0]}
    m=${parts[1]}
    s=${parts[2]}
  elif [ ${#parts[@]} -eq 2 ]; then
    h=0
    m=${parts[0]}
    s=${parts[1]}
  fi
  echo $((10#$h * 3600 + 10#$m * 60 + 10#$s))
}

while read -r line; do
  ((LOOP_TICK++))
  if [[ "$line" =~ ^A: ]]; then
    PERCENT=${line:3}
    [ -n "$PERCENT" ] && update_percent "$PERCENT"
    current_second=$(parse_elapsed "${PERCENT%%/*}")
    [ "$current_second" -ne "$LAST_LYRIC_SECOND" ] && show_lyrics "$current_second" && LAST_LYRIC_SECOND=$current_second
  fi

  ((LOOP_TICK % VOLUME_REFRESH_EVERY == 0)) && update_volume

  if cmd=$(read_command); then
    case "$cmd" in
    stop)
      queue_reason "stop"
      send_mpv_command '{ "command": ["stop"] }'
      exit 10
      ;;
    next)
      queue_reason "next"
      send_mpv_command '{ "command": ["stop"] }'
      exit 11
      ;;
    prev)
      queue_reason "prev"
      send_mpv_command '{ "command": ["stop"] }'
      exit 12
      ;;
    quit)
      queue_reason "quit"
      send_mpv_command '{ "command": ["stop"] }'
      exit 13
      ;;
    pause | play-pause | toggle) send_mpv_command '{ "command": ["cycle", "pause"] }' ;;
    play) send_mpv_command '{ "command": ["set_property", "pause", false] }' ;;
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
    seekf) send_mpv_command '{ "command": ["seek", 10] }' ;;
    seekb) send_mpv_command '{ "command": ["seek", -10] }' ;;
    esac
  fi

  read -rsn1 -t 0.05 key </dev/tty 2>/dev/null
  case "$key" in
  s)
    send_mpv_command '{ "command": ["stop"] }'
    exit 10
    ;;
  n)
    send_mpv_command '{ "command": ["stop"] }'
    exit 11
    ;;
  p)
    send_mpv_command '{ "command": ["stop"] }'
    exit 12
    ;;
  q)
    send_mpv_command '{ "command": ["stop"] }'
    exit 13
    ;;
  "=" | "+")
    send_mpv_command '{ "command": ["add", "volume", 5] }'
    update_volume
    ;;
  "-")
    send_mpv_command '{ "command": ["add", "volume", -5] }'
    update_volume
    ;;
  " ")
    send_mpv_command '{ "command": ["cycle", "pause"] }'
    ;;
  m)
    send_mpv_command '{ "command": ["cycle", "mute"] }'
    update_volume
    ;;
  f)
    send_mpv_command '{ "command": ["seek", 10] }'
    ;;
  b)
    send_mpv_command '{ "command": ["seek", -10] }'
    ;;
  esac

done < <(mpv $MPV_ARGS --force-media-title="$TITLE" "$URL" 2>&1)
