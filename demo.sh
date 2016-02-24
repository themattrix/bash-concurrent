#!/usr/bin/env bash

set -e -o pipefail

# shellcheck source=concurrent.lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/concurrent.lib.sh"

success() {
    local args=(
        - "Creating VM"                                         create_vm    3.0
        - "Creating ramdisk"                                    my_sleep     0.1
        - "Enabling swap"                                       my_sleep     0.1
        - "Populating VM with world data"                       restore_data 5.0
        - "Spigot: Pulling docker image for build"              my_sleep     0.5
        - "Spigot: Building JAR"                                my_sleep     6.0
        - "Pulling remaining docker images"                     my_sleep     2.0
        - "Launching services"                                  my_sleep     0.2

        --require "Creating VM"
        --before  "Creating ramdisk"
        --before  "Enabling swap"

        --require "Creating ramdisk"
        --before  "Populating VM with world data"
        --before  "Spigot: Pulling docker image for build"

        --require "Spigot: Pulling docker image for build"
        --before  "Spigot: Building JAR"
        --before  "Pulling remaining docker images"

        --require "Populating VM with world data"
        --require "Spigot: Building JAR"
        --require "Pulling remaining docker images"
        --before  "Launching services"
    )

    concurrent "${args[@]}"
}

failure() {
    local args=(
        - "Creating VM"                                         create_vm    3.0
        - "Creating ramdisk"                                    my_sleep     0.1
        - "Enabling swap"                                       my_sleep     0.1
        - "Populating VM with world data"                       restore_data 0.0 64
        - "Spigot: Pulling docker image for build"              my_sleep     0.5 128
        - "Spigot: Building JAR"                                my_sleep     6.0
        - "Pulling remaining docker images"                     my_sleep     2.0
        - "Launching services"                                  my_sleep     0.2

        --require "Creating VM"
        --before  "Creating ramdisk"
        --before  "Enabling swap"

        --require "Creating ramdisk"
        --before  "Populating VM with world data"
        --before  "Spigot: Pulling docker image for build"

        --require "Spigot: Pulling docker image for build"
        --before  "Spigot: Building JAR"
        --before  "Pulling remaining docker images"

        --require "Populating VM with world data"
        --require "Spigot: Building JAR"
        --require "Pulling remaining docker images"
        --before  "Launching services"
    )

    concurrent "${args[@]}"
}

nesting_success() {
    local args=(
        - "Task A1"               my_sleep 2.0
        - "Task A2"               concurrent
            -- "Task B1"          concurrent
                --- "Task C1"     my_sleep 1.0
                --- "Task C2"     my_sleep 2.0
            -- "Task B2"          my_sleep 3.0
        - "Task A3"               my_sleep 4.0
    )

    concurrent "${args[@]}"
}

nesting_failure() {
    local args=(
        - "Task A1"               my_sleep 2.0
        - "Task A2"               concurrent
            -- "Task B1"          concurrent
                --- "Task C1"     my_sleep 1.0
                --- "Task C2"     my_sleep 2.0 1
            -- "Task B2"          my_sleep 3.0
        - "Task A3"               my_sleep 4.0
    )

    concurrent "${args[@]}"
}

many() {
    local args=()
    local i

    for (( i = 0; i < 300; i++ )); do
        args+=(- "Task ${i}" my_sleep $(( RANDOM % 5 + 1 )))
    done

    concurrent "${args[@]}"
}

create_vm() {
    local provider=digitalocean
    echo "(on ${provider})" >&3
    my_sleep "${@}"
}

restore_data() {
    local data_source=dropbox
    echo "(with ${data_source})" >&3
    my_sleep "${@}"
}

my_sleep() {
    local seconds=${1}
    local code=${2:-0}
    echo "Yay! Sleeping for ${seconds} second(s)!"
    sleep "${seconds}"
    if [ "${code}" -ne 0 ]; then
        echo "Oh no! Terrible failure!" 1>&2
    fi
    return "${code}"
}

main() {
    if [[ -n "${1}" ]]; then
        "${1}"
    else
        echo
        echo "[SUCCESS EXAMPLE]"
        success
        echo
        echo "[FAILURE EXAMPLE]"
        failure
    fi
}

main "${@}"
