#!/usr/bin/env python3
"""Makes the website's looping clips from the app's own off-screen snapshot runner.

Each scene is one run of the Debug app's snapshot runner on a dated copy of the demo notebook. Where the
runner can hold a moment of a movement (the notch opening and closing, a prompt dropping, a task being
ticked, a note scrolling), every frame at 60 fps is its own picture of that moment, on the app's own
curves (`Motion` in Sources/PerchUI). Where it can only give stills (another view, mode or theme), they are
joined with short eased crossfades. Every clip ends on the picture it starts with, so it loops.

Standard library only. Run it through scripts/site-media.sh.
"""
import argparse
import datetime as dt
import json
import math
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(HERE))
sys.dont_write_bytecode = True  # no __pycache__ left in scripts/
import demo_dates  # noqa: E402

FPS = 60
# Every folder this script deletes things in carries this file, which scripts/site-media.sh puts in a work
# folder it made or was given empty, so a mistyped --work can't lose anything.
MARKER = ".perch-site-media"
APP = os.path.join(REPO, ".build/debug-app/Build/Products/Debug/Perch.app/Contents/MacOS/Perch")
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
MP4_LIMIT = 1_500_000

# Settings a snapshot run would otherwise read from this Mac's saved Perch settings, pinned to the app's
# defaults (or to what the clips need) so the clips come out the same on any Mac. For this run only.
PINNED = [
    "-notchMotion", "full", "-notchAmbient", "YES", "-notchBreathe", "NO", "-notchCardOrder", "",
    "-focusHidden", "YES", "-notepadFolder", "Daily", "-experimentalTabs", "NO", "-overdueExpanded", "NO",
    "-displayDensity", "comfortable", "-folderLayout", "grid", "-folderSort", "modified", "-clipsEnabled", "YES",
]
# What the demo notebook doesn't hold itself: who is "here" in the notch, and the words of the stand-in clips.
AGENTS = os.path.join(REPO, "Demo", "agents.json")
CLIPS = os.path.join(REPO, "Demo", "clips.json")
# Areas as the person would arrange them in Edit areas.
AREAS = ["areaorder:Studio,Home,Learning"]


def ease_in_out(x):
    """SwiftUI's easeInOut, cubic-bezier(0.42, 0, 0.58, 1)."""
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    low, high = 0.0, 1.0
    for _ in range(50):
        s = (low + high) / 2
        bx = 3 * (1 - s) ** 2 * s * 0.42 + 3 * (1 - s) * s * s * 0.58 + s ** 3
        if bx < x:
            low = s
        else:
            high = s
    s = (low + high) / 2
    return 3 * (1 - s) * s * s + s ** 3


def frames(seconds):
    return max(1, round(seconds * FPS))


class Scene:
    """A clip: the steps for one snapshot run, and a timeline of holds, moving frames and crossfades."""

    def __init__(self, id, title, description, poster, light=True, readme=False, setup=(), wait=3.0, stateless=False,
                 width=None, crop=None):
        self.id, self.title, self.description = id, title, description
        self.light, self.readme, self.width = light, readme, width
        self.crop = crop         # (x, y, width, height) of the runner's pictures to keep, in pixels
        self.steps = []          # every step of the run, in order
        self.wait = None         # the wait the runner is currently set to
        self.default_wait = wait
        self.stateless = stateless
        self.known = {}          # step text -> index, for scenes whose steps don't depend on what came before
        self.timeline = []       # ("frame", index, count) or ("fade", count) or ("loopfade", count)
        self.poster = poster     # seconds into the clip of the still that stands for it (reduced motion)
        for step in setup:
            self._add(step, 0.1)

    def _add(self, step, wait):
        if ";" in step:
            raise ValueError(f"a step can't hold ';': {step}")
        if wait != self.wait:
            self.steps.append(f"wait:{wait:g}")
            self.wait = wait
        self.steps.append(step)
        return len(self.steps) - 1

    def shot(self, *steps, wait=None):
        """Runs `steps` and keeps the picture after the last one."""
        wait = self.default_wait if wait is None else wait
        if self.stateless and len(steps) == 1 and steps[0] in self.known:
            return self.known[steps[0]]
        for step in steps[:-1]:
            self._add(step, 0.1)
        index = self._add(steps[-1], wait)
        if self.stateless and len(steps) == 1:
            self.known[steps[0]] = index
        return index

    def hold(self, seconds, *steps, wait=None):
        index = self.shot(*steps, wait=wait)
        self.timeline.append(("frame", index, frames(seconds)))
        return self

    def motion(self, make, seconds, start=0.0, wait=0.15):
        """One picture per frame: `make(t)` is the step for the moment `t` seconds into the movement."""
        for i in range(frames(seconds)):
            index = self.shot(make(start + i / FPS), wait=wait)
            self.timeline.append(("frame", index, 1))
        return self

    def fade(self, seconds=0.35):
        self.timeline.append(("fade", frames(seconds)))
        return self

    def loop(self, seconds=0.35):
        """Ends with a crossfade back to the first picture. Without it the last picture must be the first."""
        self.timeline.append(("loopfade", frames(seconds)))
        return self

    def script(self):
        return ";".join(self.steps)


