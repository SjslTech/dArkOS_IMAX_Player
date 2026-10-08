#!/bin/bash

# --- Initial Setup ---
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_NAME=$(basename "$SCRIPT_PATH")
CURR_TTY="/dev/tty1"
REAL_USER=${SUDO_USER:-$USER}
VIDEO_DIR="/roms/movies"

exec > $CURR_TTY 2>&1
printf "\033c" > "$CURR_TTY"
export TERM=linux
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Ensure video directory exists
mkdir -p "$VIDEO_DIR"

# Controller Setup
pkill -9 -f gptokeyb || true
if [ -f "/opt/inttools/gptokeyb" ]; then
    [[ -e /dev/uinput ]] && chmod 666 /dev/uinput 2>/dev/null || true
    export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
    /opt/inttools/gptokeyb -1 "$SCRIPT_NAME" -c "/opt/inttools/keys.gptk" >/dev/null 2>&1 &
fi

# Cleanup Function
ExitScript() {
    pkill -f "gptokeyb -1 $SCRIPT_NAME" || true
    pkill -9 ffplay 2>/dev/null
    printf "\033c\e[?25h" > "$CURR_TTY"
    exit 0
}
trap ExitScript EXIT SIGINT SIGTERM
printf "\e[?25l" > "$CURR_TTY"

# File Picker Function
pick_video() {
    local files=()
    local i=1
    while IFS= read -r line; do
        files+=("$i" "$(basename "$line")")
        ((i++))
    done < <(find "$VIDEO_DIR" -maxdepth 1 -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o -name "*.mov" \) | sort)
    
    if [ ${#files[@]} -eq 0 ]; then
        dialog --msgbox "No videos found in $VIDEO_DIR" 10 40
        return
    fi

    choice=$(dialog --backtitle "R36S Multi-Screen IMAX Player by SjslTech" --title " SELECT MOVIE " --menu "Choose a video to play:" 15 55 10 "${files[@]}" --output-fd 1)
    [ $? -ne 0 ] && { echo "CANCELLED"; return; }
    local index=$(( (choice - 1) * 2 + 1 ))
    echo "$VIDEO_DIR/${files[$index]}"
}

# --- Main Menu ---

while true; do
    MAIN_CHOICE=$(dialog --backtitle "R36S Multi-Screen IMAX Player by SjslTech" --title " MAIN MENU " \
        --menu "Select screen layout configuration:" 14 55 6 \
        1 "2-Screen: Left Half" \
        2 "2-Screen: Right Half" \
        3 "3-Screen: Left Slice (1/3)" \
        4 "3-Screen: Middle Slice (2/3)" \
        5 "3-Screen: Right Slice (3/3)" \
        6 "Exit" --output-fd 1)

    case "$MAIN_CHOICE" in
        1|2|3|4|5)
            SELECTED_VIDEO=$(pick_video)
            [ "$SELECTED_VIDEO" == "CANCELLED" ] && continue

            # Audio Option Prompt
            dialog --backtitle "R36S Multi-Screen IMAX Player by SjslTech" \
                   --title " AUDIO CONFIGURATION " \
                   --yesno "Enable audio on this device?\n\n(Select YES for primary unit, NO to mute)" 8 45
            
            if [ $? -eq 0 ]; then
                AUDIO_FLAG=""      # Enable sound
            else
                AUDIO_FLAG="-an"   # Mute sound
            fi

            pkill -9 ffplay 2>/dev/null

            # Native FFmpeg expressions for dynamic resolution parsing
            case "$MAIN_CHOICE" in
                1)
                    # 2-Screen Left: Width = in_w/2, x = 0
                    CROP_FILTER="crop=w=in_w/2:h=in_h:x=0:y=0,scale=640:480,setsar=1"
                    ;;
                2)
                    # 2-Screen Right: Width = in_w/2, x = in_w/2
                    CROP_FILTER="crop=w=in_w/2:h=in_h:x=in_w/2:y=0,scale=640:480,setsar=1"
                    ;;
                3)
                    # 3-Screen Left: Width = in_w/3, x = 0
                    CROP_FILTER="crop=w=in_w/3:h=in_h:x=0:y=0,scale=640:480,setsar=1"
                    ;;
                4)
                    # 3-Screen Middle: Width = in_w/3, x = in_w/3
                    CROP_FILTER="crop=w=in_w/3:h=in_h:x=in_w/3:y=0,scale=640:480,setsar=1"
                    ;;
                5)
                    # 3-Screen Right: Width = in_w/3, x = (in_w/3)*2
                    CROP_FILTER="crop=w=in_w/3:h=in_h:x=(in_w/3)*2:y=0,scale=640:480,setsar=1"
                    ;;
            esac

            dialog --infobox "Starting video..." 3 30
            sleep 1

            # Clear console screen before playback launch
            printf "\033c" > "$CURR_TTY"

            # Launch ffplay directly
            sudo -u "$REAL_USER" ffplay -hide_banner $AUDIO_FLAG -vf "$CROP_FILTER" -x 640 -y 480 -noborder "$SELECTED_VIDEO" >/dev/null 2>&1
            
            # Fallback check
            if [ $? -ne 0 ]; then
                ffplay -hide_banner $AUDIO_FLAG -vf "$CROP_FILTER" -x 640 -y 480 -noborder "$SELECTED_VIDEO" >/dev/null 2>&1
                if [ $? -ne 0 ]; then
                    dialog --msgbox "Error: ffplay failed to open the selected video." 8 45
                fi
            fi
            ;;
        6|*)
            ExitScript
            ;;
    esac
done
