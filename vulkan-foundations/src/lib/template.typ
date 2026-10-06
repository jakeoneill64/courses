#let palette = (
  navy: rgb("#003F5C"),
  purple: rgb("#58508D"),
  magenta: rgb("#BC5090"),
  coral: rgb("#FF6361"),
  amber: rgb("#FFA600"),
  ink: rgb("#1B2430"),
  muted: rgb("#5A6472"),
  rule: rgb("#D5DAE1"),
  paper: white,
  code-bg: rgb("#F3F5F8"),
  navy-tint: rgb("#E8EFF3"),
  purple-tint: rgb("#EFEEF6"),
  magenta-tint: rgb("#F8EEF4"),
  coral-tint: rgb("#FFF0EF"),
  amber-tint: rgb("#FFF5E0"),
  grey-tint: rgb("#F4F6F8"),
  green: rgb("#2E7D5B"),
  green-tint: rgb("#E9F4EE"),
)

#let fonts = (
  body: "Source Serif 4",
  sans: "Source Sans 3",
  display: "Red Hat Display",
  mono: "JetBrains Mono",
  math: "Libertinus Math",
)

#let unit-accent = (
  "0": palette.navy,
  "1": palette.amber,
  "2": palette.coral,
  "3": palette.magenta,
  "4": palette.purple,
)

#let doc-unit = state("doc-unit", "0")
#let doc-title = state("doc-title", "")

#let sans(body, ..args) = text(font: fonts.sans, ..args, body)

#let on-dark(body, size: 7.4pt) = {
  show raw.where(block: false): it => text(font: fonts.mono, size: size, fill: palette.amber-tint, it.text)
  body
}

#let cbox(size: 0.78em, fill: none, colour: palette.navy) = box(
  width: size, height: size, baseline: 0.12em, radius: 1.5pt,
  stroke: 0.8pt + colour, fill: fill,
)

#let pill(body, fill: palette.navy, fg: white) = box(
  inset: (x: 5pt, y: 2.2pt), radius: 6pt, fill: fill,
  text(font: fonts.sans, size: 7.6pt, weight: "semibold", fill: fg, tracking: 0.04em, upper(body)),
)

#let callout(title: none, colour: palette.navy, tint: palette.navy-tint, icon: none, body) = block(
  width: 100%, breakable: true, fill: tint, radius: 3pt, inset: (x: 11pt, y: 9pt),
  stroke: (left: 2.6pt + colour), above: 1.1em, below: 1.1em,
  {
    if title != none {
      block(below: 0.6em, sticky: true, text(font: fonts.display, weight: "bold", size: 9.4pt, fill: colour, tracking: 0.02em, {
        if icon != none { icon + h(4pt) }
        upper(title)
      }))
    }
    set par(justify: false)
    body
  },
)

#let course = (
  name: "Vulkan Foundations",
  tagline: "Explicit GPU programming from first principles",
  edition: "First edition, October 2026",
  author: "O’Neill Software",
)

#let why(body) = callout(title: [Why it matters], colour: palette.navy, tint: palette.navy-tint, body)
#let note(body, title: [Note]) = callout(title: title, colour: palette.muted, tint: palette.grey-tint, body)
#let safety(body, title: [Safety]) = callout(title: title, colour: palette.coral, tint: palette.coral-tint, body)
#let keyidea(body, title: [Key idea]) = callout(title: title, colour: palette.purple, tint: palette.purple-tint, body)
#let hazard(body, title: [Hazard]) = callout(title: title, colour: palette.coral, tint: palette.coral-tint, body)
#let opengl(body, title: [Coming from OpenGL]) = callout(title: title, colour: rgb("#A66A00"), tint: palette.amber-tint, body)

#let skip-test(intro: none, rule: none, ..qs) = callout(
  title: [Skip test], colour: palette.purple, tint: palette.purple-tint,
  {
    if intro != none { intro; v(0.3em) }
    set enum(numbering: "1.", indent: 0pt, body-indent: 0.6em, spacing: 0.75em)
    enum(..qs.pos())
    if rule != none {
      v(0.25em)
      text(font: fonts.sans, size: 9pt, fill: palette.purple, weight: "semibold", rule)
    }
  },
)

