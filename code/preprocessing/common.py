"""Shared helpers for the Day 2 data pipeline.

All reads are windowed COG reads over the AOI; no full scenes are downloaded.
"""

from __future__ import annotations

import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import planetary_computer
import rasterio
import yaml
from pystac_client import Client
from rasterio.enums import Resampling
from rasterio.transform import from_origin
from rasterio.warp import array_bounds, reproject, transform_bounds
from rasterio.windows import Window, from_bounds


def project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def load_config() -> dict:
    root = project_root()
    with open(root / "code" / "config" / "config.yaml", encoding="utf-8") as handle:
        cfg = yaml.safe_load(handle)
    cfg["_root"] = str(root)
    return cfg


def rel_path(cfg: dict, key: str) -> Path:
    return Path(cfg["_root"]) / cfg["paths"][key]


def stac_client(cfg: dict) -> Client:
    return Client.open(cfg["stac"]["api"])


def get_item(client: Client, collection: str, item_id: str):
    result = client.search(
        collections=[collection], ids=[item_id], max_items=2
    ).item_collection()
    if len(result) == 0:
        raise KeyError(f"STAC item not found: {collection} / {item_id}")
    return result[0]


def sign_item(item):
    return planetary_computer.sign(item)


def target_grid(cfg: dict):
    """Build the common EPSG:32646 10 m grid covering the AOI."""
    bbox = cfg["aoi"]["bbox"]
    dst_crs = rasterio.crs.CRS.from_string(cfg["grid"]["crs"])
    res = float(cfg["grid"]["resolution_m"])

    minx, miny, maxx, maxy = transform_bounds(
        "EPSG:4326", dst_crs, bbox[0], bbox[1], bbox[2], bbox[3], densify_pts=21
    )
    minx = math.floor(minx / res) * res
    miny = math.floor(miny / res) * res
    maxx = math.ceil(maxx / res) * res
    maxy = math.ceil(maxy / res) * res

    width = int(round((maxx - minx) / res))
    height = int(round((maxy - miny) / res))
    transform = from_origin(minx, maxy, res, res)
    return transform, width, height, dst_crs


def read_reprojected(
    href: str,
    dst_crs,
    dst_transform,
    width: int,
    height: int,
    resampling: Resampling,
    dst_nodata=None,
):
    """Read only the source window covering the destination grid, then warp it."""
    env = rasterio.Env(
        GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
        CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif,.tiff",
        GDAL_HTTP_MAX_RETRY="5",
        GDAL_HTTP_RETRY_DELAY="2",
        VSI_CACHE="TRUE",
    )
    with env, rasterio.open(href) as src:
        if src.crs is None:
            raise ValueError(f"Source has no CRS: {href}")
        dst_bounds = array_bounds(height, width, dst_transform)
        src_bounds = transform_bounds(
            dst_crs, src.crs, *dst_bounds, densify_pts=21
        )
        window = from_bounds(*src_bounds, transform=src.transform)
        window = window.round_offsets().round_lengths()
        full = Window(0, 0, src.width, src.height)
        window = window.intersection(full)
        if window.width <= 0 or window.height <= 0:
            return None

        data = src.read(1, window=window)
        src_transform = src.window_transform(window)
        src_nodata = src.nodata
        if dst_nodata is None:
            dst_nodata = src_nodata if src_nodata is not None else 0
        dst = np.full((height, width), dst_nodata, dtype=data.dtype)
        reproject(
            source=data,
            destination=dst,
            src_transform=src_transform,
            src_crs=src.crs,
            src_nodata=src_nodata,
            dst_transform=dst_transform,
            dst_crs=dst_crs,
            dst_nodata=dst_nodata,
            resampling=resampling,
        )
        return dst


def combine_mosaics(arrays, nodata):
    """Combine tiles into one array, preferring valid (non-nodata) values."""
    if not arrays:
        raise ValueError("No arrays to combine")
    out = arrays[0].copy()
    for arr in arrays[1:]:
        valid = arr != nodata
        out[valid] = arr[valid]
    return out


def write_geotiff(path: Path, data: np.ndarray, transform, crs, nodata):
    path.parent.mkdir(parents=True, exist_ok=True)
    profile = {
        "driver": "GTiff",
        "height": data.shape[0],
        "width": data.shape[1],
        "count": 1,
        "dtype": data.dtype.name,
        "crs": crs,
        "transform": transform,
        "nodata": nodata,
        "compress": "deflate",
        "tiled": True,
        "blockxsize": 256,
        "blockysize": 256,
        "BIGTIFF": "IF_SAFER",
    }
    with rasterio.open(path, "w", **profile) as dst:
        dst.write(data, 1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
