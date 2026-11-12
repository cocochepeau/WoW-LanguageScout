"""Build an installable ZIP using the version and runtime files in the TOC."""

import argparse
from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile


ADDON = "LanguageScout"


def build_release(root, output_dir):
    root = Path(root).resolve()
    toc = root / f"{ADDON}.toc"
    manifest = toc.read_text(encoding="utf-8-sig")
    versions = re.findall(r"^## Version:\s*([^\r\n]+)", manifest, re.MULTILINE)
    if len(versions) != 1 or not re.fullmatch(r"\d+\.\d+\.\d+", versions[0]):
        raise ValueError("TOC must contain one Version in major.minor.patch format")
    version = versions[0]

    files = {toc, root / "README.md", root / "assets" / f"{ADDON}.tga"}
    for line in manifest.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            path = (root / line.replace("\\", "/")).resolve()
            if not path.is_relative_to(root):
                raise ValueError(f"TOC references a file outside the addon: {line}")
            files.add(path)
    flags = set((root / "flags").glob("*.tga"))
    if not flags:
        raise ValueError("No flag textures found")
    files.update(flags)
    for path in files:
        if not path.is_file():
            raise FileNotFoundError(f"Missing release file: {path}")

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    archive = output_dir / f"{ADDON}-{version}.zip"
    with ZipFile(archive, "w", ZIP_DEFLATED) as package:
        for path in sorted(files):
            package.write(path, f"{ADDON}/{path.relative_to(root).as_posix()}")
    return version, archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--addon-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-dir", type=Path, default=Path("dist"))
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    version, archive = build_release(args.addon_root, args.output_dir)
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as output:
            output.write(f"version={version}\ntag=v{version}\narchive={archive.as_posix()}\n")
    print(f"Built {archive}")


if __name__ == "__main__":
    main()
