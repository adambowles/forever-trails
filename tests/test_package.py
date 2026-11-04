import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from package import ADDON, ROOT, build, manifest
from check_release import validate


class SourceFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source"
        self.root.mkdir()
        shutil.copytree(ROOT / ADDON, self.root / ADDON)
        for name in ("README.md", "LICENSE"):
            shutil.copy2(ROOT / name, self.root / name)


class PackageTests(SourceFixture):
    def test_installable_archive_and_checksum(self):
        version, sources = manifest(self.root)
        archive, checksum = build(self.root, tag=f"v{version}")
        with zipfile.ZipFile(archive) as package:
            names = package.namelist()
            self.assertTrue(all(name.startswith(f"{ADDON}/") for name in names))
            self.assertEqual(set(names), {p.as_posix() for p in sources}
                             | {f"{ADDON}/README.md", f"{ADDON}/LICENSE"})
            for path in sources:
                self.assertEqual(package.read(path.as_posix()), (self.root / path).read_bytes())
        self.assertEqual(checksum.read_text().split()[0], hashlib.sha256(archive.read_bytes()).hexdigest())

    def test_reproducible_build(self):
        first = build(self.root, self.root / "one")[0]
        second = build(self.root, self.root / "two")[0]
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_version_mismatch_is_rejected(self):
        with self.assertRaises(ValueError):
            build(self.root, tag="v99.0.0")

    def test_missing_or_unlisted_runtime_source_is_rejected(self):
        (self.root / ADDON / "Core.lua").unlink()
        with self.assertRaisesRegex(ValueError, "Missing TOC source"):
            manifest(self.root)
        shutil.copy2(ROOT / ADDON / "Core.lua", self.root / ADDON / "Core.lua")
        (self.root / ADDON / "Forgotten.lua").write_text("return true")
        with self.assertRaisesRegex(ValueError, "Every runtime Lua file"):
            manifest(self.root)

    def test_unsafe_or_duplicate_manifest_sources_are_rejected(self):
        toc = self.root / ADDON / f"{ADDON}.toc"
        original = toc.read_text()
        for extra in ("../README.md", "/etc/passwd", "Core.lua"):
            toc.write_text(original + "\n" + extra + "\n")
            with self.assertRaises(ValueError):
                manifest(self.root)


class ReleaseTests(SourceFixture):
    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True,
                                       stderr=subprocess.DEVNULL).strip()

    def setUp(self):
        super().setUp()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("add", ".")
        self.git("commit", "-m", "Base")
        self.base = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/remotes/origin/main", self.base)
        self.version, _ = manifest(self.root)
        self.tag = f"v{self.version}"

    def test_tag_on_main_is_accepted(self):
        self.git("tag", self.tag)
        validate(self.tag, self.root)

    def test_annotated_tag_on_main_is_accepted(self):
        self.git("tag", "-a", self.tag, "-m", "Release")
        validate(self.tag, self.root)

    def test_tagged_ancestor_of_main_is_accepted(self):
        self.git("tag", self.tag)
        self.git("commit", "--allow-empty", "-m", "Later main commit")
        self.git("update-ref", "refs/remotes/origin/main", self.git("rev-parse", "HEAD"))
        self.git("checkout", self.tag)
        validate(self.tag, self.root)

    def test_tag_on_unmerged_branch_is_rejected(self):
        self.git("checkout", "-b", "feature")
        self.git("commit", "--allow-empty", "-m", "Unmerged feature")
        self.git("tag", self.tag)
        with self.assertRaisesRegex(ValueError, "commit on main"):
            validate(self.tag, self.root)

    def test_wrong_checkout_is_rejected(self):
        self.git("tag", self.tag)
        self.git("commit", "--allow-empty", "-m", "Different checkout")
        with self.assertRaisesRegex(ValueError, "Checkout"):
            validate(self.tag, self.root)

    def test_wrong_tag_version_is_rejected(self):
        self.git("tag", "v99.0.0")
        with self.assertRaisesRegex(ValueError, "TOC version"):
            validate("v99.0.0", self.root)