def fmt(value):
    return f"{value:.4f}".rstrip("0").rstrip(".")


# ----------------------------------------------------------------------------------------------- scenes

def notch_open(dark):
    scene = Scene(
        "notch-open-dark" if dark else "notch-open",
        "The notch" + (" (dark)" if dark else ""),
        "The closed notch with today's counts swells under the pointer, springs open into the Workspace cards, "
        "holds, and closes again.",
        light=not dark, readme=not dark, stateless=True, setup=[f"notchscreen:1470:tall:still{':dark' if dark else ''}"],
        poster=3.7,  # the panel open, in the middle of its hold
    )
    scene.hold(1.6, "notchpeek:0", wait=0.3)
    scene.motion(lambda t: f"notchmove:open:{fmt(t)}", 0.9)
    scene.hold(2.4, "notchmove:open:3", wait=0.3)
    scene.motion(lambda t: f"notchmove:close:{fmt(t)}", 0.45)
    scene.hold(1.4, "notchpeek:0")
    return scene


def notch_modes():
    scene = Scene("notch-modes", "Notch modes",
                  "The open notch moving through its four modes: Workspace, Week, Insights and Clips.",
                  stateless=True, wait=1.0, setup=["notchscreen:1470:tall:still"],
                  poster=3.3)  # Week
    for index, mode in enumerate(["workspace", "week", "insights", "clips"]):
        if index:
            scene.fade(0.35)
        scene.hold(2.0, f"notchmode:{mode}")
    return scene.loop(0.35)


def notch_complete():
    scene = Scene("notch-complete", "Ticking a task in the notch",
                  "Two of today's tasks ticked from the open notch: the circle fills, the tick draws on, the title "
                  "is struck through, sparks fly, and the row makes way for the next.",
                  stateless=True, setup=["notchscreen:1470:tall:still"],
                  poster=2.55)  # the first task ticked and struck through, a moment after the click at 2.2
    for done in (0, 1):
        scene.hold(1.6 if done == 0 else 0.9, f"notchtick:-9:{done}", wait=0.3)
        # From the pointer arriving, through the click at 0, to the row leaving once the tick is written
        # (0.48 s) and the rows below settling into place.
        scene.motion(lambda t, done=done: f"notchtick:{fmt(t)}:{done}", 1.85, start=-0.6)
    scene.hold(1.4, "notchtick:-9:2", wait=0.3)
    return scene.loop(0.45)


def notch_live():
    scene = Scene("notch-live", "The closed notch at work",
                  "The closed notch carrying things without opening: a reminder drops out of it, then an agent's "
                  "question, then the focus timer rides beside it.",
                  stateless=True, crop=(0, 0, 2010, 300), setup=["notchscreen:1470:tall:still"],
                  poster=3.0)  # the reminder under the notch
    scene.hold(1.2, "notchpeek:0", wait=0.3)
    for kind in ("reminder", "agent"):
        scene.motion(lambda t, kind=kind: f"notchmove:prompt:{fmt(t)}:{kind}", 0.8)
        scene.hold(2.0, f"notchmove:prompt:3:{kind}", wait=0.3)
        scene.motion(lambda t, kind=kind: f"notchmove:promptaway:{fmt(t)}:{kind}", 0.5)
        scene.hold(0.7, "notchpeek:0")
    # A session just started: 25:00, then a second passes on the clock for every second of the clip.
    live_in, live_hold = 0.7, 1.8
    scene.motion(lambda t: f"notchmove:live:{fmt(t)}:{int(t)}", live_in)
    for second in range(int(live_in), int(live_in + live_hold) + 1):
        start, end = max(second, live_in), min(second + 1, live_in + live_hold)
        if end > start:
            scene.hold(end - start, f"notchmove:live:3:{second}", wait=0.3)
    elapsed = int(live_in + live_hold)
    scene.motion(lambda t: f"notchmove:liveaway:{fmt(t)}:{elapsed}", 0.6)
    scene.hold(0.7, "notchpeek:0")
    return scene


