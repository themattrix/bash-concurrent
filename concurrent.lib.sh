concurrent() (
    #
    # Help and Usage
    #

    version='concurrent 1.1.6'

    usage="concurrent - Run tasks in parallel and display pretty output as they complete.

        Usage:
          concurrent (- TASK COMMAND [ARGS...])... [(--require TASK)... (--before TASK)...]...
          concurrent -h | --help
          concurrent --version

        Options:
          -h --help                 Show this help.
          --version                 Show version.
          - TASK COMMAND [ARGS...]  Define a task named TASK for running COMMAND with ARGS.
          --require TASK            Require a TASK to complete successfully...
          --before TASK             ...before another TASK.

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
          bash v4, sed, tput, date, mktemp, kill, cp, mv

        Author:
          Matthew Tardiff <mattrix@gmail.com>

        License:
          MIT

        Version:
          ${version}

        URL:
          https://github.com/themattrix/bash-concurrent"

    display_usage_and_exit() {
       sed 's/^        //' <<< "${usage}"
       exit 0
    }

    display_version_and_exit() {
       echo "${version}"
       exit 0
    }

    if [[ -z "${1}" ]] || [[ "${1}" == '-h' ]] || [[ "${1}" == '--help' ]]; then
        display_usage_and_exit
    elif [[ "${1}" == '--version' ]]; then
        display_version_and_exit
    fi

    # No longer need these up in our business.
    unset -f display_usage_and_exit display_version_and_exit
    unset usage version

    #
    # Compatibility Check
    #

    error() {
        echo "ERROR (concurrent): ${1}" 1>&2
        exit 1
    }

    if [[ -z "${BASH_VERSINFO[@]}" ]] || [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        error "Requires Bash version 4 required (you have ${BASH_VERSION:-a different shell})"
    fi

    #
    # Settings
    #

    readonly ORIG_PWD=${PWD}
    readonly ORIG_OLDPWD=${OLDPWD}
    readonly ORIG_BASHOPTS=${BASHOPTS}
    readonly ORIG_SHELLOPTS=${SHELLOPTS}

    set_original_pwd() {
        cd "${ORIG_PWD}"
        export OLDPWD=${ORIG_OLDPWD}
    }

    set_our_shell_options() {
        set -o errexit      # Exit on a failed command...
        set -o pipefail     # ...even if that command is in a pipeline.
        shopt -s nullglob   # Empty glob evaluates to nothing instead of itself
    }

    set_original_shell_options() {
        set_our_shell_options
        [[ "${ORIG_SHELLOPTS}" == *errexit*  ]] || set +o errexit
        [[ "${ORIG_SHELLOPTS}" == *pipefail* ]] || set +o pipefail
        [[ "${ORIG_BASHOPTS}"  == *nullglob* ]] || shopt -u nullglob
    }

    set_our_shell_options

    #
    # Task Management
    #

    is_task_started() {
        [[ "${started[${1}]}" == "true" ]]
    }

    is_task_done() {
        [[ -n "${codes[${1}]}" ]]
    }

    is_task_running() {
        is_task_started "${1}" && ! is_task_done "${1}"
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

    is_task_allowed_to_start() {
        # A task is allowed to start if:
        #   1. it has not already started, and if
        #   2. all prereq tasks have succeeded.
        # If any prereqs have failed or have been skipped, then this task will
        # be skipped.

        local task=${1}
        if is_task_started "${task}"; then
            return 1  # cannot start again
        fi

        local requires
        local prereqs="prereqs_${task}[@]"
        for requires in "${!prereqs}"; do
            if [[ -z "${codes[${requires}]}" ]]; then
                return 1
            elif [[ "${codes[${requires}]}" != "0" ]]; then
                skip_task "${task}" "${names[${requires}]}"
                return 1
            fi
        done

        # All prereqs succeeded! This task can be started.
    }

    mark_task_with_code() {
        local task=${1}
        local code=${2}
        mv -- "${status_dir}/${task}"{,.done.${code}}
    }

    task_runner() (
        task=${1}
        command_args="command_${task}[@]"

        sigint_handler() {
            mark_task_with_code "${task}" int
            trap INT      # reset the signal handler
            kill -INT $$  # re-raise the signal
            exit 255      # do not continue this task
        }

        trap sigint_handler INT

        set +o errexit  # a failure of the command should not exit the task
        (
            set_original_pwd
            set_original_shell_options
            "${!command_args}" &> "${status_dir}/${task}"
        )
        code=$?
        set -o errexit  # but other failures should
        trap INT        # reset the signal handler

        mark_task_with_code "${task}" "${code}"
    )

    start_task() {
        local task=${1}
        task_runner "${task}" &
        pids["${task}"]=$!
        started["${task}"]=true
        draw_status "${task}" running
    }

    start_all_tasks() {
        status_dir=$(mktemp -d "${TMPDIR:-/tmp}/concurrent.lib.sh.XXXXXXXXXXX")
        local i
        for (( i = 0; i < task_count; i++ )); do
            echo "        ${names[${i}]}"
        done
        move_cursor_to_first_task
        start_allowed_tasks
    }

    stop_task() {
        started["${1}"]=true
        echo "[INTERRUPTED]" >> "${status_dir}/${1}"
        kill -INT "${pids[${1}]}"
    }

    stop_all_tasks() {
        local i
        for (( i = 0; i < task_count; i++ )); do
            if is_task_running "${i}"; then
                stop_task "${i}"
            fi
        done
        wait
    }

    skip_task() {
        started["${1}"]=true
        echo "[SKIPPED] Prereq '${2}' failed or was skipped" > "${status_dir}/${1}.done.skip"
    }

    start_allowed_tasks() {
        local i
        for (( i = 0; i < task_count; i++ )); do
            if is_task_allowed_to_start "${i}"; then
                start_task "${i}"
            fi
        done
    }

    has_unseen_done_tasks() {
        compgen -G '*.done.*' > /dev/null
    }

    wait_for_all_tasks() {
        while wait -n; do
            manage_tasks
        done
        status_cleanup
    }

    cleanup_int_tasks() {
        manage_tasks
        status_cleanup
    }

    manage_tasks() {
        cd "${status_dir}"
        local f
        while has_unseen_done_tasks; do
            for f in *.done.*; do
                handle_done_task "${f}"
            done
            start_allowed_tasks
        done
    }

    handle_done_task() {
        local filename=${1}
        index=${filename%%.*}
        code=${filename##*.}
        codes["${index}"]=${code}
        draw_status "${index}" "${code}"
        >> "${filename}"  # ensure file exists
        cp -- "${filename}" "${log_dir}/${index}. ${names[${index}]//\//-} (${code}).log"
        mv -- "${filename}" "${index}"
        if [[ "${code}" != "0" ]]; then
            final_status=1
        fi
    }

    status_cleanup() {
        trap INT  # no longer need special sigint handling
        move_cursor_below_tasks
        print_failures
    }

    #
    # Status Updates
    #

    txtred='\e[0;31m' # Red
    txtgrn='\e[0;32m' # Green
    txtylw='\e[0;33m' # Yellow
    txtblu='\e[0;34m' # Blue
    txtrst='\e[0m'    # Text Reset

    indent() {
        sed 's/^/    /' "${@}"
    }

    move_cursor_to_first_task() {
        tput cuu "${task_count}"
        tput sc
    }

    move_cursor_below_tasks() {
        tput cud "${task_count}"
        tput sc
    }

    draw_status() {
        local index=${1}
        local code=${2}
        tput rc
        [[ "${index}" -eq 0 ]] || tput cud "${index}"
        if   [[ "${code}" == "running" ]]; then echo -en " ${txtblu}    =>${txtrst} "
        elif [[ "${code}" == "int"     ]]; then echo -en " ${txtred}SIGINT${txtrst} "
        elif [[ "${code}" == "skip"    ]]; then echo -en " ${txtylw} SKIP ${txtrst} "
        elif [[ "${code}" == "0"       ]]; then echo -en " ${txtgrn}  OK  ${txtrst} "
        else                                    echo -en " ${txtred}FAILED${txtrst} "
        fi
        tput rc
    }

    print_failures() {
        cd "${status_dir}"
        local i
        for (( i = 0; i < task_count; i++ )); do
            if [[ "${codes[${i}]}" != '0' ]]; then
                echo
                echo "['${names[${i}]}' failed with exit status ${codes[${i}]}]"
                indent "${i}"
            fi
        done

        if [[ "${final_status}" != "0" ]]; then
            printf '\nLogs for all tasks can be found in:\n    %s\n' "${log_dir}/"
        fi
    }

    disable_echo() {
        # Disable local echo so the user can't mess up the pretty display.
        stty -echo &> /dev/null || :
    }

    enable_echo() {
        # Enable local echo so user can type again. (Simply exiting the subshell
        # is not sufficient to reset this, which is surprising.)
        stty echo &> /dev/null || :
    }

    #
    # Argument Parsing
    #

    names=()        # task names by index
    codes=()        # task exit codes (unset, 0-255, 'skip', or 'int') by index
    started=()      # task started status (unset or 'true') by index
    pids=()         # command pids by index
    task_count=0    # total number of tasks
    final_status=0  # 0 if all tasks succeeded, 1 otherwise

    # Arrays of command arguments by task index <T>:
    #   command_<T>=(...)
    #
    # Arrays of prerequisite task indices by task index <T>:
    #   prereqs_<T>=(...)
    #
    # These are dynamically created during argument parsing since bash doesn't
    # have a concept of nested lists.

    while (( $# )); do
        if [[ "${1}" == '-' ]]; then
            shift; (( $# )) || error "expected task name after '-'"
            names+=("${1}")
            shift; (( $# )) || error "expected command after task name"
            args=()
            while (( $# )) && [[ "${1}" != '-' ]] && [[ "${1}" != '--require' ]]; do
                args+=("${1}")
                shift
            done
            declare -a "command_${task_count}=(\"\${args[@]}\")"
            (( task_count++ )) || :
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
                    declare -a "prereqs_${before}=(\${prereqs_${before}[@]} ${r})"
                done
                shift
            done
        else
            error "unexpected argument '${1}'"
        fi
    done

    log_dir="${PWD}/.logs/$(date +'%F@%T')"
    mkdir -p "${log_dir}"

    handle_exit() {
        rm -rf "${status_dir}"
        enable_echo
    }

    handle_sigint() {
        # Clean things up even if there's a bug in this script.
        trap handle_exit EXIT
        stop_all_tasks
        cleanup_int_tasks
        trap INT      # reset the signal
        kill -INT $$  # re-raise the signal
        exit 255      # don't resume the script
    }

    trap handle_exit EXIT
    trap handle_sigint INT

    disable_echo
    start_all_tasks
    wait_for_all_tasks

    exit ${final_status}
)
