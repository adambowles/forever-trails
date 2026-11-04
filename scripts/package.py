#!/usr/bin/env python3
"""Validate the addon manifest and build a directly installable, repeatable ZIP."""

import argparse
import hashlib
from pathlib import Path, PurePosixPath
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = "ForeverTrails"


def manifest(root=ROOT):
    addon = root / ADDON
    toc = addon / f"{ADDON}.toc"
    metadata, sources = {}, []
    for line in toc.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("##"):
            key, separator, value = line[2:].partition(":")
            if separator:
                key = key.strip()
                if key in metadata:
                    raise ValueError(f"Duplicate TOC metadata: {key}")
                metadata[key] = value.strip()
        elif line and not line.startswith("#"):
            path = PurePosixPath(line.replace("\\", "/"))
            if path.is_absolute() or ".." in path.parts or ":" in str(path):
                raise ValueError(f"Unsafe TOC path: {line}")
            if not (addon / path).is_file():
                raise ValueError(f"Missing TOC source: {path}")
            sources.append(path.as_posix())
    version = metadata.get("Version", "")
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", version):
        raise ValueError("TOC Version must be a numeric major.minor.patch")
    if metadata.get("Interface") != "16001":
        raise ValueError("Expected Forever interface 16001")
    if metadata.get("SavedVariables") != "ForeverTrailsDB":
        raise ValueError("Missing history SavedVariables declaration")
    if len(set(path.casefold() for path in sources)) != len(sources):
        raise ValueError("Duplicate TOC source")
    actual = {p.relative_to(addon).as_posix() for p in addon.rglob("*.lua")}
    if actual != {p for p in sources if p.endswith(".lua")}:
        raise ValueError("Every runtime Lua file must appear exactly once in the TOC")
    return version, [toc.relative_to(root), *(Path(ADDON) / p for p in sources)]


def build(root=ROOT, output=None, tag=None):
    root = Path(root)
    version, files = manifest(root)
    if tag is not None and tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} does not match TOC version v{version}")
    output = Path(output) if output else root / "dist"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{ADDON}-{version}-Forever.zip"
    contents = {str(p): (root / p).read_bytes() for p in files}
    contents[f"{ADDON}/README.md"] = (root / "README.md").read_bytes()
    contents[f"{ADDON}/LICENSE"] = (root / "LICENSE").read_bytes()
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for path, data in sorted(contents.items()):
            info = zipfile.ZipInfo(path.replace("\\", "/"), date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            package.writestr(info, data)
    checksum = archive.with_suffix(archive.suffix + ".sha256")
    checksum.write_text(f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n")
    return archive, checksum


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", help="Require this release tag to match the TOC version")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", action="store_true", help="Validate without building assets")
    args = parser.parse_args()
    if args.check:
        version, _ = manifest()
        print(f"Valid Forever addon manifest: {version}")
    else:
        for artifact in build(output=args.output, tag=args.tag):
            print(artifact)


if __name__ == "__main__":
    main()
