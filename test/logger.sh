# variants=("e " "en _prompt")
# styles=("" B I BI U)
# for variant in "${variants[@]}"; do
#         read -a args <<< "$variant"
#         options=${args[0]}
#         suffix=${args[1]}
# 	# for style in "${styles[@]}"; do
# 	# 	echo "info_b${suffix}() { echo -${options} ${style}cmd"
# 	# done
#     # Variants are created by creating var names through multiple passes of string
#     # interpolation.
#     n=warn
#     color=Red
#     echo "${n}${suffix}() { echo -${options} \"\${${color}}\$@\${Off}\"; }"
#     echo "${n}_b${suffix}() { echo -${options} \"\${B${color}}\$@\${Off}\"; }"
#     echo "${n}_i${suffix}() { echo -${options} \"\${I${color}}\$@\${Off}\"; }"
#     echo "${n}_bi${suffix}() { echo -${options} \"\${BI${color}}\$@\${Off}\"; }"
#     echo "${n}_u${suffix}() { echo -${options} \"\${U${color}}\$@\${Off}\"; }"
# done

make_logger_function() {
    # The placement of the \ chars are very important for delaying the evaluation of
    # the shell vars in the strings. Notice how ${1}, ${2}, and ${Off} appear without
    # $ being prefixed with a \. This is because we want the the args to be filled in
    # immediately. So if this func is called with 'info' and 'Green' as args, the
    # string passed to eval would be "info() { echo -e \"\${Green}\$@${Off}"; }".
    # Which would then create a function called info that would take all of its args
    # and echo them out with green text colour. This is done by first echoing the
    # non-printable char for green text stored in the var $Green, then echoing the
    # text, and finally, echoing the remove all format char stored in $Off.
    # local variants=("e " "en _prompt")
    # for variant in "${variants[@]}"; do
    #     read -a args <<< "$variant"
    #     local options=${args[0]}
    #     local suffix=${args[1]}

        # Variants are created by creating var names through multiple passes of string
        # interpolation.
        suffix=""
        # options=e
        name=$1
        color=$2
        eval "${name}() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${${color}}\${args[@]}\${Off}\"; }"
        eval "${name}_b() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${B${color}}\${args[@]}\${Off}\"; }"
        eval "${name}_i() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${I${color}}\${args[@]}\${Off}\"; }"
        eval "${name}_bi() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${BI${color}}\${args[@]}\${Off}\"; }"
        eval "${name}_u() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${U${color}}\${args[@]}\${Off}\"; }"
        # eval "warn() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${Red}\${args[@]}\${Off}\"; }"
        # echo "${1}${suffix}() { opt=e; [[ \$1 =~ ^-p ]] && opt=en && shift; echo -\${opt} \"\${${2}}\$@\${Off}\"; }"
        # eval "${1}${suffix}() { echo -${options} \"\${${2}}\$@\${Off}\"; }"
        # eval "${1}_b${suffix}() { echo -${options} \"\${B${2}}\$@\${Off}\"; }"
        # eval "${1}_i${suffix}() { echo -${options} \"\${I${2}}\$@\${Off}\"; }"
        # eval "${1}_bi${suffix}() { echo -${options} \"\${BI${2}}\$@\${Off}\"; }"
        # eval "${1}_u${suffix}() { echo -${options} \"\${U${2}}\$@\${Off}\"; }"

        # suffix="_prompt"
        # options=en
        # echo "${1}${suffix}() { echo -${options} \"\${${2}}\$@\${Off}\"; }"
        # eval "${1}${suffix}() { echo -${options} \"\${${2}}\$@\${Off}\"; }"
        # eval "${1}_b${suffix}() { echo -${options} \"\${B${2}}\$@\${Off}\"; }"
        # eval "${1}_i${suffix}() { echo -${options} \"\${I${2}}\$@\${Off}\"; }"
        # eval "${1}_bi${suffix}() { echo -${options} \"\${BI${2}}\$@\${Off}\"; }"
        # eval "${1}_u${suffix}() { echo -${options} \"\${U${2}}\$@\${Off}\"; }"

        # echo "${1}_u${suffix}"
        # "${1}_u" -p test
    # done
}

make_logger_function warn Red
# suffix=_prompt
# options=en
# n=info
# color=Cyan
# echo "${n}${suffix}() { echo -${options} \"\${${color}}\$@\${Off}\"; }"
# eval "${n}${suffix}() { echo -${options} \"\${${color}}\$@\${Off}\"; }"

# args=(-p some log)
# unset "args[0]"
# echo "${args[@]}"
