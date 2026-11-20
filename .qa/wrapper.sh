#!/usr/bin/env bash
set -eu
for arg in "$@"; do case "$arg" in --role=*) export MATCH_ROLE="${arg#--role=}";; esac; done
export LD_PRELOAD="$PWD/.qa/io.so"
exec "$GODOT_REAL" "$@"
