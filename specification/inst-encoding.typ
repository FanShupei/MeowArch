#import "theme.typ": font-mono

#let inst-encoding-grid(..children) = {
  set text(size: 8pt)

  grid(
    columns: (1fr,) * 32 + (4fr,),
    row-gutter: 4pt,
    stroke: (x, y) => if y != 0 and x != 32 { 0.25pt + black },
    inset: (x, y) => (y: if y != 0 { 4pt } else { 0pt }),
    align: center,
    ..range(32).rev().map(bit => text(font: font-mono, size: 6pt, str(bit))),
    [],
    ..children,
  )
}
