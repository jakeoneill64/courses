#import "../lib/template.typ": *

= Progress tracker <h-tracker>

Every lab in the course, in order. Date each line when the lab's done-when criteria all hold and its evidence is filed, and the chapter line when its completion checklist is ticked. The sign-off page at the end of each unit is the formal record; this is the map of where you are.

#let lab-data = yaml("/src/data/labs.yaml")

#for u in lab-data.units {
  heading(level: 2, outlined: false)[Unit #u.number: #u.title]
  let rows = ()
  for c in u.chapters {
    rows.push(table.cell(colspan: 3, fill: palette.navy-tint, text(weight: "bold", fill: palette.navy)[Chapter #c.number #eval(c.title, mode: "markup")]))
    for l in c.labs {
      rows.push(text(weight: "semibold")[Lab #l.number])
      rows.push(eval(l.title, mode: "markup"))
      rows.push([])
    }
    rows.push(text(style: "italic", fill: palette.muted)[Checklist])
    rows.push(text(style: "italic", fill: palette.muted)[Every line of Chapter #c.number's completion checklist ticked])
    rows.push([])
  }
  {
    set text(font: fonts.sans, size: 8.4pt)
    set par(justify: false)
    set table.cell(breakable: false)
    table(
      columns: (auto, 1fr, 26mm),
      inset: (x: 6pt, y: 4.4pt),
      stroke: (x, y) => if y > 0 { (bottom: 0.4pt + palette.rule) },
      fill: (x, y) => if y == 0 { palette.navy } else { none },
      table.header(..([Lab], [Title], [Date done]).map(h => text(fill: white, weight: "semibold", h))),
      ..rows,
    )
  }
}
