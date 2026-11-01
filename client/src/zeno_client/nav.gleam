//// Selection in the cells pane and the positions that command-mode keys
//// act on (05-editor.md, Command mode). Pure, so it is tested without a
//// browser.

import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import zeno/deck.{type Deck, type Position, type Slide, Position}
import zeno/id.{type CellTag, type Id, type SlideTag}
import zeno/render

/// What is selected: a cell, or a slide without cells, which has nothing
/// else to select.
pub type Selection {
  OnCell(cell: Id(CellTag))
  OnSlide(slide: Id(SlideTag))
}

/// Every selectable place, in deck order.
pub fn items(deck: Deck) -> List(Selection) {
  list.flat_map(deck.slides, slide_items)
}

fn slide_items(slide: Slide) -> List(Selection) {
  case slide.cells {
    [] -> [OnSlide(slide.id)]
    cells -> list.map(cells, fn(cell) { OnCell(cell.id) })
  }
}

pub fn first(deck: Deck) -> Selection {
  case items(deck) {
    [item, ..] -> item
    // A deck always has a slide; this is only reached for an invalid one.
    [] -> panic as "a deck without slides"
  }
}

pub fn exists(deck: Deck, selection: Selection) -> Bool {
  list.contains(items(deck), selection)
}

/// The selection after the deck changed: kept if it still exists, otherwise
/// the place at the same position, or the last one.
pub fn reselect(old: Deck, new: Deck, selection: Selection) -> Selection {
  use <- bool.guard(exists(new, selection), selection)
  let index = index_of(items(old), selection) |> result.unwrap(0)
  let new_items = items(new)
  let last = list.length(new_items) - 1
  case list.drop(new_items, int.clamp(index, 0, last)) {
    [item, ..] -> item
    [] -> first(new)
  }
}

pub fn next(deck: Deck, selection: Selection) -> Selection {
  step(items(deck), selection)
}

pub fn previous(deck: Deck, selection: Selection) -> Selection {
  step(list.reverse(items(deck)), selection)
}

fn step(items: List(Selection), selection: Selection) -> Selection {
  case list.drop_while(items, fn(item) { item != selection }) {
    [_, after, ..] -> after
    _ -> selection
  }
}

/// The first place on the next slide, or the selection on the last slide.
pub fn next_slide(deck: Deck, selection: Selection) -> Selection {
  jump_slide(deck, selection, 1)
}

/// The first place on the previous slide, or the selection on the first.
pub fn previous_slide(deck: Deck, selection: Selection) -> Selection {
  jump_slide(deck, selection, -1)
}

fn jump_slide(deck: Deck, selection: Selection, by: Int) -> Selection {
  {
    use index <- result.try(slide_index(deck, selection))
    use slide <- result.try(list.drop(deck.slides, index + by) |> list.first)
    case index + by >= 0 {
      True -> list.first(slide_items(slide))
      False -> Error(Nil)
    }
  }
  |> result.unwrap(selection)
}

/// The index of the selection's slide.
pub fn slide_index(deck: Deck, selection: Selection) -> Result(Int, Nil) {
  let slide = slide_of(deck, selection)
  use slide <- result.try(slide)
  index_of(deck.slides |> list.map(fn(s) { s.id }), slide)
}

pub fn slide_of(deck: Deck, selection: Selection) -> Result(Id(SlideTag), Nil) {
  case selection {
    OnSlide(slide) -> Ok(slide)
    OnCell(cell) ->
      deck.find_cell(deck, cell) |> result.map(fn(at) { at.slide.id })
  }
}

/// Where a new cell goes: right below the selection, or right above it.
pub fn below(deck: Deck, selection: Selection) -> Result(Position, Nil) {
  case selection {
    OnSlide(slide) -> Ok(Position(slide, 0))
    OnCell(cell) -> {
      use at <- result.map(deck.find_cell(deck, cell))
      Position(at.slide.id, at.index + 1)
    }
  }
}

pub fn above(deck: Deck, selection: Selection) -> Result(Position, Nil) {
  case selection {
    OnSlide(slide) -> Ok(Position(slide, 0))
    OnCell(cell) -> {
      use at <- result.map(deck.find_cell(deck, cell))
      Position(at.slide.id, at.index)
    }
  }
}

/// Where `Move` takes a cell one step down: past the next cell, or to the
/// top of the next slide. The position counts the slide's cells without the
/// moved one, as `Move` does.
pub fn move_down(deck: Deck, cell: Id(CellTag)) -> Result(Position, Nil) {
  use at <- result.try(deck.find_cell(deck, cell))
  case at.index + 1 < list.length(at.slide.cells) {
    True -> Ok(Position(at.slide.id, at.index + 1))
    False -> {
      use next <- result.map(neighbour_slide(deck, at.slide.id, 1))
      Position(next.id, 0)
    }
  }
}

/// One step up: above the previous cell, or to the end of the previous
/// slide.
pub fn move_up(deck: Deck, cell: Id(CellTag)) -> Result(Position, Nil) {
  use at <- result.try(deck.find_cell(deck, cell))
  case at.index > 0 {
    True -> Ok(Position(at.slide.id, at.index - 1))
    False -> {
      use previous <- result.map(neighbour_slide(deck, at.slide.id, -1))
      Position(previous.id, list.length(previous.cells))
    }
  }
}

fn neighbour_slide(
  deck: Deck,
  slide: Id(SlideTag),
  by: Int,
) -> Result(Slide, Nil) {
  use index <- result.try(index_of(list.map(deck.slides, fn(s) { s.id }), slide))
  case index + by >= 0 {
    True -> list.drop(deck.slides, index + by) |> list.first
    False -> Error(Nil)
  }
}

/// What to select once a cell is cut: the next cell on its slide, else the
/// previous one, else the slide, which is then empty.
pub fn after_removal(deck: Deck, cell: Id(CellTag)) -> Selection {
  case deck.find_cell(deck, cell) {
    Error(Nil) -> first(deck)
    Ok(at) -> {
      let others = list.filter(at.slide.cells, fn(c) { c.id != cell })
      case list.drop(others, at.index), list.last(others) {
        [next, ..], _ -> OnCell(next.id)
        [], Ok(last) -> OnCell(last.id)
        [], Error(Nil) -> OnSlide(at.slide.id)
      }
    }
  }
}

/// Slide numbers as the editor shows them: `01/12`, zero-padded to the
/// width of the total and at least two digits.
pub fn number(index: Int, total: Int) -> String {
  render.number(index, total)
}

fn index_of(items: List(a), item: a) -> Result(Int, Nil) {
  list.index_map(items, fn(x, i) { #(x, i) })
  |> list.find(fn(pair) { pair.0 == item })
  |> result.map(fn(pair) { pair.1 })
}
