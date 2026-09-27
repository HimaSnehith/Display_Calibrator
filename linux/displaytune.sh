#!/usr/bin/env bash
# DisplayTune Linux Launcher
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
python3 "$DIR/displaytune.py" "$@"