#let check-item(body) = grid(
  columns: (1.15em, 1fr), column-gutter: 0.35em,
  align(top, pad(top: 0.12em, cbox())), body,
)

#let checklist(title: [Completion checklist], intro: none, colour: palette.green, tint: palette.green-tint, ..items) = block(
  width: 100%, breakable: true, fill: tint, radius: 3pt, inset: (x: 12pt, y: 10pt),
  stroke: 0.7pt + colour, above: 1.2em, below: 1.2em,
  {
    block(below: 0.7em, sticky: true, text(font: fonts.display, weight: "bold", size: 10pt, fill: colour, upper(title)))
    if intro != none { block(below: 0.7em, sticky: true, intro) }
    set par(justify: false)
    stack(spacing: 0.62em, ..items.pos().map(check-item))
  },
)

#let done-when(..items) = block(
  width: 100%, breakable: true, fill: palette.green-tint, radius: 2.5pt, inset: (x: 10pt, y: 8pt),
  above: 0.9em, below: 0.4em,
  {
    block(sticky: true, below: 0.45em, text(font: fonts.sans, weight: "bold", size: 8.6pt, fill: palette.green, tracking: 0.05em, upper[Done when]))
    set par(justify: false)
    for (n, it) in items.pos().enumerate() {
      block(above: if n == 0 { 0em } else { 0.5em }, below: 0em, breakable: false, check-item(it))
    }
  },
)

#let evidence(..items) = block(
  width: 100%, breakable: true, inset: (x: 10pt, y: 6pt), above: 0.4em, below: 0.9em,
  {
    block(sticky: true, below: 0.4em, text(font: fonts.sans, weight: "bold", size: 8.6pt, fill: palette.muted, tracking: 0.05em, upper[Evidence for the notebook]))
    set list(marker: text(fill: palette.muted, sym.bullet), indent: 0.2em, body-indent: 0.5em, spacing: 0.45em)
    list(..items.pos())
  },
)

#let lab-numbering(n) = context {
  let ch = counter(heading).get().first()
  doc-unit.get() + "." + str(ch) + "." + str(n)
}

