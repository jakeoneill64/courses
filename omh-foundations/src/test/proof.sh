#!/bin/bash
set -e
cd "$(dirname "$0")/.."
p="$1"
{
  echo '#set page(width: 190mm, height: 250mm, margin: 8mm)'
  echo '#set text(font: "Source Sans 3", size: 8pt)'
  for f in figures/$p*.svg; do
    n=$(basename "$f" .svg)
    echo "#block(breakable: false)[*$n* #v(1mm) #image(\"/$f\", width: 100%) #v(5mm)]"
  done
} > test/proof-$p.typ
typst compile --ignore-system-fonts --font-path fonts --root . test/proof-$p.typ test/proof-$p.pdf
rm -f test/proof-$p-*.png
pdftoppm -r 90 -png test/proof-$p.pdf test/proof-$p
ls test/proof-$p-*.png
