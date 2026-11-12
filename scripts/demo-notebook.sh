#!/bin/sh
# Writes a ready-to-open copy of the demo notebook (Demo/notebook) with every date moved to today,
# so what is due today, overdue or later is true on the day you run it.
#
#   scripts/demo-notebook.sh <new-folder> [--date YYYY-MM-DD] [--owner <id>]
#
# The copy is plain files with no Git history. In a build with no GitHub App (the default), open it with
# Open a notebook folder; it opens without sync. A build with a GitHub App wants Use a Git repo on this
# Mac, so run `git init` in the copy first. The notebook owner's tasks are `owner: me`, the owner of a
# build with nothing configured; for a build with another PERCH_OWNER_ID, pass it as --owner.
set -eu
if [ $# -lt 1 ]; then
  echo "Usage: scripts/demo-notebook.sh <new-folder> [--date YYYY-MM-DD] [--owner <id>]" >&2
  exit 2
fi
exec /usr/bin/env python3 "$(dirname "$0")/demo_dates.py" "$@"
