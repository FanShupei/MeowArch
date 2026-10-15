#import "template.typ": appendix, part, specification

#show: specification.with(
  title: [Meow Architecture Specification],
  author: "Shupei Fan",
  date: datetime(year: 2026, month: 10, day: 12),
  license: link("https://creativecommons.org/licenses/by/4.0/")[CC BY 4.0],
  bibliography: bibliography("ref.yaml"),
  revision-history: include "revision-history.typ",
)

#part("Unprivileged Architecture")[
  #include "unpriv/ch01-introduction.typ"
]

#part("Privileged Architecture")[
  #include "priv/ch01-introduction.typ"
]

#part("Processor-specific Application Binary Interface")[
  #include "psabi/ch01-introduction.typ"
]

#appendix[
  #include "appendices/a01-instlist.typ"
]
