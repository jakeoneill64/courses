#!/bin/sh
set -e
cd "$(dirname "$0")"
PY="${PYTHON:-.venv/bin/python}"
for f in diagrams/u1.py diagrams/u2.py diagrams/u3.py diagrams/u4a.py diagrams/u4b.py diagrams/u4c.py diagrams/handbook.py; do
  "$PY" "$f" > /dev/null
done
"$PY" tools/labs.py > /dev/null
mkdir -p ../pdf
compile() {
  typst compile --ignore-system-fonts --font-path fonts --root . "$1" "../pdf/$2"
  echo "built pdf/$2"
}
compile handbook.typ OMH-Foundations-0-Handbook.pdf
compile unit1.typ OMH-Foundations-1-Circuits-Sensors-and-Signals.pdf
compile unit2.typ OMH-Foundations-2-Logic-Processors-and-Firmware.pdf
compile unit3.typ OMH-Foundations-3-Control-Radio-and-Boards.pdf
compile unit4.typ OMH-Foundations-4-Systems-Software-and-the-Product.pdf
