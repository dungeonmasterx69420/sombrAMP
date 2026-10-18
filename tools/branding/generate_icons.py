"""Render every app icon and splash image from the System S S mark.

The mark comes from images/sombra_s_mark.svg (see flatten_marks.py). Icons are the mark in System S ink on
the System S desk colour of the dark theme, which is the default.

    python3 tools/branding/generate_icons.py   # needs: pip install cairosvg pillow
"""

import io
import re
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"

# System S, dark theme.
DESK = "#0A0A0A"
INK = "#EDEDED"

MARK_D = re.search(r' d="([^"]+)"', (ROOT / "images/sombra_s_mark.svg").read_text()).group(1)
_xs = [float(x) for x in re.findall(r"[ML]([\d.]+) ", MARK_D)]
_ys = [float(y) for y in re.findall(r"[ML][\d.]+ ([\d.]+)", MARK_D)]
# The drawn extent of the mark (its viewBox has a little slack on the right and bottom).
MARK_BOX = (min(_xs), min(_ys), max(_xs), max(_ys))


def mark_svg(size, mark_height, color, background=None, tile=False):
    """The mark centred on a size x size canvas, mark_height tall (by its drawn extent)."""
    x0, y0, x1, y1 = MARK_BOX
    scale = mark_height / (y1 - y0)
    tx = size / 2 - (x0 + x1) / 2 * scale
    ty = size / 2 - (y0 + y1) / 2 * scale
    under = ""
    if tile:
        # macOS's icon grid: an 824/1024 rounded square, inset 100/1024.
        inset, side, radius = size * 100 / 1024, size * 824 / 1024, size * 185 / 1024
        under = f'<rect x="{inset}" y="{inset}" width="{side}" height="{side}" rx="{radius}" fill="{DESK}"/>'
    elif background:
        under = f'<rect width="{size}" height="{size}" fill="{background}"/>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">'
        f"{under}"
        f'<path transform="translate({tx:.3f} {ty:.3f}) scale({scale:.5f})" fill="{color}" fill-rule="evenodd" '
        f'd="{MARK_D}"/></svg>'
    )


def render(svg, size):
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def save(image, path, rgb=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    (image.convert("RGB") if rgb else image).save(path, optimize=True)


def full(size):
    """Full-bleed square: what iOS and Android launchers mask into their own shape."""
    return render(mark_svg(1024, 1024 * 0.56, INK, background=DESK), 1024).resize((size, size), Image.LANCZOS)


def tile(size):
    """Rounded tile with transparent margins, for macOS, Linux and Windows."""
    return render(mark_svg(1024, 1024 * 0.46, INK, tile=True), 1024).resize((size, size), Image.LANCZOS)


def adaptive_mark(size, color):
    """The mark inside Android's adaptive-icon safe zone (a 66dp circle in a 108dp square)."""
    return render(mark_svg(size, size * 56 / 108, color), size)


def tv_banner():
    """Android TV's launcher banner: 320x180dp, drawn at xhdpi. The mark and the app's name, in Pixelify Sans."""
    width, height = 640, 360
    banner = Image.new("RGB", (width, height), DESK)
    font = ImageFont.truetype(str(ROOT / "assets/fonts/PixelifySans-Bold.ttf"), 76)
    name = "sombrAMP"
    left, top, right, bottom = font.getbbox(name)
    mark_height = 116
    x0, y0, x1, y1 = MARK_BOX
    mark_width = round(mark_height * (x1 - x0) / (y1 - y0))
    gap = 24
    x = (width - (mark_width + gap + right - left)) // 2
    # The mark is rendered on a square canvas, centred, so it's cropped to its drawn extent.
    square = render(mark_svg(mark_height, mark_height, INK), mark_height)
    mark = square.crop(((mark_height - mark_width) // 2, 0, (mark_height + mark_width) // 2, mark_height))
    banner.paste(mark, (x, (height - mark_height) // 2), mark)
    ImageDraw.Draw(banner).text(
        (x + mark_width + gap - left, (height - (bottom - top)) // 2 - top), name, font=font, fill=INK
    )
    return banner


def main():
    # Sources, also referenced by flutter_launcher_icons / flutter_native_splash / msix in pubspec.yaml.
    save(full(1024), ROOT / "assets/icon/sombra_icon.png", rgb=True)
    save(tile(1024), ROOT / "assets/icon/sombra_icon_tile.png")
    save(adaptive_mark(1024, INK), ROOT / "assets/icon/sombra_icon_foreground.png")
    save(render(mark_svg(1024, 1024 * 0.92, "#FFFFFF"), 1024), ROOT / "assets/icon/sombra_notification.png")
    # Android 12 crops its splash icon to a circle 2/3 of the image wide; this fits the mark inside it.
    save(render(mark_svg(1152, 600, INK), 1152), ROOT / "assets/icon/sombra_splash.png")
    save(render(mark_svg(512, 220, INK), 512), ROOT / "assets/icon/sombra_splash_ios.png")

    # iOS: opaque squares.
    appiconset = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for path in appiconset.glob("Icon-App-*.png"):
        save(full(Image.open(path).size[0]), path, rgb=True)

    # macOS.
    for path in (ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset").glob("app_icon_*.png"):
        save(tile(Image.open(path).size[0]), path)

    # Linux (the icon is installed under the name "finamp", which the .desktop file refers to).
    for path in (ROOT / "assets/icon/linux").glob("*/apps/finamp.png"):
        save(tile(Image.open(path).size[0]), path)

    # Windows.
    sizes = [16, 24, 32, 48, 64, 128, 256]
    tile(256).save(ROOT / "windows/runner/resources/app_icon.ico", sizes=[(s, s) for s in sizes])

    # Android: legacy launcher icons, themed (monochrome) icons and the notification icon.
    for density, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        save(full(round(48 * scale)), RES / f"mipmap-{density}/ic_launcher.png")
        save(adaptive_mark(round(108 * scale), "#FFFFFF"), RES / f"drawable-{density}/ic_launcher_monochrome.png")
        save(render(mark_svg(round(48 * scale), 48 * scale * 0.92, "#FFFFFF"), round(48 * scale)),
             RES / f"mipmap-{density}/white.png")
    save(adaptive_mark(432, "#FFFFFF"), RES / "mipmap-anydpi-v26/ic_launcher_monochrome.png")
    save(tv_banner(), RES / "drawable-xhdpi/tv_banner.png")

    # Android adaptive foreground, as a vector so it stays sharp at every size.
    x0, y0, x1, y1 = MARK_BOX
    scale = 56 / (y1 - y0)
    tx, ty = 54 - (x0 + x1) / 2 * scale, 54 - (y0 + y1) / 2 * scale
    (RES / "drawable-v24/ic_launcher_foreground.xml").write_text(
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp"\n'
        '    android:height="108dp"\n'
        '    android:viewportWidth="108"\n'
        '    android:viewportHeight="108">\n'
        f'    <group\n        android:scaleX="{scale:.6f}"\n        android:scaleY="{scale:.6f}"\n'
        f'        android:translateX="{tx:.4f}"\n        android:translateY="{ty:.4f}">\n'
        f'        <path\n            android:fillColor="{INK}"\n            android:fillType="evenOdd"\n'
        f'            android:pathData="{MARK_D}" />\n'
        "    </group>\n"
        "</vector>\n"
    )
    (RES / "values/colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{DESK}</color>\n</resources>\n'
    )
    print("icons written")


if __name__ == "__main__":
    main()
