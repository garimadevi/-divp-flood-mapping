"""Resolve the Day 2 STAC items and write data/manifest.json.

This script only reads STAC metadata. It does not download pixels.
Run fetch_subsets.py next to create the local AOI subsets.
"""

from __future__ import annotations

import sys
from pathlib import Path

from common import (
    get_item,
    load_config,
    rel_path,
    save_json,
    stac_client,
    utc_now,
)

PROPERTY_KEYS = {
    "datetime",
    "platform",
    "constellation",
    "instruments",
    "sar:instrument_mode",
    "sar:frequency_band",
    "sar:polarizations",
    "sar:product_type",
    "sat:orbit_state",
    "sat:relative_orbit",
    "s2:mgrs_tile",
    "eo:cloud_cover",
    "proj:epsg",
    "proj:shape",
    "gsd",
}


def item_record(item) -> dict:
    properties = {
        key: item.properties.get(key)
        for key in PROPERTY_KEYS
        if key in item.properties
    }
    assets = {}
    for name, asset in item.assets.items():
        assets[name] = {
            "href": asset.href,
            "media_type": asset.media_type,
            "roles": asset.roles,
            "title": asset.title,
        }
    return {
        "collection": item.collection_id,
        "item_id": item.id,
        "datetime": item.datetime.isoformat() if item.datetime else None,
        "bbox": item.bbox,
        "properties": properties,
        "assets": assets,
    }


def resolve(client, collection: str, item_id: str) -> dict:
    item = get_item(client, collection, item_id)
    record = item_record(item)
    print(f"  OK  {collection} / {item_id}")
    return record


def main() -> int:
    cfg = load_config()
    client = stac_client(cfg)
    collections = cfg["stac"]["collections"]
    items = cfg["items"]

    datasets: dict[str, dict] = {}

    print("Resolving STAC items:")
    datasets["s1_rtc_pre"] = resolve(
        client, collections["s1_rtc"], items["s1_rtc_pre"]
    )
    datasets["s1_rtc_post"] = resolve(
        client, collections["s1_rtc"], items["s1_rtc_post"]
    )

    for index, tile_id in enumerate(items["s2_post_tiles"]):
        datasets[f"s2_post_tile_{index + 1}"] = resolve(
            client, collections["s2_l2a"], tile_id
        )

    datasets["dem"] = resolve(client, collections["dem"], items["dem"])
    datasets["jrc_water"] = resolve(
        client, collections["jrc_water"], items["jrc_water"]
    )
    datasets["worldcover"] = resolve(
        client, collections["worldcover"], items["worldcover"]
    )

    manifest = {
        "generated_utc": utc_now(),
        "status": "metadata-only",
        "note": (
            "Asset hrefs are unsigned and expire after signing. "
            "fetch_subsets.py re-resolves each item and signs it at fetch time."
        ),
        "stac_api": cfg["stac"]["api"],
        "aoi": {
            "name": cfg["aoi"]["name"],
            "bbox_wgs84": cfg["aoi"]["bbox"],
        },
        "grid": {
            "crs": cfg["grid"]["crs"],
            "resolution_m": cfg["grid"]["resolution_m"],
        },
        "event": cfg["event"],
        "collections": collections,
        "assets": cfg["stac"]["assets"],
        "datasets": datasets,
        "local_files": {},
    }

    out = rel_path(cfg, "manifest")
    save_json(out, manifest)
    print(f"\nWrote {out}")
    print(f"Resolved {len(datasets)} dataset entries.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
