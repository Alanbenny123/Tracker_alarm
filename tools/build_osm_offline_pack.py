#!/usr/bin/env python3
"""Build the app's offline ZIP from a licensed OSM PBF extract.

Requires pyosmium and Pillow. This renders a compact schematic road map;
it does not fetch tiles from any public tile server.
"""

import argparse
import json
import math
import os
import sqlite3
import struct
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import osmium
from PIL import Image, ImageDraw, ImageFont


def load_osm_polygon(path):
    from shapely.geometry import Polygon
    from shapely.ops import unary_union

    outer = []
    holes = []
    ring = []
    is_hole = False
    lines = iter(path.read_text(encoding="utf-8").splitlines())
    next(lines, None)  # OSM poly file title.
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        if line == "END":
            if ring:
                (holes if is_hole else outer).append(Polygon(ring))
                ring = []
            else:
                break
        elif len(line.split()) == 2:
            lon, lat = map(float, line.split())
            ring.append((lon, lat))
        else:
            is_hole = line.startswith("!")
    if not outer:
        raise ValueError(f"No outer rings in {path}")
    polygon = unary_union(outer)
    if holes:
        polygon = polygon.difference(unary_union(holes))
    if not polygon.is_valid:
        polygon = polygon.buffer(0)
    return polygon


ROAD_MAJOR = {"motorway", "trunk", "primary", "motorway_link", "trunk_link", "primary_link"}
ROAD_MIDDLE = {"secondary", "tertiary", "secondary_link", "tertiary_link"}
ROAD_MINOR = {"residential", "unclassified", "living_street", "service", "road"}
ROAD_PATH = {"pedestrian", "footway", "cycleway", "path", "steps", "track"}
STATION_TAGS = {"station", "halt", "tram_stop", "subway_entrance"}


def tile_xy(lat, lon, zoom):
    lat = max(-85.05112878, min(85.05112878, lat))
    scale = 2 ** zoom
    x = (lon + 180.0) / 360.0 * scale
    y = (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * scale
    return x, y


def tile_bounds(x, y, zoom):
    n = 2 ** zoom
    west = x / n * 360.0 - 180.0
    east = (x + 1) / n * 360.0 - 180.0
    north = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
    south = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + 1) / n))))
    return south, west, north, east


def category(tags):
    highway = tags.get("highway", "")
    railway = tags.get("railway", "")
    public_transport = tags.get("public_transport", "")
    if highway == "bus_stop" or tags.get("bus") == "yes" or tags.get("bus_bay"):
        return "bus"
    if railway in STATION_TAGS or public_transport in {"station", "platform", "stop_position"}:
        if (
            tags.get("station") == "subway"
            or tags.get("subway") == "yes"
            or railway == "subway_entrance"
            or "metro" in tags.get("network", "").lower()
            or "metro" in tags.get("name", "").lower()
        ):
            return "metro"
        if railway in STATION_TAGS or tags.get("train") == "yes":
            return "railway"
        if tags.get("bus") == "yes":
            return "bus"
    if any(tags.get(key) for key in ("shop", "amenity", "tourism", "historic", "place", "leisure", "natural")):
        return "other"
    return None


def line_style(tags):
    highway = tags.get("highway")
    if highway in ROAD_MAJOR:
        return 0
    if highway in ROAD_MIDDLE:
        return 1
    if highway in ROAD_MINOR:
        return 2
    if highway in ROAD_PATH:
        return 3
    if tags.get("railway") in {"rail", "subway", "light_rail", "tram"}:
        return 4
    if tags.get("waterway") in {"river", "canal", "stream", "drain"}:
        return 5
    return None