def clips():
    scene = Scene("clips", "Clips",
                  "The Clips pane in the notch: everything copied lately, then each kind on its own (text, links, "
                  "pictures, files), and a card under the pointer.",
                  stateless=True, wait=1.0, setup=["notchscreen:1470:tall:still"],
                  poster=1.0)  # All, with cards of every kind
    scene.hold(2.0, "notchmode:clips")
    for kind in ("text", "links", "images", "files"):
        scene.fade(0.3).hold(1.4, f"notchmode:clips:{kind}")
    scene.fade(0.3).hold(1.2, "notchmode:clips")
    scene.fade(0.18).hold(1.8, "notchmode:clips:hover")
    return scene.loop(0.3)


def tasks():
    scene = Scene("tasks", "Tasks",
                  "The main window on the demo notebook, through Today, Upcoming, List, Calendar and Board.",
                  readme=True, width=1920, setup=AREAS, poster=1.0)  # Today
    for index, view in enumerate(["today", "upcoming", "list", "calendar:month", "view:board"]):
        if index:
            scene.fade(0.35)
        scene.hold(2.0, view)
    return scene.loop(0.35)


def notes():
    okafor = "Studio/Clients/Okafor garden room.md"
    scene = Scene("notes", "Notes",
                  "A client note in the reader, scrolled to its drawing and tables; a note being edited beside its "
                  "preview; a tune written in ABC; and a whiteboard sketch.",
                  readme=True, width=1920, setup=AREAS, poster=0.9)  # the client note, before it scrolls
    scene.hold(1.8, "notemode:read", f"file:{okafor}")
    scene.motion(lambda t: f"webscroll:{fmt(0.42 * ease_in_out(t / 1.0))}", 1.0, wait=0.35)
    scene.hold(1.4, "webscroll:0.42", wait=1.0)
    scene.fade(0.35).hold(2.2, "notemode:split", "file:Studio/Process/Pricing a garden room.md")
    scene.fade(0.35).hold(2.2, "notemode:read", "file:Learning/Fiddle/Tunes to learn.md")
    scene.fade(0.35).hold(2.2, "whiteboard:Studio/Lindqvist floor plan.excalidraw")
    return scene.loop(0.35)


def themes():
    scene = Scene("themes", "Themes",
                  "The Today view crossfading through five of the built-in themes, light and dark.",
                  width=1920, setup=AREAS, poster=5.3)  # Perch Dark
    for index, theme in enumerate(["perch-light", "paper", "perch-dark", "midnight", "everforest"]):
        if index:
            scene.fade(0.4)
        scene.hold(1.8, f"theme:{theme}")
    return scene.loop(0.4)


def tabs_split():
    okafor = "file:Studio/Clients/Okafor garden room.md"
    scene = Scene("tabs-split", "Tabs and split view",
                  "The experimental tabs and split view: Today in one tab, a note opened in a second tab, then the "
                  "calendar opened beside the note.",
                  width=1920, setup=AREAS + ["set:experimentalTabs=true"], poster=6.7)  # the split view
    scene.hold(2.2, "today")
    scene.fade(0.35).hold(2.4, f"tabs:open:{okafor}")
    scene.fade(0.35).hold(2.8, "tabs:split:calendar")
    return scene.loop(0.4)


