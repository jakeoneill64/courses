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
      block(below: 0.6em, text(font: fonts.display, weight: "bold", size: 9.4pt, fill: colour, tracking: 0.02em, {
        if icon != none { icon + h(4pt) }
        upper(title)
      }))
    }
    set par(justify: false)
    body
  },
)

#let why(body) = callout(title: [What this buys OMH], colour: palette.navy, tint: palette.navy-tint, body)
#let note(body, title: [Note]) = callout(title: title, colour: palette.muted, tint: palette.grey-tint, body)
#let safety(body, title: [Safety]) = callout(title: title, colour: palette.coral, tint: palette.coral-tint, body)
#let keyidea(body, title: [Key idea]) = callout(title: title, colour: palette.purple, tint: palette.purple-tint, body)

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
    block(below: 0.7em, text(font: fonts.display, weight: "bold", size: 10pt, fill: colour, upper(title)))
    if intro != none { block(below: 0.7em, intro) }
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

#let lab(title, goal: none, time: none, kit: none, body) = figure(
  kind: "lab", supplement: [Lab], numbering: lab-numbering, outlined: true, placement: none,
  caption: none,
  block(width: 100%, breakable: true, above: 1.3em, below: 1.3em, {
    set align(left)
    set par(justify: true)
    block(width: 100%, fill: palette.navy, radius: (top: 3pt), inset: (x: 10pt, y: 7pt), below: 0pt, sticky: true, {
      grid(columns: (auto, 1fr, auto), column-gutter: 8pt, align: horizon,
        text(font: fonts.sans, weight: "bold", size: 9pt, fill: palette.amber, tracking: 0.06em, upper[Lab #context counter(figure.where(kind: "lab")).display(lab-numbering)]),
        text(font: fonts.display, weight: "bold", size: 11pt, fill: white, title),
        if time != none { text(font: fonts.sans, size: 8.4pt, fill: white.darken(15%), time) },
      )
    })
    block(width: 100%, stroke: (left: 0.8pt + palette.rule, right: 0.8pt + palette.rule, bottom: 0.8pt + palette.rule), radius: (bottom: 3pt), inset: (x: 11pt, top: 9pt, bottom: 9pt), above: 0pt, {
      if goal != none {
        block(below: 0.7em, text(font: fonts.sans, size: 9.4pt, [#text(weight: "bold", fill: palette.navy)[Goal.] #goal]))
      }
      if kit != none {
        block(below: 0.7em, text(font: fonts.sans, size: 8.8pt, fill: palette.muted, [#text(weight: "bold")[Kit.] #kit]))
      }
      body
    })
  }),
)

#let fig(path, caption: none, width: 100%) = figure(
  image(path, width: width),
  caption: caption,
)

#let tbl(columns: auto, header: (), align: left, size: 8.6pt, zebra: true, ..cells) = {
  set text(font: fonts.sans, size: size)
  set par(justify: false)
  table(
    columns: columns,
    align: align,
    inset: (x: 6pt, y: 4.6pt),
    stroke: none,
    fill: (x, y) => if y == 0 { palette.navy } else if zebra and calc.even(y) { palette.grey-tint } else { none },
    table.header(..header.map(h => text(fill: white, weight: "semibold", h))),
    ..cells,
    table.hline(stroke: 0.6pt + palette.rule),
  )
}

#let chapter-meta(weeks: none, needs: none, builds: none) = {
  let row(k, v) = (text(font: fonts.sans, size: 8.4pt, weight: "bold", fill: palette.muted, upper(k)), text(font: fonts.sans, size: 9.2pt, v))
  let rows = ()
  if weeks != none { rows += row([Time], weeks) }
  if builds != none { rows += row([You build], builds) }
  if needs != none { rows += row([Needs], needs) }
  block(width: 100%, inset: (y: 8pt), stroke: (top: 0.6pt + palette.rule, bottom: 0.6pt + palette.rule), below: 1.4em,
    grid(columns: (5.6em, 1fr), row-gutter: 0.55em, column-gutter: 0.8em, ..rows))
}

#let cover(unit: "0", title: "", subtitle: "", chapters: (), edition: "") = {
  let accent = if unit == "0" { palette.amber } else { unit-accent.at(unit) }
  page(margin: 0pt, header: none, footer: none, fill: palette.navy, {
    place(top + left, dx: 0pt, dy: 0pt, grid(columns: (1fr,) * 5, rows: 7mm,
      rect(width: 100%, height: 100%, fill: palette.amber),
      rect(width: 100%, height: 100%, fill: palette.coral),
      rect(width: 100%, height: 100%, fill: palette.magenta),
      rect(width: 100%, height: 100%, fill: palette.purple),
      rect(width: 100%, height: 100%, fill: rgb("#0B5476")),
    ))
    place(top + left, dx: 22mm, dy: 34mm, block(width: 166mm, {
      text(font: fonts.display, size: 11pt, weight: "bold", fill: palette.amber, tracking: 0.18em)[OMH FOUNDATIONS]
      v(4mm)
      text(font: fonts.sans, size: 10.5pt, fill: white.darken(20%))[Hardware and low-level systems from first principles]
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

#let course-doc(unit: "0", title: "", short: "", subtitle: "", chapters: (), edition: "Second edition, October 2026", body) = {
  set document(title: "OMH Foundations: " + title, author: "OMH")
  let accent = unit-accent.at(unit)

  set text(font: fonts.body, size: 10.2pt, lang: "en", region: "gb", fill: palette.ink)
  set par(justify: true, leading: 0.64em, spacing: 0.92em)
  show math.equation: set text(font: fonts.math)
  show raw: set text(font: fonts.mono, size: 0.86em)
  show raw.where(block: false): it => box(fill: palette.code-bg, inset: (x: 2.2pt, y: 0pt), outset: (y: 2.4pt), radius: 2pt, it)
  show raw.where(block: true): it => block(width: 100%, fill: palette.code-bg, inset: 8pt, radius: 3pt, breakable: true, {
    set text(size: 8pt)
    set par(justify: false, leading: 0.5em)
    it
  })
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
        [OMH Foundations],
        text(weight: "bold", fill: palette.ink, counter(page).display()),
      )
    },
  )
  counter(page).update(1)
  body
}

#let contents() = {
  show outline.entry.where(level: 1): it => {
    v(0.9em, weak: true)
    text(font: fonts.display, weight: "bold", size: 10.5pt, it)
  }
  show outline.entry.where(level: 2): it => text(font: fonts.sans, size: 9.4pt, it)
  v(18mm)
  block(below: 1.2em, text(font: fonts.display, size: 25pt, weight: "bold", fill: palette.navy)[Contents])
  outline(title: none, depth: 2, indent: auto)
}

#let kit-data = yaml("/kit.yaml")
#let currency-symbol = (GBP: "£", USD: "US$", EUR: "€")
#let vat-note = ("inc": "inc VAT", "ex": "+ VAT", "import": "+ import VAT")

#let group-thousands(s) = {
  let n = s.len()
  let out = ""
  for (i, ch) in s.clusters().enumerate() {
    if i > 0 and calc.rem(n - i, 3) == 0 { out += "," }
    out += ch
  }
  out
}

#let money(x, decimals: true) = {
  let pence = int(calc.round(x * 100))
  let whole = calc.quo(pence, 100)
  let frac = calc.rem(pence, 100)
  if decimals { group-thousands(str(whole)) + "." + (if frac < 10 { "0" } else { "" }) + str(frac) } else { group-thousands(str(int(calc.round(x)))) }
}

#let price-cell(it) = {
  if it.at("price", default: none) == none {
    text(fill: palette.coral)[not checked]
  } else {
    [#currency-symbol.at(it.currency, default: it.currency + " ")#money(it.price)]
    linebreak()
    text(size: 0.86em, fill: palette.muted, vat-note.at(it.vat, default: ""))
  }
}

#let kit-items(unit: none, optional: none) = kit-data.items.filter(i => (unit == none or i.unit == unit) and (optional == none or i.optional == optional))

#let kit-table(unit: none, optional: none, size: 7.3pt) = {
  let items = kit-items(unit: unit, optional: optional)
  let rows = ()
  for c in kit-data.categories {
    let its = items.filter(i => i.category == c.id)
    if its.len() == 0 { continue }
    rows.push(table.cell(colspan: 5, fill: palette.navy-tint, text(weight: "bold", fill: palette.navy, c.name)))
    for i in its {
      let url = i.at("url", default: none)
      let linked(body) = if url == none { body } else { link(url, body) }
      rows.push({
        linked(text(weight: "semibold", fill: palette.ink, i.name))
        if i.optional { h(3pt); box(baseline: 0.1em, pill([optional], fill: palette.amber, fg: palette.ink)) }
        linebreak()
        text(fill: palette.muted, i.use)
        if i.at("notes", default: "") != "" {
          linebreak()
          text(size: 0.94em, fill: palette.muted, style: "italic", i.notes)
        }
        if not i.at("verified", default: true) {
          linebreak()
          text(size: 0.94em, fill: palette.coral)[Not verified: check the listing before you buy.]
        }
      })
      rows.push(text(font: fonts.mono, size: 0.9em, str(i.sku)))
      rows.push(align(center, str(i.qty)))
      rows.push(align(right, price-cell(i)))
      rows.push(linked(text(fill: if url == none { palette.muted } else { palette.navy }, i.seller)))
    }
  }
  set text(font: fonts.sans, size: size)
  set par(justify: false, leading: 0.48em)
  set table.cell(breakable: false)
  table(
    columns: (2.75fr, 1.1fr, 0.3fr, 0.78fr, 0.95fr),
    inset: (x: 4.5pt, y: 4pt),
    stroke: (x, y) => if y > 0 { (bottom: 0.4pt + palette.rule) },
    fill: (x, y) => if y == 0 { palette.navy } else { none },
    align: (x, y) => if x == 2 { center + top } else if x == 3 { right + top } else { left + top },
    table.header(..([Item and use], [SKU or part number], [Qty], [Price each], [Seller]).map(h => text(fill: white, weight: "semibold", h))),
    ..rows,
  )
}

#let kit-sums(unit: none, optional: false) = {
  let gbp = 0.0
  let usd = 0.0
  let eur = 0.0
  let unpriced = ()
  for i in kit-items(unit: unit, optional: optional) {
    if i.at("price", default: none) == none {
      unpriced.push(i.name)
      continue
    }
    let v = i.price * i.qty
    if i.currency == "GBP" { gbp += if i.vat == "ex" { v * 1.2 } else { v } } else if i.currency == "USD" { usd += v } else if i.currency == "EUR" { eur += v }
  }
  (gbp: gbp, usd: usd, eur: eur, unpriced: unpriced)
}

#let kit-summary(unit: none) = {
  let s = kit-sums(unit: unit)
  let o = kit-sums(unit: unit, optional: true)
  let overseas(x) = {
    let parts = ()
    if x.usd > 0 { parts.push("US$" + money(x.usd, decimals: false)) }
    if x.eur > 0 { parts.push("€" + money(x.eur, decimals: false)) }
    if parts.len() == 0 { [none] } else { parts.join(" and ") }
  }
  tbl(columns: (1fr, auto, auto), header: ([], [Required], [Optional]), align: (left, right, right),
    [UK sellers, VAT included (ex-VAT prices × 1.2)], [£#money(s.gbp, decimals: false)], [£#money(o.gbp, decimals: false)],
    [Overseas sellers, before import VAT and delivery], [#overseas(s)], [#overseas(o)],
    [Items with no checked price], [#if s.unpriced.len() == 0 [none] else [#s.unpriced.len()]], [#if o.unpriced.len() == 0 [none] else [#o.unpriced.len()]],
  )
  if s.unpriced.len() > 0 {
    text(font: fonts.sans, size: 8.4pt, fill: palette.muted)[Not priced: #s.unpriced.join("; ").]
  }
}

#let signoff(unit: "1", chapters: (), review: ()) = {
  heading(level: 1, numbering: none)[Sign-off]
  [A unit is complete when every chapter's completion checklist is ticked, its evidence is in your notebook and labs repository, and you can do each review task below without notes. Date each line as you finish it. If someone who builds hardware for a living will review your work, ask them to sign the last line.]
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
  checklist(title: [Unit review], intro: [Each task takes an hour or less if the unit has done its work. Do them aloud or in writing, from memory, then check against your notebook.], ..review)
  v(1.2em)
  grid(columns: (1fr, 1fr), column-gutter: 14mm, row-gutter: 9mm,
    [#line(length: 100%, stroke: 0.5pt + palette.muted) #v(-0.4em) #text(font: fonts.sans, size: 8.4pt, fill: palette.muted)[Signed: student]],
    [#line(length: 100%, stroke: 0.5pt + palette.muted) #v(-0.4em) #text(font: fonts.sans, size: 8.4pt, fill: palette.muted)[Date]],
    [#line(length: 100%, stroke: 0.5pt + palette.muted) #v(-0.4em) #text(font: fonts.sans, size: 8.4pt, fill: palette.muted)[Reviewed by (optional)]],
    [#line(length: 100%, stroke: 0.5pt + palette.muted) #v(-0.4em) #text(font: fonts.sans, size: 8.4pt, fill: palette.muted)[Date]],
  )
}

#let about-unit(unit: "1", intro: [], rows: (), before: []) = {
  heading(level: 1, numbering: none)[About this unit]
  intro
  tbl(columns: (auto, 1fr, auto), header: ([Chapter], [You build], [Weeks]), align: (left, left, right), ..rows.flatten())
  if before != [] {
    heading(level: 2)[Before you start]
    before
  }
  heading(level: 2)[Kit for this unit]
  [The Handbook's kit part lists every item for this unit with its part number, seller and price. The totals, for items this unit needs first:]
  kit-summary(unit: int(unit))
}
