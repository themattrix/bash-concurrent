#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/concurrent.lib.sh"

success() {
    echo "[SUCCESS EXAMPLE]"

    local provider=digitalocean
    local data_source=dropbox

    local args=(
        - "Creating VM on ${provider}"                          my_sleep 1.0
        - "Creating ramdisk"                                    my_sleep 0.1
        - "Enabling swap"                                       my_sleep 0.1
        - "Populating VM with world data from ${data_source}"   my_sleep 5.0
        - "Spigot: Pulling docker image for build"              my_sleep 0.5
        - "Spigot: Building JAR"                                my_sleep 6.0
        - "Pulling remaining docker images"                     my_sleep 2.0
        - "Launching services"                                  my_sleep 0.2

        --require "Creating VM on ${provider}"
        --before  "Creating ramdisk"
        --before  "Enabling swap"

        --require "Creating ramdisk"
        --before  "Populating VM with world data from ${data_source}"
        --before  "Spigot: Pulling docker image for build"

        --require "Spigot: Pulling docker image for build"
        --before  "Spigot: Building JAR"
        --before  "Pulling remaining docker images"

        --require "Populating VM with world data from ${data_source}"
        --before  "Launching services"

        --require "Spigot: Building JAR"
        --before  "Launching services"

        --require "Pulling remaining docker images"
        --before  "Launching services"
    )

    concurrent "${args[@]}"
}

failure() {
    echo "[FAILURE EXAMPLE]"

    local provider=digitalocean
    local data_source=dropbox

    local args=(
        - "Creating VM on ${provider}"                          my_sleep 1.0
        - "Creating ramdisk"                                    my_sleep 0.1
        - "Enabling swap"                                       my_sleep 0.1
        - "Populating VM with world data from ${data_source}"   my_sleep 0.0 64
        - "Spigot: Pulling docker image for build"              my_sleep 0.5 128
        - "Spigot: Building JAR"                                my_sleep 6.0
        - "Pulling remaining docker images"                     my_sleep 2.0
        - "Launching services"                                  my_sleep 0.2

        --require "Creating VM on ${provider}"
        --before  "Creating ramdisk"
        --before  "Enabling swap"

        --require "Creating ramdisk"
        --before  "Populating VM with world data from ${data_source}"
        --before  "Spigot: Pulling docker image for build"

        --require "Spigot: Pulling docker image for build"
        --before  "Spigot: Building JAR"
        --before  "Pulling remaining docker images"

        --require "Populating VM with world data from ${data_source}"
        --before  "Launching services"

        --require "Spigot: Building JAR"
        --before  "Launching services"

        --require "Pulling remaining docker images"
        --before  "Launching services"
    )

    concurrent "${args[@]}"
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
    echo
    success
    echo
    failure
}

main
