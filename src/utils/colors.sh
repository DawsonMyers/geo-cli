# Regex to find color control codes: (\\\[)?(\\e|\\033)\[(\d+;)*\d+m
#Remove color codes: echo $txt | sed 's/\x1b\[[0-9;]*m//g'
CHECK_MARK="\033[0;32m\xE2\x9C\x94\033[0m"
EMOJI_CHECK_MARK=✔️
EMOJI_CHECK_MARK_GREEN='\033[0;32m✔\033[0m'
# EMOJI_CHECK_MARK=\[\033[0;32m\]✔\[\033[0m\]  escaped for a prompt
EMOJI_RED_X=❌
EMOJI_RED_X_SMALL=✘
EMOJI_RED_X_SMALL_RED='\033[0;31m✘\033[0m'
# EMOJI_RED_X_SMALL_RED='\[\033[0;31m\]✘\[\033[0m\]'
EMOJI_BULLET='•'

# 256 colors (only supported by vte terminals)

for i in {1..256}; do
    eval "VTE_COLOR_${i}=\"\e[38;5;${i}m\""
done

display_vte_colors() {
    for i in {1..256}; do
        printf '%-5s' `echo -en "\e[38;5;${i}m ${i} "`
        (( i % 8 == 0 )) && echo
    done
}

# Reset
Off='\033[0m'       # Text Reset

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

# Bold
BBlack='\033[1;30m'       # Black
BRed='\033[1;31m'         # Red
BGreen='\033[1;32m'       # Green
BYellow='\033[1;33m'      # Yellow
BBlue='\033[1;34m'        # Blue
BPurple='\033[1;35m'      # Purple
BCyan='\033[1;36m'        # Cyan
BWhite='\033[1;37m'       # White

# Underline
UBlack='\033[4;30m'       # Black
URed='\033[4;31m'         # Red
UGreen='\033[4;32m'       # Green
UYellow='\033[4;33m'      # Yellow
UBlue='\033[4;34m'        # Blue
UPurple='\033[4;35m'      # Purple
UCyan='\033[4;36m'        # Cyan
UWhite='\033[4;37m'       # White

# Background
On_Black='\033[40m'       # Black
On_Red='\033[41m'         # Red
On_Green='\033[42m'       # Green
On_Yellow='\033[43m'      # Yellow
On_Blue='\033[44m'        # Blue
On_Purple='\033[45m'      # Purple
On_Cyan='\033[46m'        # Cyan
On_White='\033[47m'       # White

# High Intensity
IBlack='\033[0;90m'       # Black
IRed='\033[0;91m'         # Red
IGreen='\033[0;92m'       # Green
IYellow='\033[0;93m'      # Yellow
IBlue='\033[0;94m'        # Blue
IPurple='\033[0;95m'      # Purple
ICyan='\033[0;96m'        # Cyan
IWhite='\033[0;97m'       # White

# Bold High Intensity
BIBlack='\033[1;90m'      # Black
BIRed='\033[1;91m'        # Red
BIGreen='\033[1;92m'      # Green
BIYellow='\033[1;93m'     # Yellow
BIBlue='\033[1;94m'       # Blue
BIPurple='\033[1;95m'     # Purple
BICyan='\033[1;96m'       # Cyan
BIWhite='\033[1;97m'      # White

# High Intensity backgrounds
On_IBlack='\033[0;100m'   # Black
On_IRed='\033[0;101m'     # Red
On_IGreen='\033[0;102m'   # Green
On_IYellow='\033[0;103m'  # Yellow
On_IBlue='\033[0;104m'    # Blue
On_IPurple='\033[0;105m'  # Purple
On_ICyan='\033[0;106m'    # Cyan
On_IWhite='\033[0;107m'   # White

# Format functions
BOLD_ON="\e[1m"
BOLD_OFF="\e[21m"
DIM_ON="\e[2m"
DIM_OFF="\e[22m"
ITALIC_ON="\e[3m"
ITALIC_OFF="\e[23m"
UNDERLINE_ON="\e[4m"
UNDERLINE_OFF="\e[24m"
BLINK_ON="\e[5m"
BLINK_OFF="\e[25m"
INVERT_ON="\e[7m"
INVERT_OFF="\e[27m"
HIDE_ON="\e[8m"
HIDE_OFF="\e[28m"

