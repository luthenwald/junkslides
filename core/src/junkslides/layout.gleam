//// Layout records keyed by ID, effect folding and layout ops
//// (03-data-model.md, Layout; 04-layout.md).

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/time/timestamp.{type Timestamp}
import junkslides/deck.{type Deck}
import junkslides/id.{type CellTag, type Id, type SlideTag}
import junkslides/op.{
  type Effect, type OpError, AreaOffSlide, Fresh, Retired, Revived, SlideFresh,
  SlideRetired, UnknownCell, UnknownSlide,
}

/// The slide's design space in pixels (04-layout.md, The slide).
pub const width = 1920

pub const height = 1080

/// How much of a placed cell stays on the slide each way, in pixels, so
/// that it can always be grabbed again.
pub const min_visible = 10

/// A placed cell's box in design pixels, relative to the slide's top left
/// corner. Parts of it may lie off the slide.
pub type Area {
  Area(x: Int, y: Int, w: Int, h: Int)
}

pub type Align {
  Start
  Center
  End
}

pub type CellRecord {
  CellRecord(place: Option(Area), variant: Option(String), align: Option(Align))
}

/// What a slide shows of its furniture (D33). `number` is the slide number;
/// `marks` is whatever the theme draws on every slide, such as a rule or a
/// progress mark. Both are shown unless switched off.
pub type SlideRecord {
  SlideRecord(number: Bool, marks: Bool)
}

pub const no_slide_record = SlideRecord(number: True, marks: True)

pub type Orphan {
  CellOrphan(id: Id(CellTag), record: CellRecord, retired_at: Timestamp)
  SlideOrphan(id: Id(SlideTag), record: SlideRecord, retired_at: Timestamp)
}

pub type Layout {
  Layout(
    cells: Dict(Id(CellTag), CellRecord),
    slides: Dict(Id(SlideTag), SlideRecord),
    orphans: List(Orphan),
  )
}

pub type LayoutOp {
  Place(cell: Id(CellTag), area: Area)
  Unplace(cell: Id(CellTag))
  SetVariant(cell: Id(CellTag), variant: Option(String))
  SetAlign(cell: Id(CellTag), align: Option(Align))
  SetSlide(slide: Id(SlideTag), record: SlideRecord)
  PurgeOrphans
}

pub fn empty() -> Layout {
  Layout(dict.new(), dict.new(), [])
}

const no_record = CellRecord(None, None, None)

pub fn record(layout: Layout, cell: Id(CellTag)) -> CellRecord {
  case dict.get(layout.cells, cell) {
    Ok(record) -> record
    Error(Nil) -> no_record
  }
}

pub fn slide_record(layout: Layout, slide: Id(SlideTag)) -> SlideRecord {
  case dict.get(layout.slides, slide) {
    Ok(record) -> record
    Error(Nil) -> no_slide_record
  }
}

/// At least one pixel each way and at most the slide's size, with at least
/// `min_visible` pixels on the slide in each direction.
pub fn valid_area(area: Area) -> Bool {
  area.w >= 1
  && area.h >= 1
  && area.w <= width
  && area.h <= height
  && area.x + area.w >= min_visible
  && area.y + area.h >= min_visible
  && area.x <= width - min_visible
  && area.y <= height - min_visible
}

/// A record with no fields is not stored.
fn put_cell(layout: Layout, cell: Id(CellTag), record: CellRecord) -> Layout {
  case record == no_record {
    True -> Layout(..layout, cells: dict.delete(layout.cells, cell))
    False -> Layout(..layout, cells: dict.insert(layout.cells, cell, record))
  }
}

// Effects ------------------------------------------------------------------

pub fn fold_effects(
  layout: Layout,
  effects: List(Effect),
  now: Timestamp,
) -> Layout {
  list.fold(effects, layout, fn(layout, effect) {
    fold_effect(layout, effect, now)
  })
}

