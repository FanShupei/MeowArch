// Explicit references to numbered elements in another part.
#let cross-ref(target) = context {
  let element = query(target).first()
  let part = counter(heading).at(element.location()).first()

  // Appendices reset the part counter to zero.
  assert(part > 0, message: "cross-ref requires a target in a numbered part")

  ref(
    target,
    supplement: [Part~#numbering("I", part), #element.supplement],
  )
}
