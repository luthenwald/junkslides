//// Small decks for unit tests, written as deck.md text.

import gleam/list
import junkslides/deck.{type Cell, type Deck, type Slide}
import junkslides/file
import junkslides/id.{type IdSupply}

/// Three slides: [a, b, c], [d], [].
pub const text =
  "---
<!-- cell -->
a
<!-- cell -->
b
<!-- notes -->
c
---
<!-- cell -->
d
---
"

pub fn deck() -> #(Deck, IdSupply) {
  let assert Ok(result) = file.parse(text, id.test_supply(1))
  result
}

pub fn slide(deck: Deck, index: Int) -> Slide {
  let assert Ok(slide) = list.drop(deck.slides, index) |> list.first
  slide
}

pub fn cell(deck: Deck, slide_index: Int, index: Int) -> Cell {
  let assert Ok(cell) =
    list.drop(slide(deck, slide_index).cells, index) |> list.first
  cell
}

pub fn sources(deck: Deck) -> List(List(String)) {
  list.map(deck.slides, fn(slide) {
    list.map(slide.cells, fn(cell) { cell.source })
  })
}