fn fold_effect(layout: Layout, effect: Effect, now: Timestamp) -> Layout {
  case effect {
    Fresh(inherit_style: None, ..) | SlideFresh(_) -> layout
    Fresh(cell:, inherit_style: Some(source)) -> {
      let from = record(layout, source)
      put_cell(layout, cell, CellRecord(None, from.variant, from.align))
    }
    Retired(cell:) -> retire_cell(layout, cell, now)
    Revived(cell:) -> revive_cell(layout, cell)
    SlideRetired(slide:) -> retire_slide(layout, slide, now)
  }
}

fn retire_cell(layout: Layout, cell: Id(CellTag), now: Timestamp) -> Layout {
  case dict.get(layout.cells, cell) {
    Error(Nil) -> layout
    Ok(record) ->
      Layout(
        ..layout,
        cells: dict.delete(layout.cells, cell),
        orphans: list.append(without_orphan(layout.orphans, cell), [
          CellOrphan(cell, record, now),
        ]),
      )
  }
}

fn retire_slide(layout: Layout, slide: Id(SlideTag), now: Timestamp) -> Layout {
  case dict.get(layout.slides, slide) {
    Error(Nil) -> layout
    Ok(record) ->
      Layout(
        ..layout,
        slides: dict.delete(layout.slides, slide),
        orphans: list.append(without_orphan(layout.orphans, slide), [
          SlideOrphan(slide, record, now),
        ]),
      )
  }
}

fn revive_cell(layout: Layout, cell: Id(CellTag)) -> Layout {
  let orphan =
    list.find_map(layout.orphans, fn(orphan) {
      case orphan {
        CellOrphan(id:, record:, ..) if id == cell -> Ok(record)
        _ -> Error(Nil)
      }
    })
  case orphan {
    Error(Nil) -> layout
    Ok(record) ->
      Layout(
        ..put_cell(layout, cell, record),
        orphans: without_orphan(layout.orphans, cell),
      )
  }
}

fn revive_slide(layout: Layout, slide: Id(SlideTag)) -> Layout {
  let orphan =
    list.find_map(layout.orphans, fn(orphan) {
      case orphan {
        SlideOrphan(id:, record:, ..) if id == slide -> Ok(record)
        _ -> Error(Nil)
      }
    })
  case orphan {
    Error(Nil) -> layout
    Ok(record) ->
      Layout(
        ..layout,
        slides: dict.insert(layout.slides, slide, record),
        orphans: without_orphan(layout.orphans, slide),
      )
  }
}

fn without_orphan(orphans: List(Orphan), gone: Id(tag)) -> List(Orphan) {
  list.filter(orphans, fn(orphan) {
    case orphan {
      CellOrphan(id: cell, ..) -> !id.same(cell, gone)
      SlideOrphan(id: slide, ..) -> !id.same(slide, gone)
    }
  })
}

// External edits -----------------------------------------------------------

/// Folds an external edit of deck.md into the layout: the effects of
/// replacing `old` by `new`, then the consistency step, which also brings
/// back slide records (there is no effect for a revived slide).
pub fn apply_external(
  layout: Layout,
  old: Deck,
  new: Deck,
  now: Timestamp,
) -> #(Layout, List(Effect)) {
  let effects = external_effects(old, new, layout)
  #(consistency(fold_effects(layout, effects, now), new, now), effects)
}

