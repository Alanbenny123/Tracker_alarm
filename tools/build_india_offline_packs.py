#!/usr/bin/env python3
"""Download OSM state extracts and build separate app offline packs.

The generated ZIPs stay in the ignored offline-packs/builds directory. They
must be uploaded as static HTTPS assets before the app can offer downloads.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import urlparse


REGIONS = (
    ("andaman-and-nicobar-islands", "Andaman and Nicobar Islands", "andaman_and_nicobar_islands", "territory"),
    ("andhra-pradesh", "Andhra Pradesh", "andhra_pradesh", "state"),
    ("arunachal-pradesh", "Arunachal Pradesh", "arunachal_pradesh", "state"),
    ("assam", "Assam", "assam", "state"),
    ("bihar", "Bihar", "bihar", "state"),
    ("chandigarh", "Chandigarh", "chandigarh", "territory"),
    ("chhattisgarh", "Chhattisgarh", "chhattisgarh", "state"),
    ("dadra-nagar-haveli-daman-diu", "Dadra and Nagar Haveli and Daman and Diu", "dadra_and_nagar_haveli_and_daman_and_diu", "territory"),
    ("delhi", "Delhi", "national_capital_territory_of_delhi", "territory"),
    ("goa", "Goa", "goa", "state"),
    ("gujarat", "Gujarat", "gujarat", "state"),
    ("haryana", "Haryana", "haryana", "state"),
    ("himachal-pradesh", "Himachal Pradesh", "himachal_pradesh", "state"),
    ("jammu-and-kashmir", "Jammu and Kashmir", "jammu_and_kashmir", "territory"),
    ("jharkhand", "Jharkhand", "jharkhand", "state"),
    ("karnataka", "Karnataka", "karnataka", "state"),
    ("kerala", "Kerala", "kerala", "state"),
    ("ladakh", "Ladakh", "ladakh", "territory"),
    ("lakshadweep", "Lakshadweep", "lakshadweep", "territory"),
    ("madhya-pradesh", "Madhya Pradesh", "madhya_pradesh", "state"),
    ("maharashtra", "Maharashtra", "maharashtra", "state"),
    ("manipur", "Manipur", "manipur", "state"),
    ("meghalaya", "Meghalaya", "meghalaya", "state"),
    ("mizoram", "Mizoram", "mizoram", "state"),
    ("nagaland", "Nagaland", "nagaland", "state"),
    ("odisha", "Odisha", "odisha", "state"),
    ("puducherry", "Puducherry", "puducherry", "territory"),
    ("punjab", "Punjab", "punjab", "state"),
    ("rajasthan", "Rajasthan", "rajasthan", "state"),
    ("sikkim", "Sikkim", "sikkim", "state"),
    ("tamil-nadu", "Tamil Nadu", "tamil_nadu", "state"),
    ("telangana", "Telangana", "telangana", "state"),
    ("tripura", "Tripura", "tripura", "state"),
    ("uttar-pradesh", "Uttar Pradesh", "uttar_pradesh", "state"),
    ("uttarakhand", "Uttarakhand", "uttarakhand", "state"),
    ("west-bengal", "West Bengal", "west_bengal", "state"),
)
BASE_URL = "https://download.openstreetmap.fr/extracts/asia/india"
ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "offline-packs" / "sources"
BUILDS = ROOT / "offline-packs" / "builds"


def curl(url, output, resume=True):
    command = ["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3",
               "--connect-timeout", "30"]
    if resume:
        command += ["--continue-at", "-"]
    command += ["--output", str(output), url]
    result = subprocess.run(
        command,
        capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError(f"Could not download {url}: {result.stderr.strip()}")


def md5(path):
    digest = hashlib.md5()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(region):
    _, name, slug, _ = region
    SOURCES.mkdir(parents=True, exist_ok=True)
    source = SOURCES / f"{slug}.osm.pbf"
    checksum_file = SOURCES / f"{slug}.osm.pbf.md5"
    polygon_file = SOURCES / f"{slug}.poly"
    curl(f"https://download.openstreetmap.fr/polygons/asia/india/{slug}.poly",
         polygon_file, resume=False)
    if polygon_file.stat().st_size < 20:
        raise RuntimeError(f"Invalid polygon for {name}")
    curl(f"{BASE_URL}/{slug}.osm.pbf.md5", checksum_file, resume=False)
    checksum = re.search(r"\b[0-9a-fA-F]{32}\b", checksum_file.read_text())
    if not checksum:
        raise RuntimeError(f"No MD5 digest for {name}")
    expected = checksum.group(0).lower()
    if source.exists() and md5(source) == expected:
        print(f"Verified cached source: {name}", flush=True)
        return source
    if source.exists() and source.stat().st_size and source.stat().st_size < 1024 * 1024:
        source.unlink()
    print(f"Downloading {name}...", flush=True)
    curl(f"{BASE_URL}/{slug}-latest.osm.pbf", source)
    if md5(source) != expected:
        source.unlink(missing_ok=True)
        raise RuntimeError(f"Checksum mismatch for {name}; source may have changed during download")
    print(f"Downloaded and verified {name}: {source.stat().st_size} bytes", flush=True)
    return source


def valid_pack(path, region_id, require_coverage=True):
    if not path.exists():
        return False
    try:
        with zipfile.ZipFile(path) as archive:
            if archive.testzip() is not None:
                return False
            metadata = json.loads(archive.read("pack.json"))
            return (metadata.get("id") == region_id and metadata.get("placeCount", 0) > 0
                    and (not require_coverage or metadata.get("coverage"))
                    and archive.getinfo("places.json").file_size <= 100 * 1024 * 1024)
    except (KeyError, OSError, ValueError, zipfile.BadZipFile):
        return False


def build(region, tile_budget):
    region_id, name, slug, _ = region
    BUILDS.mkdir(parents=True, exist_ok=True)
    output = BUILDS / f"{region_id}-20261027.zip"
    if valid_pack(output, region_id):
        print(f"Using existing validated pack: {name}", flush=True)
        return output
    source = SOURCES / f"{slug}.osm.pbf"
    polygon = SOURCES / f"{slug}.poly"
    if not source.exists():
        raise RuntimeError(f"Missing PBF for {name}")
    if not polygon.exists():
        raise RuntimeError(f"Missing polygon for {name}")
    partial = BUILDS / f".{region_id}.partial.zip"
    partial.unlink(missing_ok=True)
    command = [
        sys.executable, str(ROOT / "tools" / "build_osm_offline_pack.py"),
        "--pbf", str(source), "--output", str(partial),
        "--polygon", str(polygon),
        "--id", region_id, "--name", name,
        "--address-label", f"{name}, India",
        "--min-zoom", "7", "--max-zoom", "14", "--map-max-zoom", "14",
        "--tile-budget", str(tile_budget),
    ]
    print(f"Building {name}...", flush=True)
    subprocess.run(command, check=True)
    if not valid_pack(partial, region_id):
        raise RuntimeError(f"Built pack failed validation: {name}")
    partial.replace(output)
    print(f"Built and validated {name}: {output.stat().st_size} bytes", flush=True)
    return output


def write_manifest(regions):
    rows = []
    for region_id, name, slug, kind in regions:
        path = BUILDS / f"{region_id}-20261027.zip"
        if not valid_pack(path, region_id):
            continue
        with zipfile.ZipFile(path) as archive:
            metadata = json.loads(archive.read("pack.json"))
        rows.append({"id": region_id, "name": name, "kind": kind,
                     "file": path.name, "bytes": path.stat().st_size,
                     "sha256": sha256(path),
                     "sourceUrl": f"{BASE_URL}/{slug}-latest.osm.pbf",
                     "places": metadata["placeCount"],
                     "tileMaxZoom": metadata.get("tileMaxZoom", metadata["maxZoom"])})
    manifest = {"schema": 1, "built": len(rows), "expected": len(REGIONS), "packs": rows}
    (BUILDS / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Completed {len(rows)}/{len(REGIONS)} regions", flush=True)


def write_catalog(base_url):
    parsed = urlparse(base_url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.query or parsed.fragment:
        raise ValueError("Catalog asset base URL must be a public HTTPS directory URL")
    listings = []
    for region_id, name, _, _ in REGIONS:
        path = BUILDS / f"{region_id}-20261027.zip"
        if not valid_pack(path, region_id):
            raise RuntimeError(f"Missing or invalid ZIP for {name}")
        listings.append({"id": region_id, "name": name,
                         "url": f"{base_url.rstrip('/')}/{path.name}"})
    output = BUILDS / "catalog-to-publish.json"
    output.write_text(json.dumps({"schema": 1, "packs": listings}, indent=2) + "\n")
    print(f"Wrote {len(listings)} catalog entries to {output}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("download", "build", "manifest", "catalog"))
    parser.add_argument("--region", help="Region id, or omit for all regions")
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--tile-budget", type=int, default=20000)
    parser.add_argument("--base-url", help="Public HTTPS release asset directory for catalog")
    args = parser.parse_args()
    regions = [region for region in REGIONS if not args.region or region[0] == args.region]
    if not regions:
        parser.error("Unknown region id")
    if args.phase == "download":
        with ThreadPoolExecutor(max_workers=max(1, min(args.jobs, 4))) as pool:
            futures = {pool.submit(download, region): region for region in regions}
            failures = []
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as error:
                    failures.append((futures[future][1], str(error)))
                    print(f"FAILED {futures[future][1]}: {error}", file=sys.stderr, flush=True)
            if failures:
                raise RuntimeError(f"{len(failures)} source downloads failed")
    elif args.phase == "build":
        failures = []
        with ThreadPoolExecutor(max_workers=max(1, min(args.jobs, 2))) as pool:
            futures = {pool.submit(build, region, args.tile_budget): region for region in regions}
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as error:
                    failures.append((futures[future][1], str(error)))
                    print(f"FAILED {futures[future][1]}: {error}", file=sys.stderr, flush=True)
        write_manifest(regions)
        if failures:
            raise RuntimeError(f"{len(failures)} pack builds failed")
    elif args.phase == "manifest":
        write_manifest(REGIONS)
    else:
        if not args.base_url:
            parser.error("catalog requires --base-url")
        write_catalog(args.base_url)


if __name__ == "__main__":
    main()
