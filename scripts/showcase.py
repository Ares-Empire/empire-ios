#!/usr/bin/env python3
"""Showcase images of the five iPhone apps, each screen inside a drawn iPhone, with made-up sample data only.

    python3 scripts/showcase.py [app ...]        # all five apps when none is named

For each named app it builds the app (Debug, for the simulator), installs it on a simulator of its own
(`claude-showcase`, iPhone 17, iOS 27.0, created here and deleted at the end), launches it once per shot with the
app's DEBUG sample arguments (no login, no server), takes a screenshot, draws an iPhone around it and writes
`showcase/<app>/NN-name.png`. Then pngquant makes each file small, unless that would band the gradients, in which
case the file stays a plain optimised PNG. Last it writes `showcase/README.md` from the shot table (SHOTS) and a
contact sheet of every image in `showcase/` to `build/showcase/contact-sheet.png` (git-ignored) to look at.

Needs: Xcode 27 with the iOS 27.0 simulator runtime, Python 3 with Pillow, pngquant (/opt/homebrew/bin/pngquant).
The iPhone is drawn here (no Apple or third-party device artwork). Patrik's own simulators are never touched.

Options: --skip-build (use the apps already built in build/showcase), --keep-simulator (reuse `claude-showcase` and
leave it running, for trying shots).
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("Pillow is missing: python3 -m pip install Pillow")

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "showcase"             # git-ignored: derived data, build logs, raw screenshots, contact sheet
OUT = ROOT / "showcase"
PNGQUANT = shutil.which("pngquant") or "/opt/homebrew/bin/pngquant"

SIMULATOR_NAME = "claude-showcase"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
STATUS_BAR = ["--time", "9:41", "--batteryState", "discharging", "--batteryLevel", "100", "--cellularMode", "active",
              "--cellularBars", "4", "--wifiBars", "3", "--dataNetwork", "wifi"]
# The apps in English with British formats (CLAUDE.md → Languages).
LANGUAGE = ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]


@dataclass(frozen=True)
class App:
    folder: str          # project folder and scheme
    bundle_id: str


APPS = {
    "aresium": App("Aresium", "de.ares-empire.aresium"),
    "empire": App("Empire", "de.ares-empire.empire"),
    "arestemis": App("Arestemis", "de.ares-empire.arestemis"),
    "aresus": App("Aresus", "de.ares-empire.aresus"),
    "arestoteles": App("Arestoteles", "de.ares-empire.arestoteles"),
}


@dataclass(frozen=True)
class Shot:
    app: str
    name: str            # file name without .png: showcase/<app>/<name>.png
    caption: str         # for showcase/README.md
    appearance: str      # light or dark (-appearance; Aresium's red mode holds dark by itself)
    wait: float          # seconds from launch to screenshot
    args: tuple[str, ...]


# Every shot runs in the app's sample mode (-sampleData): made-up data bundled in the app, no login, no server.
# The arguments are listed in CLAUDE.md (Setup state) and read in each app's ContentView / LaunchArguments.
SHOTS = [
    Shot("aresium", "01-overview-dark", "Three months of spending by category, with the monthly chart",
         "dark", 6, ("-sampleData", "-sampleOverview", "-sampleGraph")),
    Shot("aresium", "02-overview-light", "The same overview in light mode",
         "light", 6, ("-sampleData", "-sampleOverview", "-sampleGraph")),
    Shot("aresium", "03-red-mode", "Red mode: the overview with its chart, scrolled down to the ARESIUM band",
         "dark", 6, ("-sampleData", "-sampleRed", "-sampleOverview", "-sampleGraph", "-scrollToEnd")),
    Shot("aresium", "04-income-dark", "The income side: where the money came from over three months",
         "dark", 6, ("-sampleData", "-sampleIncome", "-sampleOverview", "-sampleGraph")),
    Shot("aresium", "05-transaction-light", "A transaction's details, with its category and where else it counts",
         "light", 7, ("-sampleData", "-sampleCategory", "Groceries", "-sampleMonth", "2026-10",
                      "-sampleTransaction", "sample-19")),

    Shot("empire", "01-throne-room-dark", "The throne room: the provinces on a ring, the chronicle below",
         "dark", 7, ("-sampleData",)),
    Shot("empire", "02-marble-hall-light", "The same room in light mode, the marble hall",
         "light", 7, ("-sampleData",)),
    Shot("empire", "03-province-light", "A province's page: what it is, its features, what's new",
         "light", 7, ("-sampleData", "-openSheet", "province")),
    Shot("empire", "04-approvals-dark", "Approvals: new sign-ups and requests for more apps",
         "dark", 7, ("-sampleData", "-openSheet", "approvals")),
    Shot("empire", "05-more-apps-dark", "More apps: ask for another app; it joins your ring once approved",
         "dark", 7, ("-sampleData", "-sampleCatalog", "-openSheet", "add")),

    Shot("arestemis", "01-hunt-dark", "The hunt: the search running, today's counts, the portals and the latest finds",
         "dark", 6, ("-sampleData", "-tab", "hunt")),
    Shot("arestemis", "02-listings-light", "Every listing the hunt found, with its state",
         "light", 6, ("-sampleData", "-tab", "listings", "-filter", "all")),
    Shot("arestemis", "03-listing-dark", "One listing: the facts, why it fits the search, the ad's own text",
         "dark", 6, ("-sampleData", "-openMatch", "41")),
    Shot("arestemis", "04-search-light", "The search, set in fields, or described in a sentence",
         "light", 6, ("-sampleData", "-tab", "search")),

    Shot("aresus", "01-watchtower-dark", "The watchtower: the server, then every province by state",
         "dark", 6, ("-sampleData", "-tab", "aresus")),
    Shot("aresus", "02-province-dark", "A province with an issue: its checks, last deploy and uptime",
         "dark", 6, ("-sampleData", "-openProvince", "aresium")),
    Shot("aresus", "03-aresync-light", "Aresync: each machine's last sync and the runs by day",
         "light", 6, ("-sampleData", "-tab", "aresync")),
    Shot("aresus", "04-widgets-dark", "The home and lock screen widgets",
         "dark", 6, ("-sampleData", "-widgetGallery", "issues")),

    Shot("arestoteles", "01-positions-dark", "Positions: the views held, grouped by topic",
         "dark", 6, ("-sampleData", "-tab", "positions")),
    Shot("arestoteles", "02-position-light", "One position: how the view changed and the evidence behind it",
         "light", 6, ("-sampleData", "-openPosition", "Printing press#1")),
    Shot("arestoteles", "03-note-dark", "A topic note: the brief, the positions on it, then the sections",
         "dark", 6, ("-sampleData", "-openNote", "Printing press")),
    Shot("arestoteles", "04-search-light", "Search: the best matches by meaning, sentence by sentence",
         "light", 7, ("-sampleData", "-tab", "search", "-search", "how fast did printing spread")),
]


# --- Shell helpers ----------------------------------------------------------------------------------------------------

def run(command: list[str], *, check: bool = True, quiet: bool = False, log: Path | None = None) -> str:
    """Runs a command; returns its output. With `log`, the output goes to that file and only a failure is shown."""
    result = subprocess.run(command, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if log:
        log.write_text(output)
    if check and result.returncode != 0:
        tail = "\n".join(output.strip().splitlines()[-30:])
        raise SystemExit(f"Failed ({result.returncode}): {' '.join(command)}\n{tail}"
                         + (f"\nFull log: {log}" if log else ""))
    if not quiet and not log and output.strip():
        print(output.strip())
    return output


def say(message: str) -> None:
    print(message, flush=True)


# --- Simulator --------------------------------------------------------------------------------------------------------

def showcase_simulators() -> list[str]:
    """UDIDs of every simulator named `claude-showcase` (never any other)."""
    listing = json.loads(run(["xcrun", "simctl", "list", "devices", "-j"], quiet=True))
    return [device["udid"] for devices in listing["devices"].values() for device in devices
            if device["name"] == SIMULATOR_NAME]


def delete_simulator(udid: str) -> None:
    run(["xcrun", "simctl", "shutdown", udid], check=False, quiet=True)
    run(["xcrun", "simctl", "delete", udid], check=False, quiet=True)


def boot(udid: str) -> None:
    run(["xcrun", "simctl", "boot", udid], check=False, quiet=True)      # fails harmlessly when already booted
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], quiet=True)


def prepare_simulator(keep: bool) -> str:
    existing = showcase_simulators()
    if keep and existing:
        udid = existing[0]
        boot(udid)
    else:
        for udid in existing:                                           # left over from an interrupted run
            delete_simulator(udid)
        udid = run(["xcrun", "simctl", "create", SIMULATOR_NAME, DEVICE_TYPE, RUNTIME], quiet=True).strip()
        boot(udid)
        # The status bar's clock follows the simulator's own region: en_US shows "9:41" (Germany: "09:41"). It is read
        # when the simulator starts, hence the restart. The apps get their language from their launch arguments.
        spawn = ["xcrun", "simctl", "spawn", udid, "defaults", "write", "-g"]
        run(spawn + ["AppleLocale", "en_US"], quiet=True)
        run(spawn + ["AppleLanguages", "-array", "en"], quiet=True)
        run(["xcrun", "simctl", "shutdown", udid], quiet=True)
        boot(udid)
    run(["xcrun", "simctl", "status_bar", udid, "override"] + STATUS_BAR, quiet=True)
    return udid


def build(app: App, udid: str) -> Path:
    say(f"  building {app.folder}")
    logs = WORK / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    run(["xcodebuild", "-project", str(ROOT / app.folder / f"{app.folder}.xcodeproj"), "-scheme", app.folder,
         "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", f"platform=iOS Simulator,id={udid}",
         "-derivedDataPath", str(WORK / "DerivedData"), "build"], log=logs / f"{app.folder}.log")
    return built_app(app)


def built_app(app: App) -> Path:
    path = WORK / "DerivedData" / "Build" / "Products" / "Debug-iphonesimulator" / f"{app.folder}.app"
    if not path.exists():
        raise SystemExit(f"{path} is missing: run without --skip-build")
    return path


def screenshot(udid: str, shot: Shot) -> Path:
    """Launches the app for one shot, from the home screen (an app launched over another shows a back link in the
    status bar), and takes the screenshot with the display's rounded corners as transparency."""
    for other in APPS.values():
        run(["xcrun", "simctl", "terminate", udid, other.bundle_id], check=False, quiet=True)
    time.sleep(1)
    app = APPS[shot.app]
    run(["xcrun", "simctl", "launch", udid, app.bundle_id, *shot.args, "-appearance", shot.appearance, *LANGUAGE],
        quiet=True)
    time.sleep(shot.wait)
    raw = WORK / "raw" / shot.app / f"{shot.name}.png"
    raw.parent.mkdir(parents=True, exist_ok=True)
    run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", "--mask=alpha", str(raw)], quiet=True)
    return raw