/// Effects of replacing `old` by `new` when the change came from outside
/// (06-runtime.md, Watching files): IDs gone are retired, new IDs are fresh,
/// and new cell IDs found among the orphans are revived.
pub fn external_effects(old: Deck, new: Deck, layout: Layout) -> List(Effect) {
  let old_ids = deck.ids(old)
  let new_ids = deck.ids(new)
  let orphaned = orphan_ids(layout)
  let slides_gone =
    deck.slide_ids(old)
    |> list.filter(fn(s) { !id.contains(new_ids, s) })
    |> list.map(SlideRetired)
  let slides_new =
    deck.slide_ids(new)
    |> list.filter(fn(s) { !id.contains(old_ids, s) })
    |> list.map(SlideFresh)
  let cells_gone =
    deck.cell_ids(old)
    |> list.filter(fn(c) { !id.contains(new_ids, c) })
    |> list.map(Retired)
  let cells_new =
    deck.cell_ids(new)
    |> list.filter(fn(c) { !id.contains(old_ids, c) })
    |> list.map(fn(c) {
      case id.contains(orphaned, c) {
        True -> Revived(c)
        False -> Fresh(c, None)
      }
    })
  list.flatten([slides_gone, cells_gone, slides_new, cells_new])
}

fn orphan_ids(layout: Layout) -> id.IdSet {
  list.fold(layout.orphans, id.empty_set(), fn(set, orphan) {
    case orphan {
      CellOrphan(id: cell, ..) -> id.insert(set, cell)
      SlideOrphan(id: slide, ..) -> id.insert(set, slide)
    }
  })
}

/// The consistency step on load (02-file-format.md): records whose ID is not
/// live move to the orphans, and orphans whose ID is live again move back.
pub fn consistency(layout: Layout, deck: Deck, now: Timestamp) -> Layout {
  let live = deck.ids(deck)
  let layout =
    dict.keys(layout.cells)
    |> list.filter(fn(c) { !id.contains(live, c) })
    |> list.fold(layout, fn(layout, c) { retire_cell(layout, c, now) })
  let layout =
    dict.keys(layout.slides)
    |> list.filter(fn(s) { !id.contains(live, s) })
    |> list.fold(layout, fn(layout, s) { retire_slide(layout, s, now) })
  list.fold(layout.orphans, layout, fn(layout, orphan) {
    case orphan {
      CellOrphan(id: cell, ..) ->
        case id.contains(live, cell) {
          True -> revive_cell(layout, cell)
          False -> layout
        }
      SlideOrphan(id: slide, ..) ->
        case id.contains(live, slide) {
          True -> revive_slide(layout, slide)
          False -> layout
        }
    }
  })
}

// Layout ops ---------------------------------------------------------------

/// Applies a layout op. The deck is needed to check that the cell is live.
/// Layout ops on a notes cell are allowed; the record is simply inactive.
pub fn apply(
  layout: Layout,
  deck: Deck,
  op: LayoutOp,
) -> Result(Layout, OpError) {
  case op {
    PurgeOrphans -> Ok(Layout(..layout, orphans: []))
    Place(cell:, area:) ->
      case valid_area(area) {
        False -> Error(AreaOffSlide)
        True ->
          update(layout, deck, cell, fn(r) {
            CellRecord(..r, place: Some(area))
          })
      }
    Unplace(cell:) ->
      update(layout, deck, cell, fn(r) { CellRecord(..r, place: None) })
    SetVariant(cell:, variant:) ->
      update(layout, deck, cell, fn(r) { CellRecord(..r, variant:) })
    SetAlign(cell:, align:) ->
      update(layout, deck, cell, fn(r) { CellRecord(..r, align:) })
    // A record with every switch on is not stored.
    SetSlide(slide:, record:) ->
      case deck.find_slide(deck, slide) {
        Error(Nil) -> Error(UnknownSlide(slide))
        Ok(_) ->
          Ok(case record == no_slide_record {
            True -> Layout(..layout, slides: dict.delete(layout.slides, slide))
            False ->
              Layout(
                ..layout,
                slides: dict.insert(layout.slides, slide, record),
              )
          })
      }
  }
}

fn update(
  layout: Layout,
  deck: Deck,
  cell: Id(CellTag),
  change: fn(CellRecord) -> CellRecord,
) -> Result(Layout, OpError) {
  case deck.find_cell(deck, cell) {
    Error(Nil) -> Error(UnknownCell(cell))
    Ok(_) -> Ok(put_cell(layout, cell, change(record(layout, cell))))
  }
}
