#!/bin/sh
# Makes a safe copy of a notebook for testing Perch.
# The copy's "remote" is a local folder, so nothing you do while testing can reach the original.
# Usage: scripts/make-test-vault.sh <git URL or path of the notebook> [target folder, default ~/Perch-Test]
set -eu
SOURCE="${1:?Usage: scripts/make-test-vault.sh <git URL or path of the notebook> [target folder]}"
ROOT="${2:-$HOME/Perch-Test}"

if [ -e "$ROOT" ]; then
  echo "$ROOT already exists. Remove it first to start fresh." >&2
  exit 1
fi
mkdir -p "$ROOT"
git clone -q --bare "$SOURCE" "$ROOT/remote.git"
git -C "$ROOT/remote.git" remote remove origin
git clone -q "$ROOT/remote.git" "$ROOT/vault"
echo "Test notebook: $ROOT/vault"
echo "Its sync target: $ROOT/remote.git (local, not GitHub)"
echo "In Perch, choose Open Notebook and pick the test notebook."