# --- The drawn iPhone -------------------------------------------------------------------------------------------------
#
# All lengths are screenshot pixels: the iPhone 17's display is 1206 x 2622 at 460 pixels per inch. The device is
# composed at that size and scaled down at the end (SCALE).
#
# The display's corners are not circular arcs: the simulator's own mask (taken with the screenshot) is a superellipse,
# |x/E|^N + |y/E|^N = 1 per corner, fitted to it as E = 229.5 px, N = 2.54 (about 1 px off at most). The screen keeps
# that exact mask; the glass border and the frame around it are drawn as curves at a fixed distance outside the
# fitted shape, so they stay equally wide around the corners as on the real phone.

SCREEN_W, SCREEN_H = 1206, 2622
CORNER_EXTENT, CORNER_EXPONENT = 229.5, 2.54
GLASS = 27              # black glass border around the display
FRAME = 17              # the metal band around the glass, seen from the front
BODY = GLASS + FRAME    # 44 px each side: 71.5 x 149.6 mm, as the iPhone 17
PAD_X, PAD_TOP, PAD_BOTTOM = 130, 100, 190                              # room for the buttons and the shadow
CANVAS_W = SCREEN_W + 2 * (BODY + PAD_X)
CANVAS_H = SCREEN_H + 2 * BODY + PAD_TOP + PAD_BOTTOM
SCREEN_X, SCREEN_Y = PAD_X + BODY, PAD_TOP + BODY
SCALE = 1100 / (SCREEN_W + 2 * BODY)                                    # the device is 1100 px wide in the image
SUPERSAMPLE = 3                                                         # shapes are drawn 3x and scaled down (smooth edges)

