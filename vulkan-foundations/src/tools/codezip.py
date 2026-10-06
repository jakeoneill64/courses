import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CODE = ROOT / "code"
OUT = ROOT / "pdf" / "Vulkan-Foundations-Code.zip"
PREFIX = "vulkan-foundations/code"
# A fixed timestamp keeps the archive byte-identical between builds of the same sources.
STAMP = (2026, 10, 1, 0, 0, 0)
SKIP_DIRS = {".cache", "__pycache__", ".idea", ".vscode"}
SOURCE_SUFFIXES = {".cpp", ".hpp", ".h", ".c", ".comp", ".vert", ".frag", ".glsl", ".geom", ".tesc", ".tese",
                   ".cmake", ".txt", ".md", ".json", ".py", ".sh"}
SOURCE_NAMES = {".clang-format"}


def included(path: Path) -> bool:
    parts = path.relative_to(CODE).parts
    if any(p.startswith("build") or p in SKIP_DIRS for p in parts[:-1]):
        return False
    return path.suffix in SOURCE_SUFFIXES or path.name in SOURCE_NAMES


def main() -> int:
    files = sorted(p for p in CODE.rglob("*") if p.is_file() and included(p))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            info = zipfile.ZipInfo(f"{PREFIX}/{path.relative_to(CODE).as_posix()}", STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o755 if path.stat().st_mode & 0o111 else 0o644) << 16
            archive.writestr(info, path.read_bytes())
    print(OUT, len(files), "files", OUT.stat().st_size, "bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
