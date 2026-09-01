#!/bin/sh
set -eu
for test in tests/*.lua; do
  lua5.4 "$test"
done
