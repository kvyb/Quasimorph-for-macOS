#!/bin/sh
set -eu

failed=0

forbidden=$(find . -type f -not -path './.git/*' \( \
  -iname 'Quasimorph.exe' -o \
  -iname 'UnityPlayer.dll' -o \
  -iname 'steam_api.dll' -o \
  -iname 'steam_api64.dll' -o \
  -iname 'globalgamemanagers' \
\) -print)
if [ -n "$forbidden" ]; then
  echo "Forbidden game files:" >&2
  echo "$forbidden" >&2
  failed=1
fi

large=$(find . -type f -not -path './.git/*' -size +25M -print)
if [ -n "$large" ]; then
  echo "Unexpected files larger than 25 MB:" >&2
  echo "$large" >&2
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi
