#!/usr/bin/env sh

cd /app || exit
python3 ./runner.py "$@"