# Buttons: (side, centre and length as a fraction of the body's height, how far it stands out, colour)
BUTTONS = [
    ("left", 0.215, 0.050, 8, "metal"),       # Action button
    ("left", 0.330, 0.084, 8, "metal"),       # volume up
    ("left", 0.430, 0.084, 8, "metal"),       # volume down
    ("right", 0.385, 0.126, 8, "metal"),      # side button
    ("right", 0.680, 0.108, 3, "sapphire"),   # Camera Control, almost flush with the frame
]


def corner_curve(offset: float, steps: int = 90) -> list[tuple[float, float]]:
    """The top-left corner of the display shape grown by `offset`, from the left edge to the top edge, in screen
    coordinates (the screen's top-left corner is 0, 0)."""
    e, n = CORNER_EXTENT, CORNER_EXPONENT
    points = []
    for i in range(steps + 1):
        t = (math.pi / 2) * i / steps
        c, s = math.cos(t), math.sin(t)
        # Superellipse point around the corner centre (e, e), and its outward normal.
        x = e - e * c ** (2 / n)
        y = e - e * s ** (2 / n)
        # Normal of |u|^n + |v|^n = 1 at (u, v) = (c^(2/n), s^(2/n)): (u^(n-1), v^(n-1)).
        nu = (c ** (2 / n)) ** (n - 1)
        nv = (s ** (2 / n)) ** (n - 1)
        length = math.hypot(nu, nv) or 1.0
        points.append((x - offset * nu / length, y - offset * nv / length))
    return points


