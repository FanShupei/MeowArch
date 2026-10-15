#import "theme.typ": font-heading, font-mono, font-text, weight-heading

#let cover-page(date: none, license: none) = page(numbering: none)[
  #show link: set text(fill: blue)

  #let author = context document.author.join(", ")
  #let title = context document.title
  #let version = if sys.inputs.at("status", default: "draft") == "release" {
    // release version
    assert(date != none, message: "Release builds require an explicit date")
    date.display("[year][month][day]")
  } else {
    // draft version
    if date == none {
      date = datetime.today()
    }
    date.display("[year][month][day]") + " (draft)"
  }

  #place(bottom + center)[
    #text(size: 16pt, author)
    #if license != none [
      #v(0.5em)
      #text(size: 12pt, "Licensed under " + license)
    ]
  ]

  #set align(center + horizon)
  #block(width: 80%, spacing: 0pt)[
    #block(spacing: 0pt)[
      #text(size: 32pt, font: font-heading, weight: weight-heading, title)
    ]
    #if version != none {
      place(center, dy: 24pt, text(size: 16pt, [Version: ] + version))
    }
  ]
]

#let heading-numbering(part, ..numbers) = {
  if numbers.pos().len() == 0 {
    numbering("I", part)
  } else {
    numbering("1.1", ..numbers.pos())
  }
}

#let figure-numbering(pattern, number) = {
  let chapter = counter(heading).get().at(1, default: 0)
  numbering(pattern, chapter, number)
}

#let divider-heading(it) = context {
  pagebreak(weak: true)
  page(footer: none)[
    #align(center + horizon)[
      #if it.numbering != none [
        #text(size: 18pt)[
          #it.supplement~#counter(heading).display(it.numbering)
        ]
        #v(1em)
      ]
      #block(width: 80%)[
        #text(size: 24pt, it.body)
      ]
    ]
  ]
}

#let specification(
  title: [],
  author: (),
  date: none,
  license: none,
  bibliography: none,
  revision-history: none,
  body,
) = {
  set document(title: title, author: author, date: date)
  set page(paper: "a4")

  set text(font: font-text, size: 12pt, weight: "regular")
  show heading: set text(font: font-heading, weight: weight-heading)

  // Reset raw to the same size as normal text
  show raw: set text(font: font-mono, size: 1em / 0.8)

  cover-page(date: date, license: license)

  set page(numbering: "i")
  counter(page).update(1)

  set heading(numbering: heading-numbering)
  show heading.where(level: 1): set heading(supplement: "Part")
  show heading.where(level: 2): set heading(supplement: "Chapter")

  if revision-history != none {
    set heading(numbering: none, supplement: none)
    show heading.where(level: 1): set block(below: 15pt)
    show heading.where(level: 2): set heading(outlined: false)
    show heading.where(level: 2): set text(size: 12pt, weight: "bold")
    show heading.where(level: 2): set block(above: 1em, below: 0.5em)

    revision-history

    pagebreak()
  }

  context {
    show outline.entry.where(level: 1): set block(above: par.spacing)
    show outline.entry.where(level: 1): set text(weight: "medium")
    outline(depth: 3, indent: auto)
  }

  pagebreak()
  set page(numbering: "1")
  counter(page).update(1)

  show ref: set text(fill: blue)
  show link: set text(fill: blue)

  set table(stroke: 0.5pt)
  set figure(numbering: figure-numbering.with("1.1"))
  show figure.caption: set text(size: 10pt)
  show figure.where(kind: table): set figure.caption(position: top)
  show figure.where(kind: raw): set figure.caption(position: top)

  {
    show heading.where(level: 1): divider-heading
    show heading.where(level: 2): set text(size: 20pt)
    show heading.where(level: 3): set text(size: 16pt)
    show heading.where(level: 4): set text(size: 14pt)
    show heading.where(level: 2): it => {
      pagebreak(weak: true)
      for kind in (image, table, raw) {
        counter(figure.where(kind: kind)).update(0)
      }
      it
    }
    show heading.where(level: 2): set block(below: 1.5em)
    show heading.where(level: 3): set block(below: 1em, above: 1.5em)
    show heading.where(level: 4): set block(below: 1em, above: 1.25em)

    body
  }

  if bibliography != none {
    pagebreak()

    bibliography
  }
}

#let part(title, body) = {
  heading(level: 1, title)

  set heading(offset: 1)

  body
}

#let appendix(body) = {
  heading(level: 1, numbering: none, supplement: none, [Appendices])
  counter(heading).update(0)

  set heading(
    offset: 1,
    numbering: (part, ..numbers) => {
      numbering("A.1", ..numbers.pos())
    },
  )
  show heading.where(level: 2): set heading(supplement: "Appendix")
  set figure(numbering: figure-numbering.with("A.1"))

  body
}