txt_bold() {
    echo -en "\e[1m$@\e[21m"
}

# Dim/light text.
txt_dim() {
    echo -en "\e[2m$@\e[22m"
}

txt_italic() {
    echo -en "\e[3m$@\e[23m"
}

txt_underline() {
    echo -en "\e[4m$@\e[24m"
}

# Blinking text.
txt_blink() {
    echo -en "\e[5m$@\e[25m"
}

# Inverts foreground/background text color.
txt_invert() {
    echo -en "\e[7m$@\e[27m"
}

# Hides the text.
txt_hide() {
    echo -en "\e[8m$@\e[28m"
}

# (\\\[)? \d+m?;\d+m(\\\])?

# Bash colors
#####################
# Bold
# BBlack='\[\033[1;30m\]'       # Black
# BRed='\[\033[1;31m\]'         # Red
# BGreen='\[\033[1;32m\]'       # Green
# BYellow='\[\033[1;33m\]'      # Yellow
# BBlue='\[\033[1;34m\]'        # Blue
# BPurple='\[\033[1;35m\]'      # Purple
# BCyan='\[\033[1;36m\]'        # Cyan
# BWhite='\[\033[1;37m\]'       # White

# # Underline
# UBlack='\[\033[4;30m\]'       # Black
# URed='\[\033[4;31m\]'         # Red
# UGreen='\[\033[4;32m\]'       # Green
# UYellow='\[\033[4;33m\]'      # Yellow
# UBlue='\[\033[4;34m\]'        # Blue
# UPurple='\[\033[4;35m\]'      # Purple
# UCyan='\[\033[4;36m\]'        # Cyan
# UWhite='\[\033[4;37m\]'       # White

# # Background
# On_Black='\[\033[40m\]'       # Black
# On_Red='\[\033[41m\]'         # Red
# On_Green='\[\033[42m\]'       # Green
# On_Yellow='\[\033[43m\]'      # Yellow
# On_Blue='\[\033[44m\]'        # Blue
# On_Purple='\[\033[45m\]'      # Purple
# On_Cyan='\[\033[46m\]'        # Cyan
# On_White='\[\033[47m\]'       # White

# # High Intensity
# IBlack='\[\033[0;90m\]'       # Black
# IRed='\[\033[0;91m\]'         # Red
# IGreen='\[\033[0;92m\]'       # Green
# IYellow='\[\033[0;93m\]'      # Yellow
# IBlue='\[\033[0;94m\]'        # Blue
# IPurple='\[\033[0;95m\]'      # Purple
# ICyan='\[\033[0;96m\]'        # Cyan
# IWhite='\[\033[0;97m\]'       # White

# # Bold High Intensity
# BIBlack='\[\033[1;90m\]'      # Black
# BIRed='\[\033[1;91m\]'        # Red
# BIGreen='\[\033[1;92m\]'      # Green
# BIYellow='\[\033[1;93m\]'     # Yellow
# BIBlue='\[\033[1;94m\]'       # Blue
# BIPurple='\[\033[1;95m\]'     # Purple
# BICyan='\[\033[1;96m\]'       # Cyan
# BIWhite='\[\033[1;97m\]'      # White

# # High Intensity backgrounds
# On_IBlack='\[\033[0;100m\]'   # Black
# On_IRed='\[\033[0;101m\]'     # Red
# On_IGreen='\[\033[0;102m\]'   # Green
# On_IYellow='\[\033[0;103m\]'  # Yellow
# On_IBlue='\[\033[0;104m\]'    # Blue
# On_IPurple='\[\033[0;105m\]'  # Purple
# On_ICyan='\[\033[0;106m\]'    # Cyan
# On_IWhite='\[\033[0;107m\]'   # White

########################################################################
# RGB hex colors
########################################################################
# https://unix.stackexchange.com/questions/269077/tput-setaf-color-table-how-to-determine-color-codes