class PackCollector(osmium.SimpleHandler):
    def __init__(self, db, bounds, address_label, coverage=None):
        super().__init__()
        self.db = db
        self.bounds = bounds
        self.address_label = address_label
        if coverage is not None:
            from shapely.prepared import prep
            self.coverage = prep(coverage)
        else:
            self.coverage = None
        self.place_count = 0
        self.line_count = 0
        self.counts = {key: 0 for key in ("bus", "metro", "railway", "other")}
        self.places_file = None
        self.first_place = True
        self.observed_south = math.inf
        self.observed_west = math.inf
        self.observed_north = -math.inf
        self.observed_east = -math.inf

    def observed_bounds(self):
        if not math.isfinite(self.observed_south):
            raise RuntimeError("PBF has no located nodes")
        padding = 0.01
        return (self.observed_south - padding, self.observed_west - padding,
                self.observed_north + padding, self.observed_east + padding)

    def begin_places(self, path):
        self.places_file = open(path, "w", encoding="utf-8")
        self.places_file.write("[")

    def finish_places(self):
        self.places_file.write("]")
        self.places_file.close()

    def _inside(self, lat, lon):
        if self.bounds is None:
            in_bounds = True
        else:
            south, west, north, east = self.bounds
            in_bounds = south <= lat <= north and west <= lon <= east
        if not in_bounds:
            return False
        if self.coverage is not None:
            from shapely.geometry import Point
            return self.coverage.covers(Point(lon, lat))
        return True

    def _place(self, kind, obj_id, tags, lat, lon):
        name = tags.get("name:en") or tags.get("name")
        if not name:
            return
        typ = category(tags)
        if typ is None:
            return
        if not self._inside(lat, lon):
            return
        address = ", ".join(
            value for value in (tags.get("addr:street"), tags.get("addr:city")) if value
        ) or self.address_label
        place = {
            "id": f"{kind}{obj_id}",
            "name": name[:200],
            "address": address[:250],
            "latitude": round(lat, 7),
            "longitude": round(lon, 7),
            "type": typ,
        }
        if not self.first_place:
            self.places_file.write(",")
        self.places_file.write(json.dumps(place, ensure_ascii=False, separators=(",", ":")))
        self.first_place = False
        self.place_count += 1
        self.counts[typ] += 1
        if typ in {"metro", "railway"} or tags.get("place") in {"city", "town", "village", "suburb"}:
            self.db.execute(
                "INSERT INTO labels(name,lat,lon,kind) VALUES(?,?,?,?)",
                (name[:100], lat, lon, typ if typ != "other" else "town"),
            )

    def node(self, node):
        if node.location.valid() and self.bounds is None:
            self.observed_south = min(self.observed_south, node.location.lat)
            self.observed_west = min(self.observed_west, node.location.lon)
            self.observed_north = max(self.observed_north, node.location.lat)
            self.observed_east = max(self.observed_east, node.location.lon)
        if node.location.valid() and (node.tags.get("name") or node.tags.get("name:en")):
            self._place("n", node.id, node.tags, node.location.lat, node.location.lon)

    def way(self, way):
        style = line_style(way.tags)
        typ = category(way.tags) if way.tags.get("name") else None
        if style is None and typ is None:
            return
        points = [
            (node.location.lon, node.location.lat)
            for node in way.nodes
            if node.location.valid()
        ]
        if not points:
            return
        if typ:
            # Center of the geometry is sufficient for search results.
            lat = sum(p[1] for p in points) / len(points)
            lon = sum(p[0] for p in points) / len(points)
            self._place("w", way.id, way.tags, lat, lon)
        if style is None or len(points) < 2:
            return
        lons, lats = zip(*points)
        min_lon, max_lon = min(lons), max(lons)
        min_lat, max_lat = min(lats), max(lats)
        if self.bounds is not None:
            south, west, north, east = self.bounds
            if min_lon > east or max_lon < west or min_lat > north or max_lat < south:
                return
        geom = struct.pack(f"<{len(points) * 2}f", *(n for pair in points for n in pair))
        cursor = self.db.execute(
            "INSERT INTO lines(style,geom) VALUES(?,?)", (style, geom)
        )
        self.db.execute(
            "INSERT INTO line_index VALUES(?,?,?,?,?)",
            (cursor.lastrowid, min_lon, max_lon, min_lat, max_lat),
        )
        self.line_count += 1


def create_db(path):
    db = sqlite3.connect(path)
    db.executescript(
        """
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        CREATE TABLE lines(id INTEGER PRIMARY KEY, style INTEGER NOT NULL, geom BLOB NOT NULL);
        CREATE VIRTUAL TABLE line_index USING rtree(id,min_lon,max_lon,min_lat,max_lat);
        CREATE TABLE labels(name TEXT, lat REAL, lon REAL, kind TEXT);
        CREATE INDEX labels_lat_lon ON labels(lat,lon);
        """
    )
    return db