def agents():
    scene = Scene("agents", "Agents in the notebook",
                  "An AI agent working in the same notebook: it asks from the closed notch whether a task is done, "
                  "and the open notch shows who is here and what waits to be ticked.",
                  stateless=True, setup=["notchscreen:1470:tall:still"],
                  poster=3.1)  # the agent's question under the closed notch
    scene.hold(1.2, "notchpeek:0", wait=0.3)
    scene.motion(lambda t: f"notchmove:prompt:{fmt(t)}:agent", 0.8)
    scene.hold(2.2, "notchmove:prompt:3:agent", wait=0.3)
    scene.motion(lambda t: f"notchmove:promptaway:{fmt(t)}:agent", 0.5)
    scene.hold(0.5, "notchpeek:0")
    scene.motion(lambda t: f"notchmove:open:{fmt(t)}", 0.9)
    scene.hold(2.6, "notchmove:open:3", wait=0.3)
    scene.motion(lambda t: f"notchmove:close:{fmt(t)}", 0.45)
    scene.hold(1.0, "notchpeek:0")
    return scene


def iphone():
    scene = Scene("iphone", "On a folding phone",
                  "The same notebook in the iPhone app's wide layout, as on an open folding phone held sideways: "
                  "Today beside the week, the Board, and a note beside its folder. Drawn by the Mac's snapshot "
                  "runner from the iPhone app's own layout, without the phone's status bar.",
                  width=1600, setup=AREAS + ["duo:951x669:expanded"], poster=1.1)  # Today beside the week
    scene.hold(2.2, "view:today")
    scene.fade(0.35).hold(2.2, "view:board")
    scene.fade(0.35).hold(2.4, "file:Studio/Clients/Okafor garden room.md")
    return scene.loop(0.35)


SCENES = {
    "notch-open": lambda: notch_open(False),
    "notch-open-dark": lambda: notch_open(True),
    "notch-modes": notch_modes,
    "notch-complete": notch_complete,
    "notch-live": notch_live,
    "clips": clips,
    "tasks": tasks,
    "notes": notes,
    "themes": themes,
    "tabs-split": tabs_split,
    "agents": agents,
    "iphone": iphone,
}

# ------------------------------------------------------------------------------------------- rendering


def build_owner():
    """The owner of the tasks of whoever uses the Debug app (PERCH_OWNER_ID, through its Info.plist), so the
    notebook owner's tasks show as theirs in it. The public default when the app doesn't say."""
    info = os.path.join(os.path.dirname(os.path.dirname(APP)), "Info.plist")
    try:
        with open(info, "rb") as f:
            owner = str(plistlib.load(f).get("PerchOwnerID", "")).strip()
    except (OSError, plistlib.InvalidFileException):
        owner = ""
    return owner if owner and not owner.startswith("$(") else demo_dates.OWNER


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", head[16:24])


def run(command, **kwargs):
    result = subprocess.run(command, **kwargs)
    if result.returncode != 0:
        raise SystemExit(f"failed ({result.returncode}): {' '.join(command[:6])} ...")
    return result


