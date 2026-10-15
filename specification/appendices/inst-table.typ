#import "../theme.typ": font-heading, font-mono, weight-heading

#let color-cell-fill = (
  "reg": color.aqua,
  "imm": color.rgb("#E0F4F7"),
)

#let color-name-cell-fill = luma(96%)



#let count01(s) = {
  let count = 0
  for c in s {
    if c == "0" or c == "1" {
      count += 1
    }
  }
  return count
}

#let reg(body) = (
  tag: "reg",
  span: 5,
  body: body,
)

#let imm(w, body) = (
  tag: "imm",
  span: w,
  body: body,
)

#let lit(body) = (
  tag: "field",
  span: count01(body),
  body: body,
)

#let name-cell(name) = {
  if name.len() > 12 {
    name = text(size: 6pt, name)
  }
  table.cell(fill: color-name-cell-fill, name)
}

#let inst-row(name, ..content) = {
  let fields = content.pos()
  let total-span = fields.map(it => it.span).sum(default: 0)

  assert(
    total-span <= 32,
    message: name + ": total-span = " + str(total-span) + ", expected <= 32",
  )

  let field-cells = fields.map(it => table.cell(
    colspan: it.span,
    fill: color-cell-fill.at(it.tag, default: none),
    it.body,
  ))

  if total-span == 32 {
    (..field-cells, name-cell(name))
  } else {
    // Fill missing bits in red to indicate the error
    let error-cell = table.cell(colspan: 32 - total-span, fill: red, [])
    (..field-cells, error-cell, name-cell(name))
  }
}

#let empty = (
  table.cell(colspan: 32, []),
  name-cell(""),
)

#let title(body) = table.header(
  level: 2,
  repeat: false,
  table.cell(
    colspan: 32,
    rowspan: 2,
    stroke: (left: none, right: none),
    text(size: 12pt, font: font-heading, weight: weight-heading, body),
  ),
  table.cell(rowspan: 2, fill: none, []),
)

#let inst-table(..content) = {
  set text(font: font-mono, size: 8pt)

  table(
    columns: (1fr,) * 32 + (6fr,),
    rows: 12pt,
    inset: (x, y) => (
      x: if x == 32 { 6pt } else { 0pt },
      y: 4pt,
    ),
    align: (x, y) => horizon + if x != 32 { center } else { left },
    stroke: (x, y) => if y != 0 and x != 32 { 0.25pt + black },

    table.header(
      ..range(32).rev().map(it => text(size: 6pt, str(it))),
      [],
    ),

    ..content.pos().flatten(),
  )
}
