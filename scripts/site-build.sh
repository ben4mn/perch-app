#!/usr/bin/env bash
# Builds the Perch website into a folder ready to publish, for example with GitHub Pages.
#
#   scripts/site-build.sh <out-dir> --owner OWNER --repo REPO [--license "MIT"]
#
# It copies site/ into <out-dir>: the page, its stylesheet, script and assets, and from
# site/media the mp4 clips, their posters, the manifest and the gif files the README uses
# (not the webm files). In the HTML it replaces the placeholders OWNER, REPO and
# LICENSE_NAME, and it writes a .nojekyll file. Without --license it reads the license name
# from the LICENSE file at the top of the repository.
#
# It never runs git and never uses the network. It adds and replaces files in <out-dir> but
# deletes nothing there, so build into an empty folder to publish exactly this site.
set -euo pipefail

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  echo "site-build: $*" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SITE="$ROOT/site"

out=""
owner=""
repo=""
license=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --owner) [ $# -ge 2 ] || die "--owner needs a value"; owner="$2"; shift 2 ;;
    --owner=*) owner="${1#*=}"; shift ;;
    --repo) [ $# -ge 2 ] || die "--repo needs a value"; repo="$2"; shift 2 ;;
    --repo=*) repo="${1#*=}"; shift ;;
    --license) [ $# -ge 2 ] || die "--license needs a value"; license="$2"; shift 2 ;;
    --license=*) license="${1#*=}"; shift ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [ -z "$out" ] || die "only one output folder, please"; out="$1"; shift ;;
  esac
done

[ -n "$out" ] || { usage >&2; exit 2; }
[ -n "$owner" ] || die "--owner is required"
[ -n "$repo" ] || die "--repo is required"

# GitHub's rules: an owner is letters, digits and single hyphens; a repository name is
# letters, digits, '.', '-' and '_'. Checking them also keeps them safe to put in the HTML.
owner_re='^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'
repo_re='^[A-Za-z0-9._-]{1,100}$'
license_re='^[A-Za-z0-9 .+()-]{1,40}$'
[[ "$owner" =~ $owner_re ]] && [[ "$owner" != *--* ]] \
  || die "\"$owner\" is not a GitHub owner name"
[[ "$repo" =~ $repo_re ]] && [ "$repo" != "." ] && [ "$repo" != ".." ] \
  || die "\"$repo\" is not a GitHub repository name"

if [ -z "$license" ]; then
  for name in LICENSE LICENSE.md LICENSE.txt COPYING; do
    file="$ROOT/$name"
    [ -f "$file" ] || continue
    text="$(head -c 4000 "$file")"
    case "$text" in
      *"MIT License"*|*"Permission is hereby granted, free of charge"*) license="MIT" ;;
      *"Apache License"*"Version 2.0"*) license="Apache 2.0" ;;
      *"GNU AFFERO GENERAL PUBLIC LICENSE"*"Version 3"*) license="AGPL-3.0" ;;
      *"GNU GENERAL PUBLIC LICENSE"*"Version 3"*) license="GPL-3.0" ;;
      *"GNU GENERAL PUBLIC LICENSE"*"Version 2"*) license="GPL-2.0" ;;
      *"Mozilla Public License"*"2.0"*) license="MPL 2.0" ;;
      *"ISC License"*) license="ISC" ;;
      *"Redistribution and use"*"Neither the name"*) license="BSD 3-Clause" ;;
      *"Redistribution and use"*) license="BSD 2-Clause" ;;
      *"free and unencumbered software released into the public domain"*) license="Unlicense" ;;
    esac
    [ -n "$license" ] && break
    die "could not tell the license from $name; pass --license \"NAME\""
  done
  [ -n "$license" ] || die "there is no LICENSE file at the top of the repository; pass --license \"NAME\""
fi
[[ "$license" =~ $license_re ]] || die "\"$license\" does not look like a license name"

