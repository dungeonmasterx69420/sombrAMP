"""Flatten the System S marks into plain filled paths.

System S (sombra.wtf) draws the S mark and the sombra.wtf wordmark with SVG masks and 64 / 40 stacked
<use> copies to get the extruded shadow. Flutter's SVG renderer, Android vector drawables and icon
pipelines don't support that construction reliably, so this script computes the same shapes with
shapely and writes them out as single even-odd paths. The geometry constants are copied verbatim from
System S; nothing here changes the design.

    python3 tools/branding/flatten_marks.py   # needs: pip install shapely svgelements

writes images/sombra_s_mark.svg and images/sombra_wordmark.svg (black; tint them at runtime).
"""

from pathlib import Path

from shapely import affinity
from shapely.geometry import LineString, LinearRing, Point, Polygon, box
from shapely.ops import unary_union
from svgelements import Arc, Close, Line, Move, Path as SvgPath

# ---- verbatim from System S ----
S_PATH = "M22.5 3.36L42.5 21.36V42L32.5 50L42.5 58V78.64L22.5 96.64L2.5 78.64V58L12.5 50L2.5 42V21.36z"
S_INNER = "M22.5 21.36V42L32.5 50M12.5 50L22.5 58V78.64"
S_VIEWBOX = (61, 116)
S_STROKE = 5
S_STEPS = 64

WORD_PATH = (
    "M37.92 54.97A15 11 0 1 0 23.5 69A16.5 12 0 1 1 7.64 84.31M66 70a23 23 0 1 0 46 0a23 23 0 1 0 -46 0z"
    "M138 100V66a19 19 0 0 1 38 0V100M176 66a19 19 0 0 1 38 0V100M240 0V100M240 70a23 23 0 1 0 46 0a23 23 0 1 0 -46 0z"
    "M312 100V70a23 23 0 0 1 23 -23H342M358 70a23 23 0 1 0 46 0a23 23 0 1 0 -46 0zM404 40V100M547 14V100M535 47H565"
    "M589 100V21a14 14 0 0 1 14 -14H611M577 47H607"
)
WORD_W = "M451 40L467 100L483 40L499 100L515 40"
WORD_W_CLIP = box(-1000, 40, 2000, 100)
WORD_DOT = (427, 92, 8)
WORD_VIEWBOX = (621, 110)
WORD_STROKE = 14
WORD_MITER = 20
WORD_STEPS = 40
# --------------------------------

ARC_SAMPLES = 192


def subpaths(d):
    """Split an SVG path into (points, closed) polylines, sampling arcs."""
    out, pts = [], []
    for seg in SvgPath(d):
        if isinstance(seg, Move):
            if len(pts) > 1:
                out.append((pts, False))
            pts = [(seg.end.x, seg.end.y)]
        elif isinstance(seg, Close):
            out.append((pts, True))
            pts = []
        elif isinstance(seg, Line):
            pts.append((seg.end.x, seg.end.y))
        elif isinstance(seg, Arc):
            for i in range(1, ARC_SAMPLES + 1):
                p = seg.point(i / ARC_SAMPLES)
                pts.append((p.x, p.y))
        else:
            raise ValueError(f"unexpected segment {seg!r}")
    if len(pts) > 1:
        out.append((pts, False))
    return out


def stroke(d, width, miter):
    parts = []
    for pts, closed in subpaths(d):
        geom = LinearRing(pts) if closed else LineString(pts)
        parts.append(geom.buffer(width / 2, cap_style="flat", join_style="mitre", mitre_limit=miter))
    return unary_union(parts)


def extrude(shape, steps):
    """The stacked-copies shadow: copies offset by (i/4, i/4) for i in 1..steps."""
    return unary_union([affinity.translate(shape, (i + 1) / 4, (i + 1) / 4) for i in range(steps)])


def to_path(geom, precision=2):
    polys = list(geom.geoms) if hasattr(geom, "geoms") else [geom]
    out = []
    for poly in polys:
        if not isinstance(poly, Polygon) or poly.is_empty:
            continue
        for ring in [poly.exterior, *poly.interiors]:
            coords = list(ring.coords)[:-1]
            out.append("M" + "L".join(f"{x:.{precision}f} {y:.{precision}f}" for x, y in coords) + "Z")
    return "".join(out)


def s_mark():
    face = Polygon(subpaths(S_PATH)[0][0])
    lines = unary_union([stroke(S_PATH, S_STROKE, 4), stroke(S_INNER, S_STROKE, 4)])
    shape = unary_union([extrude(face, S_STEPS).difference(face), lines])
    return shape.intersection(box(0, 0, *S_VIEWBOX)).simplify(0.01)


def wordmark():
    letters = stroke(WORD_PATH, WORD_STROKE, WORD_MITER)
    w = stroke(WORD_W, WORD_STROKE, WORD_MITER).intersection(WORD_W_CLIP)
    dot = Point(WORD_DOT[0], WORD_DOT[1]).buffer(WORD_DOT[2], 64)
    face = unary_union([letters, w, dot])
    return extrude(face, WORD_STEPS).difference(face).intersection(box(0, 0, *WORD_VIEWBOX)).simplify(0.02)


def write_svg(path, view_box, d):
    w, h = view_box
    path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">'
        f'<path fill="#000000" fill-rule="evenodd" d="{d}"/></svg>\n'
    )


if __name__ == "__main__":
    images = Path(__file__).resolve().parents[2] / "images"
    write_svg(images / "sombra_s_mark.svg", S_VIEWBOX, to_path(s_mark()))
    write_svg(images / "sombra_wordmark.svg", WORD_VIEWBOX, to_path(wordmark()))
    print(f"wrote {images / 'sombra_s_mark.svg'} and {images / 'sombra_wordmark.svg'}")