def outline(offset: float, origin: tuple[float, float], scale: float) -> list[tuple[float, float]]:
    """The whole display shape grown by `offset`, as a polygon placed with the screen's top-left at `origin`."""
    tl = corner_curve(offset)
    w, h = SCREEN_W, SCREEN_H
    ox, oy = origin
    corners = [
        [(x, y) for x, y in tl],                                         # top-left: left edge → top edge
        [(w - x, y) for x, y in reversed(tl)],                           # top-right: top edge → right edge
        [(w - x, h - y) for x, y in tl],                                 # bottom-right: right edge → bottom edge
        [(x, h - y) for x, y in reversed(tl)],                           # bottom-left: bottom edge → left edge
    ]
    return [((ox + x) * scale, (oy + y) * scale) for corner in corners for x, y in corner]


def mix(a: tuple[int, ...], b: tuple[int, ...], t: float) -> tuple[int, ...]:
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def smooth_mask(draw_shapes, size: tuple[int, int]) -> Image.Image:
    """A greyscale mask drawn at SUPERSAMPLE times the size and scaled down, for smooth edges."""
    big = Image.new("L", (size[0] * SUPERSAMPLE, size[1] * SUPERSAMPLE), 0)
    draw_shapes(ImageDraw.Draw(big), SUPERSAMPLE)
    return big.resize(size, Image.Resampling.BOX)


def vertical_gradient(size: tuple[int, int], top: tuple[int, ...], bottom: tuple[int, ...]) -> Image.Image:
    column = Image.new("RGB", (1, 256))
    for y in range(256):
        column.putpixel((0, y), mix(top, bottom, y / 255))
    return column.resize(size, Image.Resampling.BILINEAR)


