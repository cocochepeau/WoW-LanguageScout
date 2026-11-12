import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("build_release", ROOT / "scripts/build_release.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ReleaseTests(unittest.TestCase):
    def test_installable_package_includes_runtime_and_excludes_development_files(self):
        with tempfile.TemporaryDirectory() as directory:
            version, archive = builder.build_release(ROOT, directory)
            self.assertEqual(archive.name, f"LanguageScout-{version}.zip")
            with ZipFile(archive) as package:
                self.assertIsNone(package.testzip())
                names = set(package.namelist())
                self.assertIn("LanguageScout/LanguageScout.toc", names)
                self.assertIn("LanguageScout/assets/LanguageScout.tga", names)
                self.assertIn("LanguageScout/flags/EN.tga", names)
                self.assertEqual(len([n for n in names if n.startswith("LanguageScout/flags/")]), 15)
                self.assertFalse(any(n.endswith((".py", ".png", ".zip", ".yml")) for n in names))
                self.assertFalse(any("/tests/" in n or "/.git/" in n for n in names))
                self.assertFalse(any("/Plater/" in n for n in names))
                package.extractall(directory)
            toc = (Path(directory) / "LanguageScout/LanguageScout.toc").read_text()
            self.assertIn(f"## Version: {version}", toc)
            for line in toc.splitlines():
                if line.strip() and not line.startswith("#"):
                    self.assertTrue((Path(directory) / "LanguageScout" / line.strip()).is_file())

    def test_missing_runtime_file_fails_before_creating_zip(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "addon"
            shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns(".git", "dist", "*.zip", "__pycache__", "Plater"))
            (root / "UIHooks.lua").unlink()
            with self.assertRaises(FileNotFoundError):
                builder.build_release(root, Path(directory) / "output")
            self.assertFalse((Path(directory) / "output").exists())

    def test_unsafe_version_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "LanguageScout.toc").write_text("## Version: ../unexpected\n")
            with self.assertRaises(ValueError):
                builder.build_release(root, root / "output")


if __name__ == "__main__":
    unittest.main()
