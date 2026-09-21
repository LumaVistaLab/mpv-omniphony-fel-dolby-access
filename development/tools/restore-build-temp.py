"""Restore one retained snapshot to a NEW directory under build_temp.

Usage: python development/tools/restore-build-temp.py ARCHIVE TREE DESTINATION
Generated artifacts omitted by the archive are not restored. Links are recorded
in the manifest but intentionally are not recreated by this tool.
"""

import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import zipfile


def main():
    root = Path(__file__).resolve().parents[2]
    archive_dir = Path(sys.argv[1]).resolve(strict=True)
    tree = PurePosixPath(sys.argv[2])
    destination = Path(sys.argv[3]).resolve()
    permitted = root / "build_temp"
    if permitted.is_symlink() or permitted.is_junction():
        raise ValueError("build_temp must not be a link")
    if destination == permitted or not destination.is_relative_to(permitted):
        raise ValueError("Destination must be a new directory inside build_temp")
    if tree.is_absolute() or ".." in tree.parts:
        raise ValueError("TREE must be a relative path from the archive manifest")
    summary = json.loads((archive_dir / "summary.json").read_text(encoding="utf-8"))
    for name in ("retained-blobs.zip", "build-temp-manifest.jsonl.gz"):
        with (archive_dir / name).open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != summary["artifacts"][name]:
                raise ValueError(f"Archive checksum mismatch: {name}")
    with gzip.open(archive_dir / "build-temp-manifest.jsonl.gz", "rt", encoding="utf-8") as stream:
        rows = [json.loads(line) for line in stream]
    retained = [row for row in rows if row["action"] == "archived"
                and PurePosixPath(row["path"]).is_relative_to(tree)]
    if not retained:
        raise ValueError("No retained files matched TREE")
    # Validate all paths before writing any files.
    for row in retained:
        relative = PurePosixPath(row["path"]).relative_to(tree)
        if relative.is_absolute() or not relative.parts or ".." in relative.parts or ":" in str(relative):
            raise ValueError(f"Unsafe archive path: {row['path']}")
        if not (destination / str(relative)).resolve().is_relative_to(destination):
            raise ValueError(f"Archive path escapes destination: {row['path']}")
    destination.mkdir(parents=True, exist_ok=False)
    with zipfile.ZipFile(archive_dir / "retained-blobs.zip") as archive:
        for row in retained:
            output = destination / str(PurePosixPath(row["path"]).relative_to(tree))
            output.parent.mkdir(parents=True, exist_ok=True)
            with archive.open("blobs/" + row["sha256"]) as source, output.open("xb") as target:
                shutil.copyfileobj(source, target)
            with output.open("rb") as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != row["sha256"]:
                    raise ValueError(f"Restored file checksum mismatch: {output}")
            os.utime(output, ns=(row["mtime_ns"], row["mtime_ns"]))
    print(f"Restored and verified {len(retained)} retained files to {destination}")


if __name__ == "__main__":
    main()