def device_frame() -> Image.Image:
    """The iPhone without its screen content, on a transparent canvas: shadow, buttons, frame and glass."""
    size = (CANVAS_W, CANVAS_H)
    origin = (SCREEN_X, SCREEN_Y)
    body_top = SCREEN_Y - BODY
    body_height = SCREEN_H + 2 * BODY
    body_left, body_right = SCREEN_X - BODY, SCREEN_X + SCREEN_W + BODY

    def button_boxes(scale: float, kinds: tuple[str, ...]):
        for side, centre, length, out, kind in BUTTONS:
            if kind not in kinds:
                continue
            y0 = body_top + (centre - length / 2) * body_height
            y1 = body_top + (centre + length / 2) * body_height
            if side == "left":
                x0, x1 = body_left - out, body_left + 6
            else:
                x0, x1 = body_right - 6, body_right + out
            yield [x0 * scale, y0 * scale, x1 * scale, y1 * scale], min(out, 6) * scale

    # Silhouette (body and buttons), for the shadow.
    def silhouette(draw, s):
        draw.polygon(outline(BODY, origin, s), fill=255)
        for box, radius in button_boxes(s, ("metal", "sapphire")):
            draw.rounded_rectangle(box, radius=radius, fill=255)
    shape = smooth_mask(silhouette, size)

    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    # A wide soft shadow below and a tight one at the edge, black with transparency so it works on any background.
    for blur, opacity, drop in ((56, 0.30, 44), (14, 0.22, 10)):
        alpha = shape.point(lambda v, o=opacity: round(v * o))
        alpha = ImageChops.offset(alpha, 0, drop).filter(ImageFilter.GaussianBlur(blur))
        shadow = Image.new("RGBA", size, (0, 0, 0, 0))
        shadow.putalpha(alpha)
        canvas = Image.alpha_composite(canvas, shadow)

    # Buttons: brushed metal, lighter on the outer face; Camera Control darker, like sapphire glass.
    for kind, light, dark in (("metal", (128, 131, 137), (52, 54, 58)), ("sapphire", (70, 74, 80), (22, 23, 26))):
        def buttons(draw, s, kind=kind):
            for box, radius in button_boxes(s, (kind,)):
                draw.rounded_rectangle(box, radius=radius, fill=255)
        mask = smooth_mask(buttons, size)
        face = Image.new("RGB", size, dark)
        # Light falls on the outermost pixels of each button: a horizontal ramp from the body outwards.
        ramp = Image.new("L", size, 0)
        ramp_draw = ImageDraw.Draw(ramp)
        for side, _, _, out, button_kind in BUTTONS:
            if button_kind != kind:
                continue
            for i in range(out + 7):
                level = round(255 * max(0.0, min(1.0, i / max(out, 1))) ** 1.4)
                x = body_left - i if side == "left" else body_right + i
                ramp_draw.line([(x, 0), (x, CANVAS_H)], fill=level)
        face = Image.composite(Image.new("RGB", size, light), face, ramp)
        canvas.paste(face, (0, 0), mask)

    # The frame: graphite titanium. Concentric bands from the outer edge in: a dark outline (keeps the edge crisp on a
    # white page), a bright rim where the rounded side catches the light, the band itself, a dark groove at the glass.
    profile = [                  # (distance from the outer edge in px, colour)
        (0.0, (28, 29, 32)),
        (1.2, (168, 172, 179)),     # the bright rim
        (2.8, (112, 115, 121)),
        (6.5, (72, 74, 79)),
        (10.5, (56, 58, 63)),
        (13.5, (64, 66, 71)),
        (15.0, (94, 97, 103)),      # a faint chamfer before the glass
        (16.2, (14, 14, 16)),       # the groove at the glass
        (FRAME, (10, 10, 12)),
    ]
    frame_rgb = Image.new("RGB", (size[0] * SUPERSAMPLE, size[1] * SUPERSAMPLE), (0, 0, 0))
    draw = ImageDraw.Draw(frame_rgb)
    step = 1 / SUPERSAMPLE
    depth = 0.0
    while depth < FRAME:
        for (d0, c0), (d1, c1) in zip(profile, profile[1:]):
            if d0 <= depth <= d1:
                colour = mix(c0, c1, (depth - d0) / (d1 - d0))
                break
        else:
            colour = profile[-1][1]
        draw.polygon(outline(BODY - depth, origin, SUPERSAMPLE), fill=colour)
        depth += step
    frame_rgb = frame_rgb.resize(size, Image.Resampling.BOX)
    # Light from above: the top of the band a little brighter than the bottom.
    light = vertical_gradient(size, (255, 255, 255), (196, 198, 202))
    frame_rgb = ImageChops.multiply(frame_rgb, light)
    body = smooth_mask(lambda d, s: d.polygon(outline(BODY, origin, s), fill=255), size)
    canvas.paste(frame_rgb, (0, 0), body)

    # The glass border: near black, with a faint lighter line where the glass meets the frame.
    glass_edge = smooth_mask(lambda d, s: d.polygon(outline(GLASS, origin, s), fill=255), size)
    canvas.paste((24, 25, 28), (0, 0), glass_edge)
    glass = smooth_mask(lambda d, s: d.polygon(outline(GLASS - 1.2, origin, s), fill=255), size)
    canvas.paste((4, 4, 5), (0, 0), glass)
    return canvas