def render_tile(db, x, y, zoom, font):
    south, west, north, east = tile_bounds(x, y, zoom)
    image = Image.new("RGB", (256, 256), "#0c1013")
    draw = ImageDraw.Draw(image)
    styles = {
        0: ("#cfd7dc", 3 if zoom >= 11 else 2),
        1: ("#aebbc1", 2 if zoom >= 11 else 1),
        2: ("#69787f", 1),
        3: ("#344249", 1),
        4: ("#d7d0a7", 2),
        5: ("#3c6680", 2),
    }
    max_road = 0 if zoom <= 8 else 1 if zoom <= 10 else 2 if zoom <= 11 else 3
    rows = db.execute(
        """SELECT lines.style,lines.geom FROM line_index
        JOIN lines ON lines.id=line_index.id
        WHERE min_lon<=? AND max_lon>=? AND min_lat<=? AND max_lat>=?
        AND (lines.style<=? OR lines.style IN (4,5))""",
        (east, west, north, south, max_road),
    )
    groups = [[] for _ in range(6)]
    for style, geom in rows:
        groups[style].append(geom)
    for style in (5, 3, 2, 1, 0, 4):
        color, width = styles[style]
        for geom in groups[style]:
            values = struct.unpack(f"<{len(geom) // 4}f", geom)
            pixels = []
            for lon, lat in zip(values[::2], values[1::2]):
                px, py = tile_xy(lat, lon, zoom)
                pixels.append(((px - x) * 256, (py - y) * 256))
            if len(pixels) > 1:
                draw.line(pixels, fill=color, width=width, joint="curve")
    if zoom >= 9:
        kinds = ("town", "metro", "railway") if zoom < 12 else ("metro", "railway", "town")
        labels = db.execute(
            "SELECT name,lat,lon,kind FROM labels WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
            (south, north, west, east),
        )
        used = []
        count = 0
        for name, lat, lon, kind in labels:
            if kind not in kinds or (zoom < 11 and kind != "town"):
                continue
            px, py = tile_xy(lat, lon, zoom)
            px, py = (px - x) * 256, (py - y) * 256
            if any(abs(px - old_x) < 75 and abs(py - old_y) < 15 for old_x, old_y in used):
                continue
            used.append((px, py))
            draw.ellipse((px - 2, py - 2, px + 2, py + 2), fill="#ffffff")
            draw.text((px + 4, py - 8), name[:24], fill="#ffffff", font=font,
                      stroke_width=1, stroke_fill="#0c1013")
            count += 1
            if count >= 12:
                break
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pbf", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--id", default="kerala")
    parser.add_argument("--name", default="Kerala")
    parser.add_argument("--address-label", default="Kerala, India")
    parser.add_argument("--polygon", type=Path,
                        help="OSM .poly boundary; filters places and sets exact region bounds")
    parser.add_argument("--bounds", nargs=4, type=float, metavar=("SOUTH", "WEST", "NORTH", "EAST"),
                        help="Defaults to the PBF's observed node bounds")
    parser.add_argument("--min-zoom", type=int, default=7)
    parser.add_argument("--max-zoom", type=int, default=13,
                        help="Highest rendered tile zoom")
    parser.add_argument("--map-max-zoom", type=int, default=14,
                        help="Maximum user zoom, including overzoom")
    parser.add_argument("--tile-budget", type=int, default=40000,
                        help="Reduce rendered zoom until tile count fits this budget")
    args = parser.parse_args()
    if args.min_zoom < 0 or args.max_zoom > 15 or args.min_zoom > args.max_zoom or args.map_max_zoom < args.max_zoom or args.map_max_zoom > 18:
        parser.error("Zoom must be in 0..18 with min <= rendered max <= map max")
    if args.tile_budget < 1 or args.tile_budget > 250000:
        parser.error("Tile budget must be in 1..250000")
    if not args.pbf.is_file():
        parser.error("PBF file does not exist")
    if args.polygon and not args.polygon.is_file():
        parser.error("Polygon file does not exist")
    coverage = load_osm_polygon(args.polygon) if args.polygon else None
    if coverage is not None and args.bounds is None:
        west, south, east, north = coverage.bounds
        args.bounds = (south - 0.01, west - 0.01, north + 0.01, east + 0.01)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="offline-pack-") as temp:
        temp_path = Path(temp)
        db = create_db(temp_path / "features.sqlite")
        collector = PackCollector(db, args.bounds, args.address_label, coverage)
        collector.begin_places(temp_path / "places.json")
        print("Reading PBF and extracting places/roads...", flush=True)
        collector.apply_file(str(args.pbf), locations=True, idx="flex_mem")
        collector.finish_places()
        db.commit()
        print(f"Found {collector.place_count} named places and {collector.line_count} map lines", flush=True)
        if collector.place_count == 0 or collector.line_count == 0:
            raise RuntimeError("PBF contains no usable map/place data for these bounds")
        south, west, north, east = args.bounds or collector.observed_bounds()
        if south >= north or west >= east:
            raise RuntimeError("Invalid region bounds")
        def tile_count_through(max_zoom):
            count = 0
            for zoom in range(args.min_zoom, max_zoom + 1):
                x0 = math.floor(tile_xy(0, west, zoom)[0])
                x1 = math.floor(tile_xy(0, east, zoom)[0])
                y0 = math.floor(tile_xy(north, 0, zoom)[1])
                y1 = math.floor(tile_xy(south, 0, zoom)[1])
                count += (x1 - x0 + 1) * (y1 - y0 + 1)
            return count
        render_max_zoom = args.max_zoom
        while render_max_zoom > args.min_zoom and tile_count_through(render_max_zoom) > args.tile_budget:
            render_max_zoom -= 1
        if tile_count_through(render_max_zoom) > args.tile_budget:
            raise RuntimeError("Region is too large even at minimum zoom; split it into smaller packs")
        metadata = {
            "schema": 1, "id": args.id, "name": args.name,
            "bounds": {"south": south, "west": west, "north": north, "east": east},
            "minZoom": args.min_zoom, "maxZoom": args.map_max_zoom,
            "tileMaxZoom": render_max_zoom,
            "placeCount": collector.place_count,
            "source": "OpenStreetMap contributors, ODbL 1.0",
            "generatedAt": datetime.now(timezone.utc).isoformat(),
        }
        if coverage is not None:
            from shapely.geometry import mapping
            metadata["coverage"] = mapping(coverage.simplify(0.0005, preserve_topology=True))
        (temp_path / "pack.json").write_text(json.dumps(metadata, separators=(",", ":")), encoding="utf-8")
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        font = ImageFont.truetype(font_path, 10) if os.path.exists(font_path) else ImageFont.load_default()
        tile_count = 0
        with zipfile.ZipFile(args.output, "w", allowZip64=True) as archive:
            archive.write(temp_path / "pack.json", "pack.json", compress_type=zipfile.ZIP_DEFLATED)
            archive.write(temp_path / "places.json", "places.json", compress_type=zipfile.ZIP_DEFLATED)
            for zoom in range(args.min_zoom, render_max_zoom + 1):
                x0 = math.floor(tile_xy(0, west, zoom)[0])
                x1 = math.floor(tile_xy(0, east, zoom)[0])
                y0 = math.floor(tile_xy(north, 0, zoom)[1])
                y1 = math.floor(tile_xy(south, 0, zoom)[1])
                print(f"Rendering zoom {zoom}: {(x1-x0+1)*(y1-y0+1)} tiles", flush=True)
                for x in range(x0, x1 + 1):
                    for y in range(y0, y1 + 1):
                        image = render_tile(db, x, y, zoom, font)
                        tile_path = temp_path / "tile.png"
                        image.save(tile_path, format="PNG", optimize=True)
                        archive.write(tile_path, f"tiles/{zoom}/{x}/{y}.png", compress_type=zipfile.ZIP_STORED)
                        tile_count += 1
        db.close()
    print(json.dumps({"output": str(args.output), "places": collector.place_count,
                      "types": collector.counts, "tiles": tile_count,
                      "bytes": args.output.stat().st_size}, indent=2), flush=True)


if __name__ == "__main__":
    main()
