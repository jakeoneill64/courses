import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
UNITS = [
    (1, "Circuits, Sensors and Signals"),
    (2, "Logic, Processors and Firmware"),
    (3, "Control, Radio and Boards"),
    (4, "Systems Software and the Product"),
]


def bracketed(text, start):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    raise ValueError("unbalanced brackets")


def chapter(path, unit, number):
    text = path.read_text()
    title = re.search(r"^= (.+?)(?:\s+<[\w-]+>)?\s*$", text, re.M).group(1)
    labs = []
    for n, m in enumerate(re.finditer(r"#lab\(\[", text), 1):
        labs.append({"number": f"{unit}.{number}.{n}", "title": bracketed(text, m.end() - 1)})
    return {"number": f"{unit}.{number}", "title": title, "labs": labs}


def main():
    units = []
    for n, title in UNITS:
        files = sorted((ROOT / f"u{n}").glob("ch*.typ"), key=lambda p: int(re.match(r"ch(\d+)", p.name).group(1)))
        chapters = [chapter(p, n, int(re.match(r"ch(\d+)", p.name).group(1))) for p in files]
        units.append({"number": n, "title": title, "chapters": chapters})
    out = ROOT / "data" / "labs.yaml"
    out.write_text(yaml.safe_dump({"units": units}, allow_unicode=True, sort_keys=False, width=200))
    print(out, sum(len(c["labs"]) for u in units for c in u["chapters"]), "labs")


if __name__ == "__main__":
    main()
