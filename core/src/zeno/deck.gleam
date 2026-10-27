//// The deck: slides of cells (03-data-model.md, Deck).

import gleam/list
import gleam/result
import zeno/id.{type CellTag, type Id, type IdSet, type SlideTag}
import zeno/line

pub type Kind {
  Content
  Notes
}

pub type Cell {
  Cell(id: Id(CellTag), kind: Kind, source: String)
}

pub type Slide {
  Slide(id: Id(SlideTag), cells: List(Cell))
}

pub type Deck {
  Deck(slides: List(Slide))
}

pub type Position {
  /// Index among the slide's cells, 0 to length inclusive.
  Position(slide: Id(SlideTag), index: Int)
}

/// Where a cell sits: its slide, its index in that slide, and the cell.
pub type Location {
  Location(slide: Slide, index: Int, cell: Cell)
}

/// A broken deck invariant.
pub type Violation {
  NoSlides
  DuplicateId
  StructuralLine(cell: Id(CellTag))
  BlankEdge(cell: Id(CellTag))
}

pub fn cells(deck: Deck) -> List(Cell) {
  list.flat_map(deck.slides, fn(slide) { slide.cells })
}

pub fn cell_ids(deck: Deck) -> List(Id(CellTag)) {
  list.map(cells(deck), fn(cell) { cell.id })
}

pub fn slide_ids(deck: Deck) -> List(Id(SlideTag)) {
  list.map(deck.slides, fn(slide) { slide.id })
}

/// Every live ID, cell and slide.
pub fn ids(deck: Deck) -> IdSet {
  let set = list.fold(slide_ids(deck), id.empty_set(), id.insert)
  list.fold(cell_ids(deck), set, id.insert)
}

pub fn find_cell(deck: Deck, cell: Id(CellTag)) -> Result(Location, Nil) {
  list.find_map(deck.slides, fn(slide) {
    list.index_map(slide.cells, fn(c, i) { #(c, i) })
    |> list.find(fn(pair) { pair.0.id == cell })
    |> result.map(fn(pair) { Location(slide:, index: pair.1, cell: pair.0) })
  })
}

pub fn find_slide(deck: Deck, slide: Id(SlideTag)) -> Result(Slide, Nil) {
  list.find(deck.slides, fn(s) { s.id == slide })
}

/// A source satisfies invariants 3 and 4: no structural line, no leading
/// or trailing blank line.
pub fn valid_source(source: String) -> Bool {
  source_violations(source) == #(False, False)
}

fn source_violations(source: String) -> #(Bool, Bool) {
  let structural = list.any(line.lines(source), line.is_structural)
  let blank_edge = line.trim_blank_lines(source) != source
  #(structural, blank_edge)
}

/// All broken invariants, in a stable order. An empty list means the deck
/// is valid.
pub fn violations(deck: Deck) -> List(Violation) {
  let no_slides = case deck.slides {
    [] -> [NoSlides]
    _ -> []
  }
  let all = list.length(slide_ids(deck)) + list.length(cell_ids(deck))
  let duplicates = case all == id.size(ids(deck)) {
    True -> []
    False -> [DuplicateId]
  }
  let sources =
    list.flat_map(cells(deck), fn(cell) {
      let #(structural, blank_edge) = source_violations(cell.source)
      list.flatten([
        case structural {
          True -> [StructuralLine(cell.id)]
          False -> []
        },
        case blank_edge {
          True -> [BlankEdge(cell.id)]
          False -> []
        },
      ])
    })
  list.flatten([no_slides, duplicates, sources])
}