# Color       #define       Value       RGB
# black     COLOR_BLACK       0     0, 0, 0
# red       COLOR_RED         1     max,0,0
# green     COLOR_GREEN       2     0,max,0
# yellow    COLOR_YELLOW      3     max,max,0
# blue      COLOR_BLUE        4     0,0,max
# magenta   COLOR_MAGENTA     5     max,0,max
# cyan      COLOR_CYAN        6     0,max,max
# white     COLOR_WHITE       7     max,max,max

# printf '\e[%sm▒' {30..37} 0; echo           ### foreground
# printf '\e[%sm ' {40..47} 0; echo           ### background
# printf '\e[48;5;%dm ' {0..255}; printf '\e[0m \n' # prints whole spectrum of colors.

mode2header(){
    #### For 16 Million colors use \e[0;38;2;R;G;Bm each RGB is {0..255}
    printf '\e[mR\n' # reset the colors.
    printf '\n\e[m%59s\n' "Some samples of colors for r;g;b. Each one may be 000..255"
    printf '\e[m%59s\n'   "for the ansi option: \e[0;38;2;r;g;bm or \e[0;48;2;r;g;bm :"
}
mode2colors(){
    # foreground or background (only 3 or 4 are accepted)
    local fb="$1"
    [[ $fb != 3 ]] && fb=4
    local samples=(0 63 127 191 255)
    for         r in "${samples[@]}"; do
        for     g in "${samples[@]}"; do
            for b in "${samples[@]}"; do
                printf '\e[0;%s8;2;%s;%s;%sm%03d;%03d;%03d ' "$fb" "$r" "$g" "$b" "$r" "$g" "$b"
            done; printf '\e[m\n'
        done; printf '\e[m'
    done; printf '\e[mReset\n'
}

color(){
    for c; do
        printf '\e[48;5;%dm%03d' $c $c
    done
    printf '\e[0m \n'
}

# IFS=$' \t\n'
# color {0..15}
# for ((i=0;i<6;i++)); do
#     color $(seq $((i*36+16)) $((i*36+51)))
# done
# color {232..255}

# Exaple of the following function:
#   $ fromhex 00fc7b
#   048
#   $ fromhex #00fc7b
#   048
fromhex(){
    hex=${1#"#"}
    r=$(printf '0x%0.2s' "$hex")
    g=$(printf '0x%0.2s' ${hex#??})
    b=$(printf '0x%0.2s' ${hex#????})
    printf '%03d' "$(( (r<75?0:(r-35)/40)*6*6 + 
                       (g<75?0:(g-35)/40)*6   +
                       (b<75?0:(b-35)/40)     + 16 ))"
}

tohex(){
    dec=$(($1%256))   ### input must be a number in range 0-255.
    if [ "$dec" -lt "16" ]; then
        bas=$(( dec%16 ))
        mul=128
        [ "$bas" -eq "7" ] && mul=192
        [ "$bas" -eq "8" ] && bas=7
        [ "$bas" -gt "8" ] && mul=255
        a="$((  (bas&1)    *mul ))"
        b="$(( ((bas&2)>>1)*mul ))" 
        c="$(( ((bas&4)>>2)*mul ))"
        printf 'dec= %3s basic= #%02x%02x%02x\n' "$dec" "$a" "$b" "$c"
    elif [ "$dec" -gt 15 ] && [ "$dec" -lt 232 ]; then
        b=$(( (dec-16)%6  )); b=$(( b==0?0: b*40 + 55 ))
        g=$(( (dec-16)/6%6)); g=$(( g==0?0: g*40 + 55 ))
        r=$(( (dec-16)/36 )); r=$(( r==0?0: r*40 + 55 ))
        printf 'dec= %3s color= #%02x%02x%02x\n' "$dec" "$r" "$g" "$b"
    else
        gray=$(( (dec-232)*10+8 ))
        printf 'dec= %3s  gray= #%02x%02x%02x\n' "$dec" "$gray" "$gray" "$gray"
    fi
}

# for i in $(seq 0 255); do
#     tohex ${i}
# done