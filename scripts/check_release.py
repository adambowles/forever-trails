#!/usr/bin/env python3
"""Reject a release unless the checked-out tag matches the TOC and belongs to main."""

from pathlib import Path
import subprocess
import sys

from package import ROOT, manifest


def validate(tag, root=ROOT):
    root = Path(root)
    version, _ = manifest(root)
    if tag != f"v{version}":
        raise ValueError(f"Release tag must match TOC version v{version}")

    def git(*args):
        return subprocess.check_output(["git", *args], cwd=root, text=True).strip()

    commit = git("rev-parse", f"refs/tags/{tag}^{{commit}}")
    if git("rev-parse", "HEAD") != commit:
        raise ValueError("Checkout does not match the release tag")
    result = subprocess.run(["git", "merge-base", "--is-ancestor", commit,
                             "refs/remotes/origin/main"], cwd=root, check=False)
    if result.returncode:
        raise ValueError("Release tag does not point to a commit on main")


if __name__ == "__main__":
    validate(sys.argv[1])
    print("Release tag, version and main ancestry verified")