def render(scene, vault, work, compose):
    raw = os.path.join(work, scene.id, "raw")
    shutil.rmtree(os.path.join(work, scene.id), ignore_errors=True)
    os.makedirs(raw)
    arguments = [APP, "-perchSnapshotDir", raw, "-perchSnapshotVault", vault, "-perchSnapshotScript", scene.script(),
                 "-perchSnapshotComposite", "-perchSnapshotFlatSidebar",
                 "-perchSnapshotAgents", AGENTS, "-perchSnapshotClips", CLIPS] + PINNED
    if scene.light:
        arguments.append("-perchSnapshotLight")
    started = time.time()
    with open(os.path.join(work, scene.id, "run.log"), "w") as log:
        run(arguments, stdout=log, stderr=subprocess.STDOUT, cwd=work, timeout=1800)
    picture = lambda index: os.path.join(raw, f"{index:02d}.png")

    # The frame list: each entry is a picture, or a crossfade between two.
    sequence = []
    timeline = scene.timeline
    for position, entry in enumerate(timeline):
        if entry[0] == "frame":
            sequence += [picture(entry[1])] * entry[2]
        else:
            before = next(e for e in reversed(timeline[:position]) if e[0] == "frame")
            after = next((e for e in timeline[position + 1:] if e[0] == "frame"), None) if entry[0] == "fade" else None
            target = picture((after or next(e for e in timeline if e[0] == "frame"))[1])
            count = entry[1]
            for i in range(count):
                sequence.append(("blend", picture(before[1]), target, ease_in_out((i + 1) / (count + 1))))
    needed = {p for p in sequence if isinstance(p, str)} | {p for e in sequence if isinstance(e, tuple) for p in e[1:3]}
    missing = [p for p in needed if not os.path.exists(p)]
    if missing:
        raise SystemExit(f"{scene.id}: the runner wrote no picture for {len(missing)} steps, e.g. {missing[0]}")
    sizes = {png_size(p) for p in needed}
    if len(sizes) != 1:
        raise SystemExit(f"{scene.id}: pictures differ in size: {sorted(sizes)}")
    width, height = sizes.pop()

    # Crossfade frames, all in one go.
    blends = os.path.join(work, scene.id, "blend")
    os.makedirs(blends)
    jobs, made = [], {}
    for position, entry in enumerate(sequence):
        if isinstance(entry, tuple):
            key = (entry[1], entry[2], round(entry[3], 5))
            if key not in made:
                made[key] = os.path.join(blends, f"{len(made):04d}.png")
                jobs.append("\t".join([entry[1], entry[2], f"{entry[3]:.5f}", made[key]]))
            sequence[position] = made[key]
    if jobs:
        with open(os.path.join(work, scene.id, "blend.tsv"), "w") as f:
            f.write("\n".join(jobs) + "\n")
        run([compose, "blend", os.path.join(work, scene.id, "blend.tsv")])

    # Numbered links, so ffmpeg reads the clip at exactly 60 frames a second.
    seq = os.path.join(work, scene.id, "seq")
    os.makedirs(seq)
    for number, path in enumerate(sequence):
        os.symlink(path, os.path.join(seq, f"{number:05d}.png"))
    if not 0 <= round(scene.poster * FPS) < len(sequence):
        raise SystemExit(f"{scene.id}: its poster at {scene.poster} s is outside the clip ({len(sequence) / FPS:.2f} s)")
    poster = sequence[round(scene.poster * FPS)]
    return dict(sequence=sequence, width=width, height=height, poster=poster, seq=seq)