command -v python3 >/dev/null 2>&1 || die "python3 is needed to fill in the placeholders"
[ -f "$SITE/index.html" ] || die "no site/index.html in $ROOT"
compgen -G "$SITE/media/*.mp4" >/dev/null || die "no clips in site/media; make them first with scripts/site-media.sh"
[ -f "$SITE/media/manifest.json" ] || die "no site/media/manifest.json; make the clips first with scripts/site-media.sh"

# Where <out-dir> really is, before anything is made there: the nearest folder that exists,
# with symbolic links resolved, plus the part still to be made.
resolve() {
  local path="$1" rest=""
  case "$path" in /*) ;; *) path="$PWD/$path" ;; esac
  while [ ! -d "$path" ]; do
    rest="/$(basename "$path")$rest"
    path="$(dirname "$path")"
  done
  case "$rest" in */..|*/../*|*/.|*/./*) die "give <out-dir> without . or .. in the part that does not exist yet" ;; esac
  printf '%s%s\n' "$(cd "$path" && pwd -P)" "$rest"
}

out="$(resolve "$out")"
case "$out" in
  "$ROOT"|"$SITE"|"$SITE"/*) die "build outside the site folder and outside the repository's top level" ;;
  /|"$HOME") die "refusing to build into $out" ;;
esac
mkdir -p "$out"
if [ -n "$(ls -A "$out")" ]; then
  echo "site-build: note: $out is not empty; files not part of the site are left as they are"
fi

# The page and everything beside it, except the media folder and hidden files.
count=0
while IFS= read -r rel; do
  rel="${rel#./}"
  mkdir -p "$out/$(dirname "$rel")"
  cp "$SITE/$rel" "$out/$rel"
  count=$((count + 1))
done < <(cd "$SITE" && find . -path ./media -prune -o -type f ! -name '.*' -print)

# From the media folder: the mp4 clips, the posters, the manifest and the README's gif files.
mkdir -p "$out/media"
for file in "$SITE"/media/manifest.json "$SITE"/media/*.mp4 "$SITE"/media/*-poster.jpg "$SITE"/media/*.gif; do
  [ -f "$file" ] || continue
  cp "$file" "$out/media/"
  count=$((count + 1))
done

: > "$out/.nojekyll"

# Fill in the placeholders, then check that every clip and poster the page names was copied.
python3 -I - "$out" "$owner" "$repo" "$license" <<'PY'
import html, pathlib, re, sys

out, owner, repo, license_name = sys.argv[1:5]
root = pathlib.Path(out)
pages = sorted(root.glob("*.html"))
if not pages:
    sys.exit("site-build: no HTML page was copied")

# A repository named <owner>.github.io is served at the root of that address.
if repo.lower() == f"{owner.lower()}.github.io":
    site_url = f"https://{owner.lower()}.github.io/"
else:
    site_url = f"https://{owner.lower()}.github.io/{repo}/"

problems = []
for page in pages:
    text = page.read_text(encoding="utf-8")
    text = text.replace("https://ben4mn.github.io/perch-app/", site_url)
    text = text.replace("LICENSE_NAME", html.escape(license_name))
    text = re.sub(r"\bOWNER\b", lambda m: owner, text)
    text = re.sub(r"\bREPO\b", lambda m: repo, text)
    left = [word for word in ("OWNER", "REPO", "LICENSE_NAME") if re.search(rf"\b{word}\b", text)]
    if left:
        problems.append(f"{page.name}: placeholders left: {', '.join(left)}")
    for ref in sorted(set(re.findall(r"media/[A-Za-z0-9._-]+", text))):
        if not (root / ref).is_file():
            problems.append(f"{page.name}: names {ref}, which is not in the build")
    page.write_text(text, encoding="utf-8")

if problems:
    sys.exit("site-build: " + "\nsite-build: ".join(problems))
print(f"site-build: the site will be at {site_url}")
PY

size="$(du -sh "$out" | awk '{print $1}')"
echo "site-build: copied $count files ($size) to $out"
echo "site-build: repository https://github.com/$owner/$repo, $license license"
