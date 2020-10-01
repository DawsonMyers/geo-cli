CHECK_MARK="\033[0;32m\xE2\x9C\x94\033[0m"
EMOJI_CHECK_MARK=✔️
EMOJI_RED_X=❌

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

# 256 colors (only supported by vte terminals)

for i in {1..256}; do
    eval "VTE_Color_${i}=\"\e[38;5;${i}m\""
done

display_vte_colors() {
    for i in {1..256}; do
        printf '%-5s' `echo -en "\e[38;5;${i}m ${i} "`
        (( i % 8 == 0 )) && echo
    done
}

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