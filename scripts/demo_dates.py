#!/usr/bin/env python3
"""Makes a dated copy of the demo notebook in Demo/notebook.

The notebook in the repository is written as if today were ANCHOR. A copy made on another day has every
date moved by the same number of days, in file names and in file contents, so that what was due "today"
is due on the day the copy is made, what was overdue is still overdue by the same amount, and links
between notes still match their file names. Each file's modification time is set from Demo/edited.tsv
(notes) or from the task's own dates (tasks), moved the same way, so folders sort and show "edited" times
the way a lived-in notebook would.

The notebook owner's own tasks and comments are written as `owner: me` and `@me:`, the owner of a build with
nothing configured (PERCH_OWNER_ID in Config/Perch.xcconfig). A copy for a build with another owner takes
that name instead (--owner), so the app shows them as the user's own there too.

Standard library only. Used by scripts/demo-notebook.sh and scripts/site-media.sh.
"""
import argparse
import datetime as dt
import hashlib
import os
import re
import shutil
import sys
import time

ANCHOR = dt.date(2026, 11, 12)
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(REPO, "Demo", "notebook")
EDITED = os.path.join(REPO, "Demo", "edited.tsv")
DATE = re.compile(r"(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)")
# The owner the notebook is written for, and what an owner can be called: one word, as in a task's owner:.
OWNER = "me"
OWNER_NAME = re.compile(r"^[A-Za-z0-9._-]+$")


def shift_text(text, days):
    """Every YYYY-MM-DD in `text`, `days` later. Anything that isn't a real date is left alone."""
    def move(match):
        try:
            day = dt.date(int(match.group(1)), int(match.group(2)), int(match.group(3)))
        except ValueError:
            return match.group(0)
        return (day + dt.timedelta(days=days)).isoformat()
    return DATE.sub(move, text)


def set_owner(text, owner):
    """The notebook owner's `owner: me` and `@me:` comments in a task file, as `owner`."""
    if owner == OWNER or not text.startswith("---\n"):
        return text
    end = text.find("\n---\n", 4)
    if end < 0:
        return text
    front, body = text[:end + 1], text[end + 1:]
    front = re.sub(rf"^owner: {re.escape(OWNER)}$", f"owner: {owner}", front, flags=re.M)
    body = re.sub(rf"^(- \d{{4}}-\d{{2}}-\d{{2}}\S* )@{re.escape(OWNER)}:", rf"\g<1>@{owner}:", body, flags=re.M)
    return front + body


def read_edited():
    """Demo/edited.tsv: path, days before the anchor, time of day. Paths are as written in the repository."""
    table = {}
    if not os.path.exists(EDITED):
        return table
    with open(EDITED, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            path, offset, clock = line.split("\t")
            table[path] = (int(offset), clock)
    return table


def task_offset(text):
    """A task file was last touched on the latest of its created, completed and activity dates."""
    found = []
    for key in ("created", "completed"):
        match = re.search(rf"^{key}: (\d{{4}}-\d{{2}}-\d{{2}})", text, re.M)
        if match:
            found.append(match.group(1))
    found += re.findall(r"^- (\d{4}-\d{2}-\d{2}) @", text, re.M)
    days = [(dt.date.fromisoformat(d) - ANCHOR).days for d in found]
    days = [d for d in days if d <= 0]
    return max(days) if days else -14


def default_clock(path):
    """A steady, made-up time of day for a file the table doesn't list, between 08:00 and 19:00."""
    minutes = 8 * 60 + int(hashlib.sha1(path.encode()).hexdigest(), 16) % (11 * 60)
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def copy(target, today, owner=OWNER):
    days = (today - ANCHOR).days
    if not OWNER_NAME.match(owner):
        sys.exit(f"An owner is one word of letters, digits, '.', '_' and '-', as in a task's owner: line. Not: {owner!r}")
    if os.path.exists(target) and os.listdir(target):
        sys.exit(f"{target} is not empty. Give a new or empty folder.")
    edited = read_edited()
    now = time.time()
    written = 0
    for folder, _, names in os.walk(SOURCE):
        for name in names:
            if name in (".DS_Store",):
                continue
            source = os.path.join(folder, name)
            relative = os.path.relpath(source, SOURCE)
            moved = shift_text(relative, days)
            destination = os.path.join(target, moved)
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            if name.endswith((".md", ".excalidraw", ".svg", ".json", ".txt")):
                with open(source, encoding="utf-8") as f:
                    text = f.read()
                if "/Tasks/" in "/" + relative and name.endswith(".md"):
                    text = set_owner(text, owner)
                with open(destination, "w", encoding="utf-8") as f:
                    f.write(shift_text(text, days))
            else:
                shutil.copyfile(source, destination)
                text = ""
            if relative in edited:
                offset, clock = edited[relative]
            elif "/Tasks/" in "/" + relative:
                offset, clock = task_offset(text), default_clock(relative)
            else:
                offset, clock = -14, default_clock(relative)
            hour, minute = (int(part) for part in clock.split(":"))
            stamp = dt.datetime.combine(today + dt.timedelta(days=offset), dt.time(hour, minute)).timestamp()
            stamp = min(stamp, now - 60)
            os.utime(destination, (stamp, stamp))
            written += 1
    return written, days


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("target", help="a new or empty folder for the copy")
    parser.add_argument("--date", help="the day the copy is for, YYYY-MM-DD (default: today)")
    parser.add_argument("--owner", default=OWNER,
                        help=f"the owner of the build you will open it in, its PERCH_OWNER_ID (default: {OWNER})")
    arguments = parser.parse_args()
    today = dt.date.fromisoformat(arguments.date) if arguments.date else dt.date.today()
    written, days = copy(os.path.abspath(arguments.target), today, arguments.owner)
    print(f"Wrote {written} files to {arguments.target}, dates moved by {days:+d} days (anchor {ANCHOR}, today {today}).")


if __name__ == "__main__":
    main()
