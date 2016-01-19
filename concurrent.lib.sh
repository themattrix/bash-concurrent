concurrent() (
    #
    # Help and Usage
    #

    __crt__help__version='concurrent 1.4.1'

    __crt__help__usage="concurrent - Run tasks in parallel and display pretty output as they complete.

        Usage:
          concurrent \\
              (- TASK COMMAND [ARGS...])... \\
              [--sequential | \\
               [((--require TASK)...|--require-all) \\
                ((--before TASK)...]...|--before-all)]
          concurrent -h | --help
          concurrent --version

        Options:
          -h --help                 Show this help.
          --version                 Show version.
          - TASK COMMAND [ARGS...]  Define a task named TASK for running COMMAND with ARGS.
          --sequential              Each task requires the previous task.
          --require TASK            Require a TASK to complete successfully...
          --before TASK             ...before another TASK.
          --require-all             Shortcut for requiring all tasks.
          --before-all              Given tasks are prerequisites to all others.

        Failed Tasks:
          If a task fails, all dependent tasks (and their dependent tasks, and so on) are
          immediately marked 'SKIP'. The status and output of all failed and skipped tasks
          are displayed at the end. The exit status will be 1.

        Examples:
          # Run three tasks concurrently.
          concurrent \\
              - 'My long task'   sleep 10 \\
              - 'My medium task' sleep 5  \\
              - 'My short task'  sleep 1

          # Start the medium task *after* the short task succeeds.
          concurrent \\
              - 'My long task'   sleep 10 \\
              - 'My medium task' sleep 5  \\
              - 'My short task'  sleep 1  \\
              --require 'My short task'   \\
              --before  'My medium task'

          # Start the short task after *both* other tasks succeed.
              ...
              --require 'My long task'    \\
              --require 'My medium task'  \\
              --before  'My short task'

          # Start the medium task *and* the long task after the short task succeeds.
              ...
              --require 'My short task'   \\
              --before  'My medium task'  \\
              --before  'My long task'

        Requirements:
          bash >= 4.3, sed, tput, date, mktemp, kill, cp, mv

        Author:
          Matthew Tardiff <mattrix@gmail.com>

        License:
          MIT

        Version:
          ${__crt__help__version}

        URL:
          https://github.com/themattrix/bash-concurrent"

    __crt__help__display_usage_and_exit() {
       sed 's/^        //' <<< "${__crt__help__usage}"
       exit 0
    }

    __crt__help__display_version_and_exit() {
       echo "${__crt__help__version}"
       exit 0
    }

    if [[ -z "${1}" ]] || [[ "${1}" == '-h' ]] || [[ "${1}" == '--help' ]]; then
        __crt__help__display_usage_and_exit
    elif [[ "${1}" == '--version' ]]; then
        __crt__help__display_version_and_exit
    fi

    __crt__unset() {
        local sub_namespace=${1}
        [[ -n "${sub_namespace}" ]] &&
            local namespace="__crt__${sub_namespace}__" ||
            local namespace="__crt__"
        unset -f $(compgen -A function "${namespace}")
        unset $(compgen -v "${namespace}")
    }

    __crt__unset 'help'

    #
    # Compatibility Check
    #

    __crt__error() {
        echo "ERROR (concurrent): ${1}" 1>&2
        exit 1
    }

    if [[ -z "${BASH_VERSINFO[@]}" || "${BASH_VERSINFO[0]}" -lt 4 || "${BASH_VERSINFO[1]}" -lt 3 ]]; then
        __crt__error "Requires Bash version 4.3 for 'wait -n' (you have ${BASH_VERSION:-a different shell})"
    fi

    #
    # Settings
    #

    __crt__ORIG_PWD=${PWD}
    __crt__ORIG_OLDPWD=${OLDPWD}
    __crt__ORIG_BASHOPTS=${BASHOPTS}
    __crt__ORIG_SHELLOPTS=${SHELLOPTS}

    __crt__set_original_pwd() {
        cd "${__crt__ORIG_PWD}"
        export OLDPWD=${__crt__ORIG_OLDPWD}
    }

    __crt__set_our_shell_options() {
        set -o errexit      # Exit on a failed command...
        set -o pipefail     # ...even if that command is in a pipeline.
        shopt -s nullglob   # Empty glob evaluates to nothing instead of itself
    }

    __crt__set_original_shell_options() {
        __crt__set_our_shell_options
        [[ "${__crt__ORIG_SHELLOPTS}" == *errexit*  ]] || set +o errexit
        [[ "${__crt__ORIG_SHELLOPTS}" == *pipefail* ]] || set +o pipefail
        [[ "${__crt__ORIG_BASHOPTS}"  == *nullglob* ]] || shopt -u nullglob
    }

    __crt__set_our_shell_options

    #
    # Status Updates
    #

    __crt__txtred='\e[0;31m' # Red
    __crt__txtgrn='\e[0;32m' # Green
    __crt__txtylw='\e[0;33m' # Yellow
    __crt__txtblu='\e[0;34m' # Blue
    __crt__txtrst='\e[0m'    # Text Reset

    __crt__seconds_between_frames=1.0
    __crt__running_status_current_frame=0
    __crt__running_status_frames=(
        " ${__crt__txtblu}    =>${__crt__txtrst} "
        " ${__crt__txtblu}     >${__crt__txtrst} "
    )

    __crt__indent() {
        sed 's/^/    /' "${@}"
    }

    __crt__move_cursor_to_first_task() {
        tput cuu "${__crt__task_count}"
        tput sc
    }

    __crt__move_cursor_below_tasks() {
        tput cud "${__crt__task_count}"
        tput sc
    }

    __crt__draw_running_status() {
        echo -en "${__crt__running_status_frames[${__crt__running_status_current_frame}]}"
    }

    __crt__draw_status() {
        local index=${1}
        local code=${2}
        tput rc
        [[ "${index}" -eq 0 ]] || tput cud "${index}"
        if   [[ "${code}" == "running" ]]; then __crt__draw_running_status
        elif [[ "${code}" == "int"     ]]; then echo -en " ${__crt__txtred}SIGINT${__crt__txtrst} "
        elif [[ "${code}" == "skip"    ]]; then echo -en " ${__crt__txtylw} SKIP ${__crt__txtrst} "
        elif [[ "${code}" == "0"       ]]; then echo -en " ${__crt__txtgrn}  OK  ${__crt__txtrst} "
        else                                    echo -en " ${__crt__txtred}FAILED${__crt__txtrst} "
        fi
        tput rc
    }

    __crt__update_running_status_frames() {
        local i
        for (( i = 0; i < __crt__task_count; i++ )); do
            if __crt__is_task_running "${i}"; then
                __crt__draw_status "${i}" running
            fi
        done
        __crt__running_status_current_frame=$((
            (__crt__running_status_current_frame + 1) % ${#__crt__running_status_frames[@]}
        ))
    }

    __crt__print_failures() {
        cd "${__crt__status_dir}"
        local i
        for (( i = 0; i < __crt__task_count; i++ )); do
            if [[ "${__crt__codes[${i}]}" != '0' ]]; then
                echo
                echo "['${__crt__names[${i}]}' failed with exit status ${__crt__codes[${i}]}]"
                __crt__indent "${i}"
            fi
        done
        if [[ "${__crt__final_status}" != "0" ]]; then
            printf '\nLogs for all tasks can be found in:\n    %s\n' "${__crt__log_dir}/"
        fi
    }

    __crt__disable_echo() {
        # Disable local echo so the user can't mess up the pretty display.
        stty -echo
    }

    __crt__enable_echo() {
        # Enable local echo so user can type again. (Simply exiting the subshell
        # is not sufficient to reset this, which is surprising.)
        stty echo
    }

    __crt__status_cleanup() {
        trap INT  # no longer need special sigint handling
        __crt__move_cursor_below_tasks
        __crt__print_failures
    }

    #
    # Task Management
    #

    __crt__is_task_started() {
        [[ "${__crt__started[${1}]}" == "true" ]]
    }

    __crt__is_task_done() {
        [[ -n "${__crt__codes[${1}]}" ]]
    }

    __crt__are_all_tasks_done() {
        local i
        for (( i = 0; i < __crt__task_count; i++ )); do
            __crt__is_task_done "${i}" || return 1
        done
    }

    __crt__is_task_running() {
        __crt__is_task_started "${1}" && ! __crt__is_task_done "${1}"
    }

    __crt__name_index() {
        local name=${1}
        local i
        for i in "${!__crt__names[@]}"; do
            if [[ "${__crt__names[${i}]}" == "${name}" ]]; then
                printf '%s' "${i}"
                return
            fi
        done
        __crt__error "Failed to find task named '${name}'"
    }

    __crt__is_task_allowed_to_start() {
        # A task is allowed to start if:
        #   1. it has not already started, and if
        #   2. all prereq tasks have succeeded.
        # If any prereqs have failed or have been skipped, then this task will
        # be skipped.

        local task=${1}
        if __crt__is_task_started "${task}"; then
            return 1  # cannot start again
        fi

        local requires
        local prereqs="prereqs_${task}[@]"
        for requires in "${!prereqs}"; do
            if [[ -z "${__crt__codes[${requires}]}" ]]; then
                return 1
            elif [[ "${__crt__codes[${requires}]}" != "0" ]]; then
                __crt__skip_task "${task}" "${__crt__names[${requires}]}"
                return 1
            fi
        done

        # All prereqs succeeded! This task can be started.
    }

    __crt__mark_task_with_code() {
        local task=${1}
        local code=${2}
        mv -- "${__crt__status_dir}/${task}"{,.done.${code}}
    }

    __crt__task_runner() (
        # Do not create real variables for these so that they do not override
        # names from the parent script.
        # $1: task
        # $2: command args array
        # $3: status dir
        set -- "${1}" "command_${1}[@]" "${__crt__status_dir}"

        __crt__sigint_handler() {
            __crt__mark_task_with_code "${1}" int
            trap INT      # reset the signal handler
            kill -INT $$  # re-raise the signal
            exit 255      # do not continue this task
        }

        trap "__crt__sigint_handler ${1}" INT

        set +o errexit  # a failure of the command should not exit the task
        (
            __crt__set_original_pwd
            __crt__set_original_shell_options
            __crt__unset
            "${!2}" &> "${3}/${1}"
        )
        code=$?
        set -o errexit  # but other failures should
        trap INT        # reset the signal handler

        __crt__mark_task_with_code "${1}" "${code}"
    )

    __crt__start_task() {
        __crt__task_runner "${1}" &
        __crt__pids["${1}"]=$!
        __crt__started["${1}"]=true
        __crt__draw_status "${1}" running
    }

    __crt__draw_initial_tasks() {
        local i
        for (( i = 0; i < __crt__task_count; i++ )); do
            echo "        ${__crt__names[${i}]}"
        done
    }

    __crt__start_all_tasks() {
        __crt__draw_initial_tasks
        __crt__move_cursor_to_first_task
        __crt__start_allowed_tasks
    }

    __crt__stop_task() {
        __crt__started["${1}"]=true
        echo "[INTERRUPTED]" >> "${__crt__status_dir}/${1}"
        kill -INT "${__crt__pids[${1}]}"
    }

    __crt__stop_all_tasks() {
        local i
        for (( i = 0; i < __crt__task_count; i++ )); do
            if __crt__is_task_running "${i}"; then
                __crt__stop_task "${i}"
            fi
        done
        wait
    }

    __crt__skip_task() {
        __crt__started["${1}"]=true
        echo "[SKIPPED] Prereq '${2}' failed or was skipped" > "${__crt__status_dir}/${1}.done.skip"
    }

    __crt__start_allowed_tasks() {
        local __crt__i
        for (( __crt__i = 0; __crt__i < __crt__task_count; __crt__i++ )); do
            if __crt__is_task_allowed_to_start "${__crt__i}"; then
                __crt__start_task "${__crt__i}"
            fi
        done
    }

    __crt__has_unseen_done_tasks() {
        cd "${__crt__status_dir}"
        compgen -G '*.done.*' > /dev/null
    }

    __crt__wait_for_all_tasks() {
        __crt__start_animation_frame
        while wait -n; do
            __crt__manage_tasks
            __crt__manage_animation
        done
        __crt__status_cleanup
    }

    __crt__manage_tasks() {
        cd "${__crt__status_dir}"
        local __crt__f
        while __crt__has_unseen_done_tasks; do
            for __crt__f in *.done.*; do
                __crt__handle_done_task "${__crt__f}"
            done
            __crt__start_allowed_tasks
        done
    }

    __crt__handle_done_task() {
        local filename=${1}
        local index=${filename%%.*}
        local code=${filename##*.}
        __crt__codes["${index}"]=${code}
        __crt__draw_status "${index}" "${code}"
        >> "${filename}"  # ensure file exists
        cp -- "${filename}" "${__crt__log_dir}/${index}. ${__crt__names[${index}]//\//-} (${code}).log"
        mv -- "${filename}" "${index}"
        if [[ "${code}" != "0" ]]; then
            __crt__final_status=1
        fi
    }

    __crt__manage_animation() {
        if __crt__is_animation_frame_done && ! __crt__are_all_tasks_done; then
            __crt__start_animation_frame
        fi
    }

    __crt__start_animation_frame() {
        __crt__update_running_status_frames
        {
            sleep "${__crt__seconds_between_frames}"
            > "${__crt__status_dir}/anim"
        } &
    }

    __crt__is_animation_frame_done() {
        rm -- "${__crt__status_dir}/anim" &> /dev/null
    }

    #
    # Argument Parsing
    #

    __crt__names=()        # task names by index
    __crt__codes=()        # task exit codes (unset, 0-255, 'skip', or 'int') by index
    __crt__started=()      # task started status (unset or 'true') by index
    __crt__pids=()         # command pids by index
    __crt__task_count=0    # total number of tasks
    __crt__final_status=0  # 0 if all tasks succeeded, 1 otherwise

    # Arrays of command arguments by task index <T>:
    #   command_<T>=(...)
    #
    # Arrays of prerequisite task indices by task index <T>:
    #   prereqs_<T>=(...)
    #
    # These are dynamically created during argument parsing since bash doesn't
    # have a concept of nested lists.

    __crt__args__is_task_flag()        { [[ "${1}" == "-"             ]]; }
    __crt__args__is_require_flag()     { [[ "${1}" == "--require"     ]]; }
    __crt__args__is_require_all_flag() { [[ "${1}" == "--require-all" ]]; }
    __crt__args__is_before_flag()      { [[ "${1}" == "--before"      ]]; }
    __crt__args__is_before_all_flag()  { [[ "${1}" == "--before-all"  ]]; }
    __crt__args__is_sequential_flag()  { [[ "${1}" == "--sequential"  ]]; }

    __crt__args__is_flag_starting_section() {
        __crt__args__is_task_flag "${1}" ||
        __crt__args__is_require_flag "${1}" ||
        __crt__args__is_require_all_flag "${1}" ||
        __crt__args__is_sequential_flag "${1}"
    }

    __crt__args__is_item_in_array() {
        local item_to_find=${1}
        local array_name="${2}[@]"
        local i
        for i in "${!array_name}"; do
            if [[ "${i}" == ${item_to_find} ]]; then return 0; fi
        done
        return 1
    }

    __crt__args__get_tasks_not_in() {
        local these_tasks=${1}
        local other_tasks=()
        local i

        for (( i = 0; i < __crt__task_count; i++ )); do
            __crt__args__is_item_in_array "${i}" "${these_tasks}" || other_tasks=(${other_tasks[@]} ${i})
        done

        __crt__args__fn_result=("${other_tasks[@]}")
    }

    __crt__args__assign_sequential_prereqs() {
        local i
        for (( i = 1; i < __crt__task_count; i++ )); do
            declare -g -a "prereqs_${i}=($(( i - 1 )))"
        done
    }

    __crt__args__handle_task_flag() {
        set -- "${remaining_args[@]}"

        shift; (( $# )) || __crt__error "expected task name after '-'"
        __crt__names+=("${1}")
        shift; (( $# )) || __crt__error "expected command after task name"
        local args=()
        while (( $# )) && ! __crt__args__is_flag_starting_section "${1}"; do
            args+=("${1}")
            shift
        done
        declare -g -a "command_${__crt__task_count}=(\"\${args[@]}\")"
        (( __crt__task_count++ )) || :

        remaining_args=("${@}")
    }

    __crt__args__handle_sequential_flag() {
        set -- "${remaining_args[@]}"
        shift
        __crt__args__assign_sequential_prereqs
        remaining_args=("${@}")
    }

    __crt__args__handle_require_flag() {
        set -- "${remaining_args[@]}"

        local require
        local before

        while (( $# )) && __crt__args__is_require_flag "${1}"; do
            shift; (( $# )) || __crt__error "expected task name after '--require'"
            require=(${require[@]} $(__crt__name_index "${1}"))
            shift
        done

        if __crt__args__is_before_all_flag "${1}"; then
            shift
            __crt__args__get_tasks_not_in 'require'; before=("${__crt__args__fn_result[@]}")
            local b
            for b in "${before[@]}"; do
                declare -g -a "prereqs_${b}=(\${require[@]})"
            done
        elif __crt__args__is_before_flag "${1}"; then
            while (( $# )) && __crt__args__is_before_flag "${1}"; do
                shift; (( $# )) || __crt__error "expected task name after '--before'"
                before=$(__crt__name_index "${1}")
                shift
                declare -g -a "prereqs_${before}=(\${prereqs_${before}[@]} \${require[@]})"
            done
        else
            __crt__error "expected '--before' or '--before-all' after '--require-all'"
        fi

        remaining_args=("${@}")
    }

    __crt__args__handle_require_all_flag() {
        set -- "${remaining_args[@]}"

        local require
        local before

        shift
        if __crt__args__is_before_all_flag "${1}"; then
            shift
            __crt__args__assign_sequential_prereqs  # --require-all --before-all is the same as --sequential
        elif __crt__args__is_before_flag "${1}"; then
            before=()
            while (( $# )) && __crt__args__is_before_flag "${1}"; do
                shift; (( $# )) || __crt__error "expected task name after '--before'"
                before=(${before[@]} $(__crt__name_index "${1}"))
                shift
            done
            __crt__args__get_tasks_not_in 'before'; require=("${__crt__args__fn_result[@]}")
            local b
            for b in "${before[@]}"; do
                declare -g -a "prereqs_${b}=(\${require[@]})"
            done
        else
            __crt__error "expected '--before' or '--before-all' after '--require-all'"
        fi

        remaining_args=("${@}")
    }

    __crt__args__parse() {
        local remaining_args=("${@}")

        while (( ${#remaining_args} )); do
            if __crt__args__is_task_flag "${remaining_args[0]}"; then
                __crt__args__handle_task_flag
            elif __crt__args__is_require_flag "${remaining_args[0]}"; then
                __crt__args__handle_require_flag
            elif __crt__args__is_require_all_flag "${remaining_args[0]}"; then
                __crt__args__handle_require_all_flag
            elif __crt__args__is_sequential_flag "${remaining_args[0]}"; then
                __crt__args__handle_sequential_flag
            else
                __crt__error "unexpected argument '${remaining_args[0]}'"
            fi
        done

        __crt__unset 'args'
    }

    __crt__args__parse "${@}"

    #
    # Logging
    #

    __crt__log_dir="${PWD}/.logs/$(date +'%F@%T')"
    mkdir -p "${__crt__log_dir}"

    #
    # Signal Handling/General Cleanup
    #

    __crt__handle_exit() {
        rm -rf "${__crt__status_dir}"
        __crt__enable_echo
    }

    __crt__handle_sigint() {
        # Clean things up even if there's a bug in this script.
        trap __crt__handle_exit EXIT
        __crt__stop_all_tasks
        __crt__manage_tasks
        __crt__status_cleanup
        trap INT      # reset the signal
        kill -INT $$  # re-raise the signal
        exit 255      # don't resume the script
    }

    __crt__disable_echo || __crt__error 'Must be run in the foreground of an interactive shell!'
    __crt__status_dir=$(mktemp -d "${TMPDIR:-/tmp}/concurrent.lib.sh.XXXXXXXXXXX")

    trap __crt__handle_exit EXIT
    trap __crt__handle_sigint INT

    __crt__start_all_tasks
    __crt__wait_for_all_tasks

    exit ${__crt__final_status}
)