def framed(frame: Image.Image, raw: Path) -> Image.Image:
    screen = Image.open(raw).convert("RGBA")
    if screen.size != (SCREEN_W, SCREEN_H):
        raise SystemExit(f"{raw}: expected an iPhone 17 screenshot ({SCREEN_W} x {SCREEN_H}), got {screen.size}")
    device = frame.copy()
    device.alpha_composite(screen, (SCREEN_X, SCREEN_Y))
    size = (round(CANVAS_W * SCALE), round(CANVAS_H * SCALE))
    return device.resize(size, Image.Resampling.LANCZOS)


# --- Small files ------------------------------------------------------------------------------------------------------

BANDING_LIMIT = 3       # levels of 255; pngquant's dithered gradients measure about 2 (2026-10-26)

def banding(original: Image.Image, reduced: Image.Image) -> float:
    """How far the reduced image drifts from the original once fine dithering is averaged out, in levels of 255 (the
    99.9th percentile over the image, on a grey background). Banding is a drift over an area, which survives the blur;
    dithering noise does not."""
    def flat(image: Image.Image) -> Image.Image:
        grey = Image.new("RGBA", image.size, (128, 128, 128, 255))
        return Image.alpha_composite(grey, image.convert("RGBA")).convert("RGB").filter(ImageFilter.BoxBlur(4))
    difference = ImageChops.difference(flat(original), flat(reduced)).convert("L")
    histogram = difference.histogram()
    total, seen = sum(histogram), 0
    for level, count in enumerate(histogram):
        seen += count
        if seen >= total * 0.999:
            return float(level)
    return 255.0


def save_small(image: Image.Image, path: Path) -> str:
    """Saves with pngquant when it keeps the gradients smooth, else as a plain optimised PNG. Returns which."""
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    if not Path(PNGQUANT).exists():
        return "png (pngquant not found)"
    with tempfile.TemporaryDirectory() as temp:
        quantised = Path(temp) / "q.png"
        result = subprocess.run([PNGQUANT, "--quality=80-100", "--speed=1", "--strip", "--force",
                                 "--output", str(quantised), str(path)], capture_output=True)
        if result.returncode != 0 or not quantised.exists():
            return "png (pngquant could not reach the quality)"
        drift = banding(image, Image.open(quantised))
        if drift > BANDING_LIMIT:
            return f"png (pngquant drifted {drift:.0f}/255)"
        shutil.copyfile(quantised, path)
    return "pngquant"



# --- Contact sheet ----------------------------------------------------------------------------------------------------

def contact_sheet() -> Path | None:
    """Every image in showcase/, one row per app, on a mid-grey background (shows the shadow and the edges)."""
    rows = [(name, sorted((OUT / name).glob("*.png"))) for name in APPS]
    rows = [(name, files) for name, files in rows if files]
    if not rows:
        return None
    thumb_w = 300
    first = Image.open(rows[0][1][0])
    thumb_h = round(first.height * thumb_w / first.width)
    label_h, gap = 40, 16
    columns = max(len(files) for _, files in rows)
    sheet = Image.new("RGB", (gap + columns * (thumb_w + gap), gap + len(rows) * (label_h + thumb_h + gap)),
                      (150, 152, 156))
    font = ImageFont.load_default()
    for r, (name, files) in enumerate(rows):
        y = gap + r * (label_h + thumb_h + gap)
        label = Image.new("L", (200, 14), 0)
        ImageDraw.Draw(label).text((0, 1), name.upper(), fill=255, font=font)
        label = label.resize((600, 42), Image.Resampling.NEAREST)
        sheet.paste((20, 20, 22), (gap, y), label)
        for c, file in enumerate(files):
            image = Image.open(file).convert("RGBA").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
            sheet.paste(image, (gap + c * (thumb_w + gap), y + label_h), image)
    path = WORK / "contact-sheet.png"
    sheet.save(path, optimize=True)
    return path


# --- README -----------------------------------------------------------------------------------------------------------

FULL_RUN_MINUTES = 6          # measured 2026-10-26 on the MacBook (5.9 min from a clean build folder)

README_TITLES = {"aresium": "Aresium (finance)", "empire": "Empire (the hub)", "arestemis": "Arestemis (flat hunter)",
                 "aresus": "Aresus (watchtower and Aresync)", "arestoteles": "Arestoteles (knowledge vault)"}