#let lab(title, goal: none, time: none, code: none, body) = figure(
  kind: "lab", supplement: [Lab], numbering: lab-numbering, outlined: true, placement: none,
  caption: none,
  block(width: 100%, breakable: true, above: 1.3em, below: 1.3em, {
    set align(left)
    set par(justify: true)
    block(width: 100%, fill: palette.navy, radius: (top: 3pt), inset: (x: 10pt, y: 7pt), below: 0pt, sticky: true, {
      grid(columns: (auto, 1fr, auto), column-gutter: 8pt, align: horizon,
        text(font: fonts.sans, weight: "bold", size: 9pt, fill: palette.amber, tracking: 0.06em, upper[Lab #context counter(figure.where(kind: "lab")).display(lab-numbering)]),
        text(font: fonts.display, weight: "bold", size: 11pt, fill: white, on-dark(title, size: 9.6pt)),
        if time != none { text(font: fonts.sans, size: 8.4pt, fill: white.darken(15%), time) },
      )
    })
    block(width: 100%, stroke: (left: 0.8pt + palette.rule, right: 0.8pt + palette.rule, bottom: 0.8pt + palette.rule), radius: (bottom: 3pt), inset: (x: 11pt, top: 9pt, bottom: 9pt), above: 0pt, {
      if goal != none {
        block(below: 0.7em, text(font: fonts.sans, size: 9.4pt, [#text(weight: "bold", fill: palette.navy)[Goal.] #goal]))
      }
      if code != none {
        block(below: 0.7em, text(font: fonts.sans, size: 8.8pt, fill: palette.muted, [#text(weight: "bold")[Code.] #raw(code)]))
      }
      body
    })
  }),
)

#let fig(name, caption: none, width: 100%, placement: auto) = figure(
  image(if name.starts-with("/") { name } else { "/src/figures/" + name + ".svg" }, width: width),
  caption: caption, placement: placement,
)

#let tbl(columns: auto, header: (), align: left, size: 8.6pt, zebra: true, ..cells) = {
  set text(font: fonts.sans, size: size)
  set par(justify: false)
  let width = if type(columns) == array { columns.len() } else if type(columns) == int { columns } else { 1 }
  block(breakable: cells.pos().len() / width > 12, table(
    columns: columns,
    align: align,
    inset: (x: 6pt, y: 4.6pt),
    stroke: none,
    fill: (x, y) => if y == 0 { palette.navy } else if zebra and calc.even(y) { palette.grey-tint } else { none },
    table.header(..header.map(h => text(fill: white, weight: "semibold", on-dark(h, size: 7.8pt)))),
    ..cells,
    table.hline(stroke: 0.6pt + palette.rule),
  ))
}

#let chapter-meta(time: none, needs: none, builds: none) = {
  let row(k, v) = (text(font: fonts.sans, size: 8.4pt, weight: "bold", fill: palette.muted, upper(k)), text(font: fonts.sans, size: 9.2pt, v))
  let rows = ()
  if time != none { rows += row([Time], time) }
  if builds != none { rows += row([You build], builds) }
  if needs != none { rows += row([Needs], needs) }
  block(width: 100%, inset: (y: 8pt), stroke: (top: 0.6pt + palette.rule, bottom: 0.6pt + palette.rule), below: 1.4em,
    grid(columns: (5.6em, 1fr), row-gutter: 0.55em, column-gutter: 0.8em, ..rows))
}

#let cover(unit: "0", title: "", subtitle: "", chapters: (), edition: "") = {
  let accent = if unit == "0" { palette.amber } else if unit == "4" { palette.purple.lighten(45%) } else { unit-accent.at(unit) }
  page(margin: 0pt, header: none, footer: none, fill: palette.navy, {
    place(top + left, dx: 0pt, dy: 0pt, grid(columns: (1fr,) * 5, rows: 7mm,
      rect(width: 100%, height: 100%, fill: palette.amber),
      rect(width: 100%, height: 100%, fill: palette.coral),
      rect(width: 100%, height: 100%, fill: palette.magenta),
      rect(width: 100%, height: 100%, fill: palette.purple),
      rect(width: 100%, height: 100%, fill: rgb("#0B5476")),
    ))
    place(top + left, dx: 22mm, dy: 34mm, block(width: 166mm, {
      text(font: fonts.display, size: 11pt, weight: "bold", fill: palette.amber, tracking: 0.18em, upper(course.name))
      v(4mm)
      text(font: fonts.sans, size: 10.5pt, fill: white.darken(20%), course.tagline)
    }))
    place(top + left, dx: 22mm, dy: 88mm, block(width: 166mm, {
      if unit != "0" {
        text(font: fonts.display, size: 13pt, weight: "bold", fill: accent, tracking: 0.12em)[UNIT #unit]
        v(2mm)
      }
      set par(leading: 0.42em, justify: false)
      text(font: fonts.display, size: 38pt, weight: "black", fill: white, hyphenate: false, title)
      v(6mm)
      text(font: fonts.sans, size: 14pt, fill: white.darken(12%), subtitle)
    }))
    if chapters.len() > 0 {
      place(top + left, dx: 22mm, dy: 170mm, block(width: 166mm, {
        set par(leading: 0.55em)
        for (i, c) in chapters.enumerate() {
          grid(columns: (14mm, 1fr), column-gutter: 2mm,
            text(font: fonts.display, size: 10.5pt, weight: "bold", fill: accent, if unit != "0" { unit + "." + str(i + 1) } else { str(i + 1) }),
            text(font: fonts.sans, size: 11pt, fill: white, c))
          v(2.6mm)
        }
      }))
    }
    place(bottom + left, dx: 22mm, dy: -18mm, text(font: fonts.sans, size: 9pt, fill: white.darken(30%), edition))
  })
}

#let code-frame(body, file: none, caption: none, breakable: true) = block(width: 100%, breakable: breakable, above: 1em, below: 1em, {
  if file != none or caption != none {
    block(width: 100%, fill: palette.navy, radius: (top: 3pt), inset: (x: 8pt, y: 4.5pt), below: 0pt, sticky: true,
      grid(columns: (1fr, auto), column-gutter: 8pt,
        text(font: fonts.sans, size: 8pt, fill: white, on-dark(if caption != none { caption } else { [] })),
        if file != none { text(font: fonts.mono, size: 7.2pt, fill: white.darken(18%), file) },
      ))
  }
  block(width: 100%, fill: palette.code-bg, inset: 8pt, radius: if file != none or caption != none { (bottom: 3pt) } else { 3pt }, above: 0pt, breakable: breakable, {
    show raw: set text(size: 8pt)
    set par(justify: false, leading: 0.5em)
    body
  })
})

#let course-doc(unit: "0", title: "", short: "", subtitle: "", chapters: (), edition: course.edition, body) = {
  set document(title: course.name + ": " + title, author: course.author)
  let accent = unit-accent.at(unit)

  set text(font: fonts.body, size: 10.2pt, lang: "en", region: "gb", fill: palette.ink)
  set par(justify: true, leading: 0.64em, spacing: 0.92em)
  show math.equation: set text(font: fonts.math)
  show raw: set text(font: fonts.mono, size: 0.86em)
  show raw.where(block: false): it => box(fill: palette.code-bg, inset: (x: 2.2pt, y: 0pt), outset: (y: 2.4pt), radius: 2pt, it)
  show raw.where(block: true): it => if it.at("label", default: none) == <framed> { it } else {
    code-frame([#raw(it.text, block: true, lang: it.lang) <framed>], breakable: it.text.split("\n").len() > 24)
  }
  show link: it => text(fill: palette.navy, it)

  set list(marker: (text(fill: accent.darken(10%), sym.bullet), text(fill: palette.muted, sym.dash.en)), indent: 0.3em, body-indent: 0.55em, spacing: 0.7em)
  set enum(indent: 0.1em, body-indent: 0.55em, spacing: 0.7em)
  set table(stroke: none)

  set heading(numbering: (..n) => {
    let nums = n.pos()
    if nums.len() == 1 { if unit == "0" { str(nums.first()) } else { unit + "." + str(nums.first()) } }
  })
  show heading: set text(font: fonts.display, fill: palette.navy)
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    counter(figure.where(kind: "lab")).update(0)
    counter(figure.where(kind: image)).update(0)
    counter(figure.where(kind: table)).update(0)
    v(18mm)
    if it.numbering != none {
      block(below: 0.4em, text(font: fonts.display, size: 12pt, weight: "bold", fill: accent, tracking: 0.1em, upper[#if unit == "0" [Part] else [Chapter] #counter(heading).display()]))
    } else {
      block(below: 0.4em, text(font: fonts.display, size: 12pt, weight: "bold", fill: accent, tracking: 0.1em, upper[#if unit == "0" [Handbook] else [Unit #unit]]))
    }
    block(below: 1.0em, { set par(justify: false); text(size: 25pt, weight: "bold", hyphenate: false, it.body) })
  }
  show heading.where(level: 2): it => block(above: 1.6em, below: 0.85em, sticky: true, {
    set par(justify: false)
    text(size: 14pt, weight: "bold", hyphenate: false, it.body)
    v(-0.55em)
    line(length: 100%, stroke: 0.6pt + palette.rule)
  })
  show heading.where(level: 3): it => block(above: 1.25em, below: 0.65em, sticky: true, text(size: 11.2pt, weight: "bold", it.body))
  show heading.where(level: 4): it => block(above: 1em, below: 0.5em, sticky: true, text(font: fonts.sans, size: 10pt, weight: "bold", fill: palette.ink, it.body))

  set figure(numbering: n => context { (if unit == "0" { "" } else { str(unit) + "." }) + str(counter(heading).get().first()) + "." + str(n) })
  show figure.caption: it => {
    set text(font: fonts.sans, size: 8.8pt, fill: palette.muted)
    set par(justify: false)
    [#text(weight: "bold", fill: palette.ink)[#it.supplement #context it.counter.display(it.numbering).] #it.body]
  }
  show figure.where(kind: "lab"): it => it.body
  show figure: set block(breakable: true)

  doc-unit.update(unit)
  doc-title.update(title)

  cover(unit: unit, title: title, subtitle: subtitle, chapters: chapters, edition: edition)

  set page(
    paper: "a4",
    margin: (top: 25mm, bottom: 22mm, x: 21mm),
    header: context {
      let p = here().page()
      let starts = query(heading.where(level: 1)).filter(h => h.location().page() == p)
      if starts.len() == 0 {
        let before = query(heading.where(level: 1).before(here()))
        set text(font: fonts.sans, size: 8.2pt, fill: palette.muted)
        grid(columns: (1fr, auto),
          [#text(weight: "bold", fill: accent)[#if unit != "0" [Unit #unit] else [Handbook]] #h(4pt) #short],
          if before.len() > 0 {
            let h = before.last()
            if h.numbering == none [#h.body] else if unit == "0" [#counter(heading).at(h.location()).first() #h.body] else [#unit.#counter(heading).at(h.location()).first() #h.body]
          },
        )
        v(-0.45em)
        line(length: 100%, stroke: 0.5pt + palette.rule)
      }
    },
    footer: context {
      set text(font: fonts.sans, size: 8.2pt, fill: palette.muted)
      grid(columns: (1fr, auto),
        [#course.name],
        text(weight: "bold", fill: palette.ink, counter(page).display()),
      )
    },
  )
  counter(page).update(1)
  body
}

#let trademarks = [Vulkan and the Vulkan logo are registered trademarks of the Khronos Group Inc. OpenGL and the oval logo are trademarks or registered trademarks of Hewlett Packard Enterprise in the United States and other countries, used by permission by Khronos. All other trademarks belong to their owners. This course is not endorsed by the Khronos Group.]

#let colophon() = block(above: 2.4em, width: 100%, inset: (top: 8pt), stroke: (top: 0.5pt + palette.rule), {
  set text(font: fonts.sans, size: 7.6pt, fill: palette.muted)
  set par(justify: false)
  [#course.name, #course.edition. © 2026 O’Neill Group LLC. ]
  trademarks
})

#let contents() = {
  show outline.entry.where(level: 1): it => {
    v(0.9em, weak: true)
    text(font: fonts.display, weight: "bold", size: 10.5pt, it)
  }
  show outline.entry.where(level: 2): it => text(font: fonts.sans, size: 9.4pt, it)
  v(18mm)
  block(below: 1.2em, text(font: fonts.display, size: 25pt, weight: "bold", fill: palette.navy)[Contents])
  outline(title: none, depth: 2, indent: auto)
  colophon()
}

#let lang-of(path) = {
  let ext = path.split(".").last()
  if ext in ("cpp", "hpp", "h", "cc", "c") { "cpp" }
  else if ext in ("comp", "vert", "frag", "glsl", "geom", "tesc", "tese") { "glsl" }
  else if ext == "txt" or ext == "cmake" { "cmake" }
  else if ext == "py" { "python" }
  else if ext == "sh" { "bash" }
  else { none }
}

#let dedent(lines) = {
  let widths = lines.filter(l => l.trim() != "").map(l => l.len() - l.trim(at: start).len())
  let cut = if widths.len() == 0 { 0 } else { calc.min(..widths) }
  lines.map(l => if l.trim() == "" { "" } else { l.slice(cut) })
}

// The companion code marks each listing with "snippet:begin <name>" and "snippet:end <name>" comment lines.
#let snippet(path, name, caption: none, lang: auto) = {
  let lines = read("/code/" + path).split("\n")
  let begin = lines.position(l => l.contains("snippet:begin " + name) and l.trim().ends-with(name))
  let end = lines.position(l => l.contains("snippet:end " + name) and l.trim().ends-with(name))
  assert(begin != none, message: "no snippet:begin " + name + " in code/" + path)
  assert(end != none and end > begin, message: "no snippet:end " + name + " in code/" + path)
  let body = dedent(lines.slice(begin + 1, end).filter(l => not l.contains("snippet:")))
  let l = if lang == auto { lang-of(path) } else { lang }
  code-frame([#raw(body.join("\n"), block: true, lang: l) <framed>], file: "code/" + path, caption: caption, breakable: body.len() > 24)
}

#let listing(path, caption: none, lang: auto) = {
  let lines = read("/code/" + path).split("\n").filter(l => not l.contains("snippet:"))
  while lines.len() > 0 and lines.last().trim() == "" { lines = lines.slice(0, -1) }
  let l = if lang == auto { lang-of(path) } else { lang }
  code-frame([#raw(lines.join("\n"), block: true, lang: l) <framed>], file: "code/" + path, caption: caption, breakable: lines.len() > 24)
}

#let console(body, caption: none) = code-frame([#raw(body.trim(at: end), block: true, lang: none) <framed>], caption: caption, breakable: body.split("\n").len() > 24)

#let problems(..items) = {
  heading(level: 2)[Problem set]
  set enum(numbering: "1.", indent: 0pt, body-indent: 0.6em, spacing: 0.95em)
  enum(..items.pos())
}

#let reading(..items) = {
  heading(level: 2)[Reading]
  set list(spacing: 0.75em)
  list(..items.pos())
}

#let signoff(unit: "1", chapters: (), review: ()) = {
  heading(level: 1, numbering: none)[Sign-off]
  [A unit is complete when every chapter's completion checklist is ticked, its evidence is in your notebook and repository, and you can do each review task below without notes. Date each line as you finish it. If someone who writes GPU code for a living will review your work, ask them to sign the last line.]
  v(0.6em)
  {
    set text(font: fonts.sans, size: 9pt)
    table(
      columns: (auto, 1fr, auto, auto, 24mm),
      inset: (x: 6pt, y: 6pt),
      stroke: (x, y) => if y > 0 { (bottom: 0.5pt + palette.rule) },
      fill: (x, y) => if y == 0 { palette.navy } else { none },
      align: (x, y) => if x in (2, 3) { center + horizon } else { left + horizon },
      table.header(..([], [Chapter], [Checklist ticked], [Evidence filed], [Date]).map(h => text(fill: white, weight: "semibold", h))),
      ..chapters.enumerate().map(((i, c)) => (text(weight: "bold", fill: unit-accent.at(unit), unit + "." + str(i + 1)), c, cbox(), cbox(), [])).flatten(),
    )
  }
  checklist(title: [Unit review], intro: [Each task takes an hour or less if the unit has done its work. Do them aloud or in writing, from memory, then check against your notebook and code.], ..review)
  v(1.2em)
  grid(columns: (1fr, 1fr), column-gutter: 14mm, row-gutter: 9mm,
    [#line(length: 100%, stroke: 0.5pt + palette.muted) #v(-0.4em) #text(font: fonts.sans, size: 8.4pt, fill: palette.muted)[Signed: student]],
    [#line(length: 100%, stroke: 0.5pt + palette.muted) #v(-0.4em) #text(font: fonts.sans, size: 8.4pt, fill: palette.muted)[Date]],
    [#line(length: 100%, stroke: 0.5pt + palette.muted) #v(-0.4em) #text(font: fonts.sans, size: 8.4pt, fill: palette.muted)[Reviewed by (optional)]],
    [#line(length: 100%, stroke: 0.5pt + palette.muted) #v(-0.4em) #text(font: fonts.sans, size: 8.4pt, fill: palette.muted)[Date]],
  )
}

#let about-unit(unit: "1", intro: [], rows: (), before: [], needs: []) = {
  heading(level: 1, numbering: none)[About this unit]
  intro
  tbl(columns: (auto, 1fr, auto), header: ([Chapter], [You build], [Hours]), align: (left, left, right), ..rows.flatten())
  if before != [] {
    heading(level: 2)[Before you start]
    before
  }
  if needs != [] {
    heading(level: 2)[What this unit needs]
    needs
  }
}
