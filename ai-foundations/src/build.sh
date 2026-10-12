#!/bin/sh
# Regenerates every figure and the lab list, then typesets the volumes into ../pdf and, for a full
# build, packs the companion code into ../pdf/AI-Foundations-Code.zip.
#   ./build.sh        every volume
#   ./build.sh 2      Unit 2 only (0 is the Handbook)
set -e
cd "$(dirname "$0")"
PY="${PYTHON:-../code/.venv/bin/python}"
for f in diagrams/*.py; do
  [ "$f" = diagrams/aifig.py ] && continue
  "$PY" "$f" > /dev/null
done
"$PY" tools/labs.py > /dev/null
mkdir -p ../pdf
compile() {
  typst compile --ignore-system-fonts --font-path fonts --root .. "$1" "../pdf/$2"
  echo "built pdf/$2"
}
volume() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
ONLY="${1:-}"
volume 0 && compile handbook.typ AI-Foundations-0-Handbook.pdf
volume 1 && compile unit1.typ AI-Foundations-1-Learning-Machines.pdf
volume 2 && compile unit2.typ AI-Foundations-2-Language-Models.pdf
volume 3 && compile unit3.typ AI-Foundations-3-From-Base-Model-to-Assistant.pdf
volume 4 && compile unit4.typ AI-Foundations-4-Making-It-Fast.pdf
[ -z "$ONLY" ] && "$PY" tools/codezip.py
exit 0
