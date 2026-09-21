"""Archive build_temp provenance without deleting files or following links.

Usage: python development/tools/archive-build-temp.py <new-archive-directory>
The destination must be under distribution/build-temp-cleanup/.
"""

import collections
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
TEMP = ROOT / "build_temp"
REPARSE = stat.FILE_ATTRIBUTE_REPARSE_POINT


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def walk(path):
    # Do not traverse junctions or symlinks, even when they lead within the tree.
    for item in sorted(path.iterdir(), key=lambda p: p.name.lower()):
        info = item.lstat()
        yield item, info
        if stat.S_ISDIR(info.st_mode) and not info.st_file_attributes & REPARSE:
            yield from walk(item)


def retention(relative, size):
    parts = relative.parts
    name = relative.name.lower()
    if parts[0] == "msys64":
        return relative.as_posix().startswith((
            "msys64/var/lib/pacman/local/", "msys64/etc/", "msys64/var/log/"
        ))
    if parts[0] == "rust":
        return name.endswith(".crate") or name in {
            "settings.toml", "config.toml", "channel-rust-stable.toml",
            "multirust-channel-manifest.toml", "rust-installer-version",
        } or "update-hashes" in parts
    if parts[0] in {"python-qrcode", "_MEI439962"}:
        return name in {"metadata", "installer", "record", "direct_url.json"}
    if ".git" in parts:
        return True  # Preserve sole local histories, refs, index and configuration.
    if "target" in parts or "__pycache__" in parts:
        return name in {".rustc_info.json", "output", "stderr"} or name.endswith(".log")
    if name.endswith((".exe", ".dll", ".pdb", ".obj", ".o", ".a", ".lib", ".pyc")):
        return False
    if name.endswith((".wav", ".f32")) and size > 2 * 1024 * 1024:
        return False
    if name == "msys2-base-x86_64-20260611.tar.xz":
        return False
    return True


def git(*arguments, cwd=ROOT):
    result = subprocess.run(
        ["git", "--no-optional-locks", "-C", str(cwd), *arguments],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    )
    return result.stdout.decode("utf-8", errors="replace").strip()


def main():
    destination = Path(sys.argv[1]).resolve()
    allowed = ROOT / "distribution" / "build-temp-cleanup"
    if not destination.is_relative_to(allowed) or destination == allowed:
        raise ValueError("Use a new dated directory under distribution/build-temp-cleanup")
    if TEMP.is_symlink() or TEMP.is_junction():
        raise ValueError("build_temp must be a real directory")
    destination.mkdir(parents=True, exist_ok=False)
    started = time.time()
    summary = {
        "repository": str(ROOT), "build_temp": str(TEMP.resolve()),
        "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "git_head": git("rev-parse", "HEAD"),
        "git_status_before": git("status", "--porcelain=v1"),
        "free_bytes_before": shutil.disk_usage(ROOT).free,
        "top_level": {}, "git_repositories": [], "verified": False,
    }
    blobs = set()
    rows = []
    totals = collections.defaultdict(lambda: {"files": 0, "bytes": 0, "retained_files": 0})
    zip_path = destination / "retained-blobs.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
        for path, info in walk(TEMP):
            relative = path.relative_to(TEMP)
            row = {
                "path": relative.as_posix(), "size": info.st_size,
                "mtime_ns": info.st_mtime_ns, "attributes": info.st_file_attributes,
            }
            if info.st_file_attributes & REPARSE:
                row.update(kind="link", target=os.readlink(path), action="record-link")
            elif stat.S_ISDIR(info.st_mode):
                row.update(kind="directory", action="record-directory")
                if path.name == ".git":
                    repository = path.parent
                    summary["git_repositories"].append({
                        "path": repository.relative_to(TEMP).as_posix(),
                        "head": git("rev-parse", "HEAD", cwd=repository),
                        "remotes": git("remote", "-v", cwd=repository),
                        "status": git("status", "--porcelain=v1", cwd=repository),
                    })
            else:
                sha = digest(path)
                keep = retention(relative, info.st_size)
                row.update(kind="file", sha256=sha, action="archived" if keep else "discard-generated")
                group = totals[relative.parts[0]]
                group["files"] += 1
                group["bytes"] += info.st_size
                if keep:
                    group["retained_files"] += 1
                    if sha not in blobs:
                        archive.write(path, "blobs/" + sha)
                        blobs.add(sha)
                after = path.stat()
                if (after.st_size, after.st_mtime_ns) != (info.st_size, info.st_mtime_ns):
                    raise RuntimeError(f"File changed while archiving: {path}")
            rows.append(row)
            if len(rows) % 10000 == 0:
                print(f"Inventoried {len(rows)} entries; retained {len(blobs)} distinct blobs", flush=True)
    manifest = destination / "build-temp-manifest.jsonl.gz"
    with gzip.open(manifest, "wt", encoding="utf-8") as output:
        for row in rows:
            output.write(json.dumps(row, ensure_ascii=False) + "\n")
    print("Verifying every retained blob...", flush=True)
    with zipfile.ZipFile(zip_path) as archive:
        for entry in archive.infolist():
            with archive.open(entry) as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != entry.filename.split("/")[1]:
                    raise RuntimeError(f"Archive verification failed: {entry.filename}")
    print("Recording read-only hashes of upstream inputs, deliverables and maintained tooling...", flush=True)
    anchors = destination / "preserved-files.jsonl.gz"
    anchor_count = 0
    with gzip.open(anchors, "wt", encoding="utf-8") as output:
        for base in ("sources", "releases", "distribution", "development"):
            # Exclude this newly created archive subtree.
            def anchor_walk(folder):
                for item in sorted(folder.iterdir(), key=lambda p: p.name.lower()):
                    if item == allowed:
                        continue
                    info = item.lstat()
                    yield item, info
                    if stat.S_ISDIR(info.st_mode) and not info.st_file_attributes & REPARSE:
                        yield from anchor_walk(item)
            for path, info in anchor_walk(ROOT / base):
                record = {"path": path.relative_to(ROOT).as_posix(), "mtime_ns": info.st_mtime_ns,
                          "attributes": info.st_file_attributes, "size": info.st_size}
                if info.st_file_attributes & REPARSE:
                    record.update(kind="link", target=os.readlink(path))
                elif stat.S_ISDIR(info.st_mode):
                    record.update(kind="directory")
                else:
                    record.update(kind="file", sha256=digest(path))
                output.write(json.dumps(record, ensure_ascii=False) + "\n")
                anchor_count += 1
    summary.update(
        top_level=dict(totals), entries=len(rows),
        original_files=sum(group["files"] for group in totals.values()),
        original_bytes=sum(group["bytes"] for group in totals.values()),
        retained_files=sum(group["retained_files"] for group in totals.values()),
        retained_unique_blobs=len(blobs), preserved_entries=anchor_count,
        archive_bytes=zip_path.stat().st_size, verified=True,
        elapsed_seconds=round(time.time() - started, 1),
        artifacts={p.name: digest(p) for p in (zip_path, manifest, anchors)},
    )
    (destination / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in summary.items() if k not in {"top_level", "git_repositories"}}, indent=2), flush=True)


if __name__ == "__main__":
    main()
