# Concurrent ![version: 2.3.2](https://img.shields.io/badge/version-2.3.2-green.svg?style=flat-square) ![language: bash](https://img.shields.io/badge/language-bash-blue.svg?style=flat-square) ![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square) [![Travis](https://img.shields.io/travis/themattrix/bash-concurrent.svg?style=flat-square)](https://travis-ci.org/themattrix/bash-concurrent)

A Bash function to run tasks in parallel and display pretty output as they complete.

[![asciicast](https://asciinema.org/a/34219.png)](https://asciinema.org/a/34219)


## Examples

Run three tasks concurrently:

```bash
concurrent \
    - 'My long task'   sleep 10 \
    - 'My medium task' sleep 5  \
    - 'My short task'  sleep 1
```

Run three tasks sequentially:

```bash
concurrent \
    - 'My long task'   sleep 10 \
    - 'My medium task' sleep 5  \
    - 'My short task'  sleep 1  \
    --sequential
```

Start the medium task *after* the short task succeeds:

```bash
concurrent \
    - 'My long task'   sleep 10 \
    - 'My medium task' sleep 5  \
    - 'My short task'  sleep 1  \
    --require 'My short task'   \
    --before  'My medium task'
```

Start the short task after *both* other tasks succeed:

```bash
concurrent \
    - 'My long task'   sleep 10 \
    - 'My medium task' sleep 5  \
    - 'My short task'  sleep 1  \
    --require 'My long task'    \
    --require 'My medium task'  \
    --before  'My short task'
```

Same as above, but shorter:

```bash
concurrent \
    - 'My long task'   sleep 10 \
    - 'My medium task' sleep 5  \
    - 'My short task'  sleep 1  \
    --require-all --before 'My short task'
```

Start the medium task *and* the long task after the short task succeeds:

```bash
concurrent \
    - 'My long task'   sleep 10 \
    - 'My medium task' sleep 5  \
    - 'My short task'  sleep 1  \
    --require 'My short task'   \
    --before  'My medium task'  \
    --before  'My long task'
```

Same as above, but shorter:

```bash
concurrent \
    - 'My long task'   sleep 10 \
    - 'My medium task' sleep 5  \
    - 'My short task'  sleep 1  \
    --require 'My short task' --before-all
```

Run the first two tasks concurrently,
*and then* the second two tasks concurrently,
*and then* the final three tasks concurrently.

```bash
concurrent \
    - 'Task 1'  sleep 3 \
    - 'Task 2'  sleep 3 \
    --and-then \
    - 'Task 3'  sleep 3 \
    - 'Task 4'  sleep 3 \
    --and-then \
    - 'Task 5'  sleep 3 \
    - 'Task 6'  sleep 3 \
    - 'Task 7'  sleep 3
```

If your command has a `-` argument, you can use a different task delimiter:

```bash
concurrent \
    + 'My long task'   wget -O - ... \
    + 'My medium task' sleep 5  \
    + 'My short task'  sleep 1
```

You can display extra information at the end of each task's status line by
echoing to `fd 3`.

```bash
my_task() {
    ...
    echo "(extra info)" >&3
    ...
}
```

Take a look at [`demo.sh`](demo.sh) for more involved examples.


## Dry Run

If you have a lot of dependencies between tasks, it's generally a good idea to
perform a dry-run to ensure that the tasks are ordered as expected. Set the
`CONCURRENT_DRY_RUN` environment variable to perform a dry-run.


## Forking Limit

By default, `concurrent` allows up to 50 concurrently-running tasks.
Set the `CONCURRENT_LIMIT` environment variable to override this limit.

A neat trick is to set the limit to 1, essentially forcing a `--sequential`
run, but with existing tasks between dependencies taken into account.

A limit less than 1 is treated as no limit.


## Compact Display

If the number of tasks exceed the terminal height, the "compact display" will
be activated. It can also be explicitly activated by setting the
`CONCURRENT_COMPACT` environment variable to anything other than `0`.

In this mode, each task is represented by a single character instead of an
entire line. An execution summary is displayed below the tasks.

[![asciicast](https://asciinema.org/a/37290.png)](https://asciinema.org/a/37290)


## Logging

By default, logs for each task will be created in `./logs/<timestamp>/`.
For example:

    $ ls .logs/2016-02-02@00:09:07
    0. Creating VM (0).log
    1. Creating ramdisk (0).log
    2. Enabling swap (0).log
    3. Populating VM with world data (1).log
    4. Spigot: Pulling docker image for build (1).log
    5. Spigot: Building JAR (skip).log
    6. Pulling remaining docker images (skip).log
    7. Launching services (skip).log


To change this directory, set `CONCURRENT_LOG_DIR` before calling `concurrent`.


## Failure Demo

[![asciicast](https://asciinema.org/a/34217.png)](https://asciinema.org/a/34217)


## Interrupted Demo

[![asciicast](https://asciinema.org/a/34218.png)](https://asciinema.org/a/34218)


## Requirements

- bash >= 4.2 (for `declare -g`)
- cat
- cp
- date
- mkdir
- mkfifo
- mktemp
- mv
- sed
- tail
- tput


## Change Log

- **2.3.2**
  - *Fix:* Failing tasks with no output now exit with the correct status (credit: @uluyol).
- **2.3.1**
  - *Fix:* Now clearing to end of line when printing extra status info after a task (credit: @fragmede).
- **2.3.0**
  - *New:* Concurrency limit defaults to 50, unless overridden by `CONCURRENT_LIMIT`.
  - *New:* If the number of tasks exceed the terminal height (or `CONCURRENT_COMPACT` is set), each task will be displayed as a single character instead of a taking up an entire line.
  - *New:* Cursor now hidden while running.
  - *Fix:* Greatly improved speed of event loop. Especially noticeable for large numbers of tasks.
  - *Fix:* Namespaced `command_*` and `prereq_*` arrays so that they don't carry into the tasks.
- **2.2.1**
  - *Fix:* Tasks not allowed to read from stdin.
- **2.2.0**
  - *New:* Instances of concurrent can be nested without breaking.
  - *New:* Set custom log dir with `CONCURRENT_LOG_DIR`.
  - *Fix:* Works under Cygwin (special thanks to @FredDeschenes).
  - *Fix:* No longer requires GNU sed (gsed) on OS X.
  - *Fix:* Animation now uses a single process.
  - *Fix:* Extra status info is now merely bold instead of bold/white, which should be more visible on light terminal backgrounds.
- **2.1.0**
  - *New:* New `--and-then` flag for dividing tasks into groups. All tasks in a group run concurrently, but all must complete before the next group may start (inspiration: [fooshards on Reddit](https://www.reddit.com/r/programming/comments/42n64o/concurrent_bash_function_to_run_tasks_in_parallel/czbxnrh)).
  - *Fix:* Removed extra backslashes in README (credit: [bloody-albatross on Reddit](https://www.reddit.com/r/programming/comments/42n64o/concurrent_bash_function_to_run_tasks_in_parallel/czbrtjg))
- **2.0.1**
  - *Fix:* `kill` is a bash builtin (credit: @ScoreUnder)
  - *Fix:* Require GNU sed on OS X (credit: @kumon)
  - *Fix:* Static analysis with shellcheck on push via Travis CI (credit: @xzovy)
  - *Fix:* Cleaner signal handling.
  - *Fix:* Simplified event loop.
- **2.0.0**
  - *New:* Tasks can now display status updates by echoing to fd 3.
- **1.6.0**
  - *New:* `CONCURRENT_DRY_RUN` environment variable runs `sleep 3` instead of actual commands (and prints message).
- **1.5.2**
  - *Fix:* Requirement loops disallowed.
- **1.5.1**
  - *Fix:* Task is not allowed to require itself directly.
- **1.5.0**
  - *New:* First argument is now the task delimiter.
- **1.4.1**
  - *Fix:* Namespaced previously-missed function.
- **1.4.0**
  - *New:* New `--require-all` and `--before-all` flags.
  - *Fix:* Namespaced all concurrent-related functions and variables.
  - *Fix:* Unsetting all concurrent-related functions and variables in the task's context.
  - *Fix:* Enforcing foreground in an interactive shell.
- **1.3.0**
  - *New:* New `--sequential` flag, for when each task requires the previous.
- **1.2.0**
  - *New:* Running tasks have an animated cursor.
  - *Fix:* Enforcing bash version 4.3.
  - *Fix:* Echo is re-enabled even if an internal error occurs.
- **1.1.6**
  - *Fix:* Enforcing bash version 4.
- **1.1.5**
  - *Fix:* Tasks now use original `$PWD` and `$OLDPWD`.
- **1.1.4**
  - *Fix:* Tasks now use original `$SHELLOPTS` and `$BASHOPTS`.
- **1.1.3**
  - *Fix:* Sanitizing forward slashes from log names.
- **1.1.2**
  - *Fix:* Ensuring task status file exists even if an internal error occurs.
- **1.1.1**
  - *Fix:* Task command may now have arguments starting with `-`.
- **1.1.0**
  - *New:* Gracefully handling SIGINT.
  - *Fix:* Works on OS X too.
- **1.0.0**
  - Initial working release.