def encode(scene, rendered, out):
    files = {}
    source = ["-framerate", str(FPS), "-i", os.path.join(rendered["seq"], "%05d.png")]
    x, y, kept_width, kept_height = scene.crop or (0, 0, rendered["width"], rendered["height"])
    width = scene.width or kept_width
    height = round(kept_height * width / kept_width / 2) * 2
    width -= width % 2
    scale = (f"crop={kept_width}:{kept_height}:{x}:{y}," if scene.crop else "") + f"scale={width}:{height}:flags=lanczos"
    quiet = [FFMPEG, "-hide_banner", "-loglevel", "error", "-y"]

    mp4 = os.path.join(out, f"{scene.id}.mp4")
    crf = 20
    while True:
        # One keyframe for the whole clip: most of a clip is a picture held still, and a long group of
        # pictures halves the file against the default.
        run(quiet + source + ["-vf", f"{scale},format=yuv420p", "-c:v", "libx264", "-preset", "veryslow", "-tune", "animation",
                              "-crf", str(crf), "-g", "1200", "-profile:v", "high", "-movflags", "+faststart", "-an", mp4])
        if os.path.getsize(mp4) <= MP4_LIMIT or crf >= 28:
            break
        crf += 2
    files["mp4"] = mp4

    encoders = subprocess.run([FFMPEG, "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    if "libvpx-vp9" in encoders:
        webm = os.path.join(out, f"{scene.id}.webm")
        run(quiet + source + ["-vf", f"{scale},format=yuv420p", "-c:v", "libvpx-vp9", "-crf", "36", "-b:v", "0", "-g", "1200",
                              "-row-mt", "1", "-deadline", "good", "-cpu-used", "2", "-an", webm])
        files["webm"] = webm

    poster = os.path.join(out, f"{scene.id}-poster.jpg")
    run(quiet + ["-i", rendered["poster"], "-vf", scale, "-q:v", "2", poster])
    files["poster"] = poster

    if scene.readme:
        gif = os.path.join(out, f"{scene.id}.gif")
        crop = f"crop={kept_width}:{kept_height}:{x}:{y}," if scene.crop else ""
        run(quiet + source + ["-vf", f"fps=25,{crop}scale=800:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=200:stats_mode=diff[p];"
                                     "[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle", "-loop", "0", gif])
        files["gif"] = gif
    return files, width, height, crf


def contact_sheet(rows, compose, path):
    lines = []
    for scene_id, sequence in rows:
        picks = [sequence[0], sequence[len(sequence) // 2], sequence[-1]]
        lines.append("\t".join([scene_id] + picks))
    spec = path + ".tsv"
    with open(spec, "w") as f:
        f.write("\n".join(lines) + "\n")
    run([compose, "sheet", spec, path])
    os.remove(spec)


def main():
    parser = argparse.ArgumentParser(description="Makes site/media from the snapshot runner.")
    parser.add_argument("--scenes", help="comma-separated scene ids (default: all)")
    parser.add_argument("--work", required=True, help="scratch folder for the notebook copy and frames")
    parser.add_argument("--out", default=os.path.join(REPO, "site", "media"))
    parser.add_argument("--contact-sheet", help="also write a contact sheet PNG here")
    parser.add_argument("--compose", required=True, help="the compiled compose helper")
    parser.add_argument("--date", help="the notebook's today, YYYY-MM-DD (default: today)")
    arguments = parser.parse_args()

    today = dt.date.fromisoformat(arguments.date) if arguments.date else dt.date.today()
    chosen = arguments.scenes.split(",") if arguments.scenes else list(SCENES)
    unknown = [s for s in chosen if s not in SCENES]
    if unknown:
        raise SystemExit(f"unknown scenes: {', '.join(unknown)}. Known: {', '.join(SCENES)}")

    work = os.path.abspath(arguments.work)
    if not os.path.isfile(os.path.join(work, MARKER)):
        raise SystemExit(f"{work} isn't a work folder made by scripts/site-media.sh (no {MARKER} in it). Nothing was deleted.")
    vault = os.path.join(work, "notebook")
    shutil.rmtree(vault, ignore_errors=True)
    written, days = demo_dates.copy(vault, today, build_owner())
    print(f"Notebook: {written} files in {vault}, dates moved {days:+d} days to {today}, owned by the Debug app's owner.")

    out = os.path.abspath(arguments.out)
    os.makedirs(out, exist_ok=True)
    manifest_path = os.path.join(out, "manifest.json")
    manifest = {"scenes": []}
    if os.path.exists(manifest_path) and arguments.scenes:
        with open(manifest_path) as f:
            manifest = json.load(f)
    entries = {entry["id"]: entry for entry in manifest.get("scenes", [])}
    sheet_rows = []
    for scene_id in chosen:
        scene = SCENES[scene_id]()
        started = time.time()
        rendered = render(scene, vault, work, arguments.compose)
        files, width, height, crf = encode(scene, rendered, out)
        duration = len(rendered["sequence"]) / FPS
        entries[scene.id] = {
            "id": scene.id, "title": scene.title, "description": scene.description,
            "appearance": "light" if scene.light else "dark", "readme": scene.readme,
            "width": width, "height": height, "fps": FPS, "frames": len(rendered["sequence"]),
            "duration": round(duration, 3), "loops": True,
            "files": {kind: {"path": os.path.basename(path), "bytes": os.path.getsize(path)} for kind, path in files.items()},
            "sourcePixels": [rendered["width"], rendered["height"]], "mp4Crf": crf,
        }
        sheet_rows.append((scene.id, rendered["sequence"]))
        sizes = ", ".join(f"{kind} {os.path.getsize(path) / 1e6:.2f} MB" for kind, path in files.items())
        print(f"{scene.id}: {duration:.2f} s, {width}x{height}, {sizes} (crf {crf}, {time.time() - started:.0f} s)")

    order = [s for s in SCENES if s in entries]
    manifest = {
        "generated": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "notebookDate": today.isoformat(),
        "note": "Every name, task and note in these clips is invented (Demo/README.md). Each clip loops: it ends on its first picture.",
        "scenes": [entries[s] for s in order],
    }
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"Wrote {manifest_path}")
    if arguments.contact_sheet:
        os.makedirs(os.path.dirname(os.path.abspath(arguments.contact_sheet)), exist_ok=True)
        contact_sheet(sheet_rows, arguments.compose, arguments.contact_sheet)
        print(f"Wrote {arguments.contact_sheet}")


if __name__ == "__main__":
    main()
