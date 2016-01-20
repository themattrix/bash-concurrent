# Concurrent ![version: 1.5.0](https://img.shields.io/badge/version-1.5.0-green.svg?style=flat-square) ![language: bash](https://img.shields.io/badge/language-bash-blue.svg?style=flat-square) ![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)

A Bash function to run tasks in parallel and display pretty output as they complete.

[![asciicast](https://asciinema.org/a/33615.png)](https://asciinema.org/a/33615)


## Examples

Run three tasks concurrently:

```bash
concurrent \\
    - 'My long task'   sleep 10 \\
    - 'My medium task' sleep 5  \\
    - 'My short task'  sleep 1
```

Start the medium task *after* the short task succeeds:

```bash
concurrent \\
    - 'My long task'   sleep 10 \\
    - 'My medium task' sleep 5  \\
    - 'My short task'  sleep 1  \\
    --require 'My short task'   \\
    --before  'My medium task'
```

Start the short task after *both* other tasks succeed:

```bash
concurrent \\
    - 'My long task'   sleep 10 \\
    - 'My medium task' sleep 5  \\
    - 'My short task'  sleep 1  \\
    --require 'My long task'    \\
    --require 'My medium task'  \\
    --before  'My short task'
```

Start the medium task *and* the long task after the short task succeeds:

```bash
concurrent \\
    - 'My long task'   sleep 10 \\
    - 'My medium task' sleep 5  \\
    - 'My short task'  sleep 1  \\
    --require 'My short task'   \\
    --before  'My medium task'  \\
    --before  'My long task'
```

If your command has a `-` argument, you can use a different task delimiter:

```bash
concurrent \\
    + 'My long task'   wget -O - ... \\
    + 'My medium task' sleep 5  \\
    + 'My short task'  sleep 1
```

Take a look at [`demo.sh`](demo.sh) for more involved examples.

## Failure Demo

[![asciicast](https://asciinema.org/a/33617.png)](https://asciinema.org/a/33617)


## Interrupted Demo

[![asciicast](https://asciinema.org/a/33618.png)](https://asciinema.org/a/33618)


## Requirements

- bash >= 4.3 (for `wait -n`)
- sed
- tput
- date
- mktemp
- kill
- mv
- cp


## Change Log

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
