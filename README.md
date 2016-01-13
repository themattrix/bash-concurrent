# Concurrent ![version: 1.1.0](https://img.shields.io/badge/version-1.1.0-green.svg?style=flat-square) ![language: bash](https://img.shields.io/badge/language-bash-blue.svg?style=flat-square) ![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)

A Bash function to run tasks in parallel and display pretty output as they complete.

[![asciicast](https://asciinema.org/a/33545.png)](https://asciinema.org/a/33545)


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

Take a look at [`demo.sh`](demo.sh) for more involved examples.


## Requirements

- bash (v4)
- sed
- tput
- date
- ls
- mktemp
- kill