def write_readme() -> None:
    """showcase/README.md from the shot table: a table per app with each image and its caption."""
    lines = [
        "# Showcase",
        "",
        "Pictures of the five iPhone apps for display (portfolio, website, sharing). Every screen shows the apps' "
        "made-up sample data (their DEBUG sample mode): no real account, transaction, listing or note.",
        "",
        "Made by `scripts/showcase.py`, which also writes this file; change a shot or caption in its `SHOTS` table.",
        "",
    ]
    for name in APPS:
        shots = [shot for shot in SHOTS if shot.app == name and (OUT / name / f"{shot.name}.png").exists()]
        if not shots:
            continue
        lines += [f"## {README_TITLES[name]}", "", "| Image | What it shows |", "|---|---|"]
        for shot in shots:
            path = f"{name}/{shot.name}.png"
            lines.append(f'| <a href="{path}"><img src="{path}" width="220" alt="{shot.caption}"></a> '
                         f"| **{shot.name}.png**<br>{shot.caption} |")
        lines.append("")
    lines += [
        "## Make them again",
        "",
        "```",
        "python3 scripts/showcase.py               # all five apps",
        "python3 scripts/showcase.py empire        # one app (or several)",
        "```",
        "",
        "Needs the Mac with Xcode 27 and the iOS 27.0 simulator runtime, Python 3 with Pillow, and pngquant "
        f"(`brew install pngquant`). All five apps take about {FULL_RUN_MINUTES} minutes: building, starting the "
        "simulator, then about 8 seconds per shot. The script builds the named apps into `build/showcase/` (git-ignored), "
        "makes its own simulator `claude-showcase` (iPhone 17) and deletes it at the end, so no other simulator is "
        "touched. It launches each app once per shot with its sample arguments in English, draws an iPhone around "
        "the screenshot (drawn by the script, no Apple artwork) and replaces that app's images here. A contact sheet "
        "of all images goes to `build/showcase/contact-sheet.png`.",
        "",
    ]
    (OUT / "README.md").write_text("\n".join(lines))


# --- Main -------------------------------------------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("apps", nargs="*", help="aresium, empire, arestemis, aresus, arestoteles (default: all)")
    parser.add_argument("--skip-build", action="store_true", help="use the apps already built in build/showcase")
    parser.add_argument("--keep-simulator", action="store_true", help="reuse claude-showcase and leave it running")
    options = parser.parse_args()
    names = options.apps or list(APPS)
    unknown = [name for name in names if name not in APPS]
    if unknown:
        parser.error(f"unknown app {', '.join(unknown)}; choose from {', '.join(APPS)}")

    started = time.time()
    WORK.mkdir(parents=True, exist_ok=True)
    say("Drawing the iPhone")
    frame = device_frame()
    say(f"Preparing the simulator {SIMULATOR_NAME}")
    udid = prepare_simulator(options.keep_simulator)
    try:
        for name in names:
            app = APPS[name]
            say(f"{app.folder}")
            path = built_app(app) if options.skip_build else build(app, udid)
            run(["xcrun", "simctl", "install", udid, str(path)], quiet=True)
            shots = [shot for shot in SHOTS if shot.app == name]
            folder = OUT / name
            for old in folder.glob("*.png"):                            # a renamed or dropped shot leaves no file behind
                old.unlink()
            for shot in shots:
                raw = screenshot(udid, shot)
                method = save_small(framed(frame, raw), folder / f"{shot.name}.png")
                size = (folder / f"{shot.name}.png").stat().st_size
                say(f"  {name}/{shot.name}.png  {size / 1024:.0f} KB  {method}")
            run(["xcrun", "simctl", "terminate", udid, app.bundle_id], check=False, quiet=True)
    finally:
        if not options.keep_simulator:
            delete_simulator(udid)
            say(f"Deleted the simulator {SIMULATOR_NAME}")
    write_readme()
    sheet = contact_sheet()
    total = sum(file.stat().st_size for file in OUT.rglob("*.png"))
    say(f"showcase/: {total / 1024 / 1024:.1f} MB in all; contact sheet: {sheet}")
    say(f"Took {(time.time() - started) / 60:.1f} min")


if __name__ == "__main__":
    main()
