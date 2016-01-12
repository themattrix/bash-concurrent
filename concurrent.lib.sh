concurrent() (
    # Requires: bash v4, sed, tput, date, ls, mktemp

    set -e -o pipefail  # Exit on failed command
    shopt -s nullglob   # Empty glob evaluates to nothing instead of itself

    txtred='\e[0;31m' # Red
    txtgrn='\e[0;32m' # Green
    txtylw='\e[0;33m' # Yellow
    txtblu='\e[0;34m' # Blue
    txtrst='\e[0m'    # Text Reset

    pending_msg="        "
    running_msg=" ${txtblu}    ->${txtrst} "
    success_msg=" ${txtgrn}  OK  ${txtrst} "
    failure_msg=" ${txtred}FAILED${txtrst} "
    skipped_msg=" ${txtylw} SKIP ${txtrst} "

    error() {
        echo -e "[${txtred}ERROR${txtrst}] ${1}" 1>&2
        exit 1
    }

    indent() {
        sed 's/^/    /' "${@}"
    }

    name_index() {
        local name=${1}
        local i
        for i in "${!names[@]}"; do
            if [[ "${names[${i}]}" == "${name}" ]]; then
                printf '%s' "${i}"
                return
            fi
        done
        error "Failed to find task named '${name}'"
    }

    start_command() {
        {
            array_name="command_${1}[@]"
            set +e
            "${!array_name}" &> "${status_dir}/${1}"
            code=$?
            mv "${status_dir}/${1}"{,.done.${code}}
        } &
        start["${1}"]=true
        draw_status "${1}" running
    }

    skip_command() {
        start["${1}"]=true
        echo "[SKIPPED] Prereq '${2}' failed or was skipped" > "${status_dir}/${1}.done.skip"
    }

    command_started() {
        [[ "${start[${1}]}" == "true" ]]
    }

    command_may_start() {
        local before=${1}
        if command_started "${before}"; then
            return 1  # cannot start again
        fi
        local requires
        local wait_array="waits_${before}[@]"
        for requires in "${!wait_array}"; do
            if [[ -z "${codes[${requires}]}" ]]; then
                return 1
            elif [[ "${codes[${requires}]}" != "0" ]]; then
                skip_command "${before}" "${names[${requires}]}"
                return 1
            fi
        done
        return 0
    }

    start_all() {
        status_dir=$(mktemp -d "${TMPDIR:-/tmp}/concurrent.lib.sh.XXXXXXXXXXXXXXXX")
        trap 'rm -rf "${status_dir}"' EXIT
        local i
        for (( i = 0; i < commands; i++ )); do
            echo -e "${pending_msg}${names[${i}]}"
        done
        tput cuu "${commands}"
        tput sc
        start_allowed
    }

    start_allowed() {
        local i
        for (( i = 0; i < commands; i++ )); do
            if command_may_start "${i}"; then
                start_command "${i}"
            fi
        done
    }

    wait_for_all() {
        cd "${status_dir}"
        local i
        local f
        for (( i = 0; i < commands; i++ )); do
            wait -n || :
            while compgen -G '*.done.*' > /dev/null; do
                for f in *.done.*; do
                    handle_done "${f}"
                done
                start_allowed
            done
        done
        tput cud "${commands}"
    }

    draw_status() {
        local index=${1}
        local code=${2}
        tput rc
        [[ "${index}" -eq 0 ]] || tput cud "${index}"
        if   [[ "${code}" == "running" ]]; then echo -en "${running_msg}"
        elif [[ "${code}" == "skip"    ]]; then echo -en "${skipped_msg}"
        elif [[ "${code}" == "0"       ]]; then echo -en "${success_msg}"
        else                                    echo -en "${failure_msg}"
        fi
        tput rc
    }

    handle_done() {
        local filename=${1}
        index=${filename%%.*}
        code=${filename##*.}
        codes["${index}"]=${code}
        draw_status "${index}" "${code}"
        cp "${filename}" "${log_dir}/${index}. ${names[${index}]} (${code}).log"
        mv "${filename}" "${index}"
        if [[ "${code}" != "0" ]]; then
            final_status=1
        fi
    }

    print_failures() {
        cd "${status_dir}"
        local i
        for (( i = 0; i < commands; i++ )); do
            if [[ "${codes[${i}]}" != '0' ]]; then
                echo
                echo "['${names[${i}]}' failed with exit status ${codes[${i}]}]"
                indent "${i}"
            fi
        done

        if [[ "${final_status}" != "0" ]]; then
            echo
            echo "Logs for all tasks can be found in '${log_dir}/':"
            (cd "${log_dir}" && ls -1d *) | indent
        fi
    }

    names=()        # command names by index
    codes=()        # command exit codes by index
    start=()        # command start status by index
    commands=0      # total number of commands
    final_status=0  # 0 if all commands succeeded, 1 otherwise

    while (( $# )); do
        if [[ "${1}" == '-' ]]; then
            shift; (( $# )) || error "expected task name after '-'"
            names+=("${1}")
            shift; (( $# )) || error "expected command after task name"
            args=()
            while (( $# )) && [[ "${1}" != -* ]]; do
                args+=("${1}")
                shift
            done
            declare -a "command_${commands}=(\"\${args[@]}\")"
            (( commands++ )) || :
        elif [[ "${1}" == "--require" ]]; then
            require=()
            while (( $# )) && [[ "${1}" == "--require" ]]; do
                shift; (( $# )) || error "expected task name after '--require'"
                require=(${require[@]} $(name_index "${1}"))
                shift
            done
            while (( $# )) && [[ "${1}" == "--before" ]]; do
                shift; (( $# )) || error "expected task name after '--before'"
                before=$(name_index "${1}")
                for r in "${require[@]}"; do
                    declare -a "waits_${before}=(\${waits_${before}[@]} ${r})"
                done
                shift
            done
        else
            shift
        fi
    done

    log_dir="${PWD}/.logs/$(date +'%F@%T')"
    mkdir -p "${log_dir}"

    # Disable local echo so the user can't mess up the pretty display.
    stty -echo

    start_all
    wait_for_all
    print_failures

    # Enable local echo so user can type again. (Simply exiting the subshell
    # is not sufficient to reset this, which is surprising.)
    stty echo

    exit ${final_status}
)
