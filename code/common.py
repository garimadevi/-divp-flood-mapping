"""Re-export common helpers from preprocessing.common for tools and static analysis."""
from __future__ import annotations

import sys
from pathlib import Path

_prep_dir = str(Path(__file__).resolve().parent / "preprocessing")
if _prep_dir not in sys.path:
    sys.path.insert(0, _prep_dir)

from preprocessing.common import (  # type: ignore[import]
    combine_mosaics,
    get_item,
    load_config,
    load_json,
    project_root,
    read_reprojected,
    rel_path,
    save_json,
    sha256_file,
    sign_item,
    stac_client,
    target_grid,
    utc_now,
    write_geotiff,
)

__all__ = [
    "combine_mosaics",
    "get_item",
    "load_config",
    "load_json",
    "project_root",
    "read_reprojected",
    "rel_path",
    "save_json",
    "sha256_file",
    "sign_item",
    "stac_client",
    "target_grid",
    "utc_now",
    "write_geotiff",
]

