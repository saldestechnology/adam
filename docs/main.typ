// Compiled AI Whitepaper — main entry point
// Compile: typst compile docs/main.typ docs/whitepaper.pdf

#set page(
  paper: "a4",
  margin: (top: 2.5cm, bottom: 2.5cm, left: 2.5cm, right: 2.5cm),
)

#set par(justify: true)

#set text(
  font: "New Computer Modern",
  size: 11pt,
)

#set heading(numbering: "1.1")

#show heading: it => block([
  #v(0.5cm)
  #it
  #v(0.3cm)
])

#include "sections/00-title.typ"

#pagebreak()

#include "sections/01-intro.typ"
#include "sections/02-spec-driven.typ"
#include "sections/03-architecture.typ"
#include "sections/04-ralph-loop.typ"
#include "sections/05-corpus-fallback.typ"
#include "sections/06-harvest.typ"
#include "sections/07-quality.typ"
#include "sections/08-distributed.typ"
#include "sections/09-results.typ"
#include "sections/10-future.typ"
