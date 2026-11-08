#!/usr/bin/env bash
# RetroPie splashscreen player: preserve VLC on Raspberry Pi, enable MPV on X11 ARM.
set -u
ROOTDIR=""
DATADIR=""
REGEX_VIDEO=""
REGEX_IMAGE=""
CMD_OPTS=""
CONFIG="/opt/retropie/configs/all/splashscreen.cfg"
PID_FILE="/dev/shm/rp-splashscreen.pid"
LOG_FILE="/tmp/rp-splashscreen.log"
[[ -r "$CONFIG" ]] && source "$CONFIG"
RANDOMIZE="${RANDOMIZE:-disabled}"
DURATION="${DURATION:-12}"
[[ "$DURATION" =~ ^[0-9]+$ ]] || DURATION=12
(( DURATION > 0 )) || DURATION=12
image_regex='\.(bmp|jpe?g|gif|png|ppm|tiff|webp)$'
video_regex='\.(avi|mov|mp4|mkv|3gp|mpg|mpeg|mp3|wav|m4a|aac|ogg|flac|webm)$'
matches() { [[ "${1,,}" =~ $image_regex|$video_regex ]]; }
image_file() { [[ "${1,,}" =~ $image_regex ]]; }
get_list() {
    local path
    case "$RANDOMIZE" in
        retropie) path="$ROOTDIR/supplementary/splashscreen";;
        custom) path="$DATADIR/splashscreens";;
        all) find "$ROOTDIR/supplementary/splashscreen" "$DATADIR/splashscreens" -type f -print0 2>/dev/null
             return;;
        list) [[ -r /etc/splashscreen.list ]] && while IFS= read -r path; do
                  [[ -f "$path" ]] && matches "$path" && printf '%s\0' "$path"
              done </etc/splashscreen.list
              return;;
        *) [[ -r /etc/splashscreen.list ]] && while IFS= read -r path; do
                  [[ -f "$path" ]] && matches "$path" && printf '%s\0' "$path"
              done </etc/splashscreen.list
           return;;
    esac
    [[ -d "$path" ]] && find "$path" -type f -print0 2>/dev/null
}
stop_player() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        read -r pid < "$PID_FILE" || true
        if [[ "$pid" =~ ^[0-9]+$ ]]; then kill "$pid" 2>/dev/null || true; fi
        rm -f "$PID_FILE"
    fi
}
start_player() {
    local -a files=() valid=() args=()
    local file delay player
    mapfile -d '' -t files < <(get_list)
    for file in "${files[@]}"; do [[ -f "$file" ]] && matches "$file" && valid+=("$file"); done
    (( ${#valid[@]} )) || { echo "No splashscreens selected" >> "$LOG_FILE"; return 1; }
    if [[ "$RANDOMIZE" != disabled ]]; then
        file="${valid[RANDOM % ${#valid[@]}]}"
        valid=("$file")
    fi
    delay=$(( DURATION / ${#valid[@]} ))
    (( delay > 0 )) || delay=1
    player="${SPLASH_PLAYER:-auto}"
    if [[ "$player" == auto ]]; then
        if [[ -n "${DISPLAY:-}" ]] && command -v mpv >/dev/null 2>&1; then player=mpv
        else player=vlc; fi
    fi
    if [[ "$player" == mpv ]]; then
        command -v mpv >/dev/null || { echo "mpv not installed" >> "$LOG_FILE"; return 1; }
        # MPV treats images as single frames: use --image-display-duration.
        args=(--no-config --really-quiet --fullscreen --force-window=immediate
              --image-display-duration="$delay" --keep-open=no --)
        mpv "${args[@]}" "${valid[@]}" >>"$LOG_FILE" 2>&1 &
    else
        command -v vlc >/dev/null || { echo "vlc not installed" >> "$LOG_FILE"; return 1; }
        vlc --intf dummy --quiet --no-video-title-show --play-and-exit --image-duration "$delay" "${valid[@]}" >>"$LOG_FILE" 2>&1 &
    fi
    echo "$!" > "$PID_FILE"
}
case "${1:-start}" in
 start) start_player;;
 stop) stop_player;;
 status) [[ -s "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null;;
 *) echo "Usage: $0 {start|stop|status}" >&2; exit 2;;
esac
