//// The laws of 03-data-model.md as qcheck properties over random decks and
//// random sequences of operations, including invalid ones, layout ops,
//// typed edits through `normalize_edit`, undo and redo.

import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import qcheck.{type Generator}
import zeno/deck.{
  type Cell, type Deck, Cell, Content, Deck, Notes, Position, Slide,
}
import zeno/file
import zeno/history.{type History}
import zeno/id.{type CellTag, type Id, type IdSupply}
import zeno/layout.{type Layout}
import zeno/line
import zeno/op.{type Effect, type Op}

// Generators ---------------------------------------------------------------

/// Lines for cell bodies: dialect constructs, blank lines, and lines that
/// look like structural lines but are not.
const pool = [
  "a", "Hello _world_", "# Title", "- item", "  - nested", "1. one", "```",
  "```gleam", "> quote", "", "  ", "--", "--- ", " ---", "<!-- cell -->x",
  "<!-- slide -->", "<!-- deck v01 -->", "\\", "{.x}", "ü", "e\u{301}", "\t",
]

/// Lines a person might type, including structural ones.
const typed_pool = ["---", "<!-- cell -->", "<!-- notes -->", "<!-- deck v1 -->"]

fn text(indexes: List(Int), lines: List(String)) -> String {
  list.map(indexes, fn(i) {
    let assert Ok(l) = list.drop(lines, i % list.length(lines)) |> list.first
    l
  })
  |> string.join("\n")
}

fn source(indexes: List(Int)) -> String {
  text(indexes, pool) |> line.trim_blank_lines
}

fn lines_gen() -> Generator(List(Int)) {
  qcheck.generic_list(qcheck.bounded_int(0, 40), qcheck.bounded_int(0, 5))
}

type Spec =
  List(List(#(Bool, List(Int))))

fn spec_gen() -> Generator(Spec) {
  let cell = qcheck.tuple2(qcheck.bool(), lines_gen())
  let slide = qcheck.generic_list(cell, qcheck.bounded_int(0, 4))
  qcheck.generic_list(slide, qcheck.bounded_int(1, 4))
}

fn build(spec: Spec, supply: IdSupply) -> #(Deck, IdSupply) {
  let #(supply, slides) =
    list.map_fold(spec, supply, fn(supply, cells) {
      let #(slide_id, supply) = id.fresh(supply, id.empty_set())
      let #(supply, cells) =
        list.map_fold(cells, supply, fn(supply, c) {
          let #(cell_id, supply) = id.fresh(supply, id.empty_set())
          let kind = case c.0 {
            True -> Notes
            False -> Content
          }
          #(supply, Cell(cell_id, kind, source(c.1)))
        })
      #(supply, Slide(slide_id, cells))
    })
  #(Deck(slides), supply)
}

type Step {
  Step(kind: Int, a: Int, b: Int, lines: List(Int))
}

fn step_gen() -> Generator(Step) {
  qcheck.map4(
    qcheck.bounded_int(0, 19),
    qcheck.bounded_int(0, 60),
    qcheck.bounded_int(0, 60),
    lines_gen(),
    Step,
  )
}

type Scenario {
  Scenario(spec: Spec, steps: List(Step))
}

fn scenario_gen() -> Generator(Scenario) {
  qcheck.map2(
    spec_gen(),
    qcheck.generic_list(step_gen(), qcheck.bounded_int(0, 25)),
    Scenario,
  )
}

fn config() {
  qcheck.default_config() |> qcheck.with_test_count(250)
}

// The run --------------------------------------------------------------------

type Model {
  Model(
    deck: Deck,
    layout: Layout,
    history: History,
    supply: IdSupply,
    clipboard: Option(Cell),
    clock: Int,
  )
}

/// What a step turns into, given the current model.
type Action {
  Ops(List(Op))
  Typed(cell: Id(CellTag), text: String)
  LayoutAction(layout.LayoutOp)
  UndoAction
  RedoAction
}

fn now(model: Model) -> Timestamp {
  timestamp.add(timestamp.unix_epoch, duration.seconds(model.clock))
}

fn nth(items: List(a), n: Int) -> Option(a) {
  case items {
    [] -> None
    _ ->
      list.drop(items, n % list.length(items))
      |> list.first
      |> option.from_result
  }
}

fn foreign_cell() -> Id(CellTag) {
  let #(foreign, _) = id.fresh(id.test_supply(900), id.empty_set())
  foreign
}

fn action(model: Model, step: Step) -> Action {
  let deck = model.deck
  let cell = nth(deck.cells(deck), step.a) |> option.map(fn(c) { c.id })
  let cell_id = option.unwrap(cell, foreign_cell())
  let assert Some(slide) = nth(deck.slides, step.a)
  let assert Some(target) = nth(deck.slides, step.b)
  // Sometimes one past the end, to exercise range errors.
  let position = fn(s: deck.Slide, n: Int) {
    Position(s.id, n % { list.length(s.cells) + 2 })
  }
  case step.kind {
    0 -> Ops([op.EditText(cell_id, source(step.lines))])
    1 -> Ops([op.Insert(position(target, step.b), Content)])
    2 -> Ops([op.Delete(cell_id)])
    3 -> {
      let length = case deck.find_cell(deck, cell_id) {
        Ok(found) -> string.length(found.cell.source)
        Error(Nil) -> 0
      }
      Ops([op.Split(cell_id, step.b % { length + 2 })])
    }
    4 -> Ops([op.MergeWithNext(cell_id)])
    5 -> Ops([op.Move(cell_id, position(target, step.b))])
    6 -> Ops([op.Duplicate(cell_id)])
    7 -> Ops([op.CycleKind(cell_id)])
    8 -> {
      let copied = case deck.find_cell(deck, cell_id) {
        Ok(found) -> Some(found.cell)
        Error(Nil) -> None
      }
      case option.or(model.clipboard, copied) {
        Some(pasted) -> Ops([op.Paste(pasted, position(target, step.b))])
        None -> Ops([op.Insert(position(target, 0), Notes)])
      }
    }
    9 -> Ops([op.InsertBreak(position(slide, step.b))])
    10 -> Ops([op.RemoveBreak(slide.id)])
    11 ->
      Ops([op.MoveSlide(slide.id, step.b % { list.length(deck.slides) + 1 })])
    12 -> Ops([op.DeleteSlide(slide.id)])
    13 | 14 -> {
      let mixed = list.append(pool, typed_pool)
      Typed(cell_id, text(step.lines, mixed))
    }
    15 -> {
      let area =
        // Pixels, some of them too far off the slide or too large.
        layout.Area(
          step.a * 97 % 2000 - 60,
          step.b * 53 % 1150 - 60,
          step.b * 89 % 2000,
          step.a * 61 % 1150,
        )
      LayoutAction(layout.Place(cell_id, area))
    }
    16 ->
      LayoutAction(case step.b % 3 {
        0 -> layout.Unplace(cell_id)
        1 -> layout.SetVariant(cell_id, nth(["large", "quiet"], step.b))
        _ -> layout.SetAlign(cell_id, nth([layout.Start, layout.End], step.b))
      })
    17 -> Ops([op.Delete(foreign_cell())])
    18 -> UndoAction
    _ ->
      case step.b % 4 {
        0 -> LayoutAction(layout.PurgeOrphans)
        _ -> RedoAction
      }
  }
}

fn run(model: Model, step: Step) -> Model {
  let model = Model(..model, clock: model.clock + 1)
  case action(model, step) {
    Ops(ops) -> apply_ops(model, ops)
    Typed(cell, typed) ->
      case op.normalize_edit(model.deck, cell, typed) {
        Error(_) -> model
        Ok(ops) -> {
          law_normalisation(ops)
          apply_ops(model, ops)
        }
      }
    LayoutAction(layout_op) ->
      case layout.apply(model.layout, model.deck, layout_op) {
        Error(_) -> model
        Ok(after) -> commit(model, model.deck, after, model.supply)
      }
    UndoAction ->
      case history.undo(model.history) {
        None -> model
        Some(#(deck, layout, history)) ->
          Model(..model, deck:, layout:, history:)
      }
    RedoAction ->
      case history.redo(model.history) {
        None -> model
        Some(#(deck, layout, history)) ->
          Model(..model, deck:, layout:, history:)
      }
  }
  |> check_state
}

fn apply_ops(model: Model, ops: List(Op)) -> Model {
  case op.apply_all(model.deck, ops, model.supply) {
    // Law 8 holds by construction: the model is kept as it was.
    Error(_) -> model
    Ok(#(deck, effects, supply)) -> {
      law_honest_effects(model.deck, deck, effects)
      let layout = layout.fold_effects(model.layout, effects, now(model))
      let clipboard = case ops {
        [op.Delete(gone)] ->
          case deck.find_cell(model.deck, gone) {
            Ok(found) -> Some(found.cell)
            Error(Nil) -> model.clipboard
          }
        _ -> model.clipboard
      }
      Model(..commit(model, deck, layout, supply), clipboard:)
    }
  }
}

/// Records a step and checks law 5 right away.
fn commit(model: Model, deck: Deck, layout: Layout, supply: IdSupply) -> Model {
  let history = history.record(model.history, deck, layout)
  let assert Some(#(before_deck, before_layout, undone)) = history.undo(history)
  assert before_deck == model.deck
  assert before_layout == model.layout
  let assert Some(#(redone_deck, redone_layout, _)) = history.redo(undone)
  assert redone_deck == deck
  assert redone_layout == layout
  Model(..model, deck:, layout:, history:, supply:)
}

// Laws ---------------------------------------------------------------------

/// Law 1.
fn law_honest_effects(before: Deck, after: Deck, effects: List(Effect)) {
  let retired =
    list.filter_map(effects, fn(e) {
      case e {
        op.Retired(c) -> Ok(c)
        _ -> Error(Nil)
      }
    })
  let added =
    list.filter_map(effects, fn(e) {
      case e {
        op.Fresh(c, _) | op.Revived(c) -> Ok(c)
        _ -> Error(Nil)
      }
    })
  let expected =
    deck.cell_ids(before)
    |> list.filter(fn(c) { !list.contains(retired, c) })
    |> list.append(added)
  assert sorted(expected) == sorted(deck.cell_ids(after))
  let slides_retired =
    list.filter_map(effects, fn(e) {
      case e {
        op.SlideRetired(s) -> Ok(s)
        _ -> Error(Nil)
      }
    })
  let slides_added =
    list.filter_map(effects, fn(e) {
      case e {
        op.SlideFresh(s) -> Ok(s)
        _ -> Error(Nil)
      }
    })
  let expected =
    deck.slide_ids(before)
    |> list.filter(fn(s) { !list.contains(slides_retired, s) })
    |> list.append(slides_added)
  assert sorted(expected) == sorted(deck.slide_ids(after))
}

fn sorted(ids: List(Id(tag))) -> List(Id(tag)) {
  list.sort(ids, id.compare)
}

/// Law 9.
fn law_normalisation(ops: List(Op)) {
  list.each(ops, fn(o) {
    case o {
      op.EditText(source:, ..) -> {
        assert !list.any(line.lines(source), line.is_structural)
      }
      _ -> Nil
    }
  })
}

/// Laws 2, 3, 4, 6 and 7, after every step.
fn check_state(model: Model) -> Model {
  let Model(deck:, layout:, ..) = model
  // Laws 2 and 3.
  assert deck.violations(deck) == []
  // Law 4.
  let printed = file.print(deck)
  let assert Ok(#(parsed, _)) = file.parse(printed, id.test_supply(500))
  assert parsed == deck
  assert file.print(parsed) == printed
  // Law 6.
  let live = deck.ids(deck)
  assert list.all(dict.keys(layout.cells), id.contains(live, _))
  assert list.all(dict.keys(layout.slides), id.contains(live, _))
  assert list.all(layout.orphans, fn(orphan) {
    case orphan {
      layout.CellOrphan(id: c, ..) -> !id.contains(live, c)
      layout.SlideOrphan(id: s, ..) -> !id.contains(live, s)
    }
  })
  // Law 7.
  assert list.all(dict.values(layout.cells), fn(record) {
    case record.place {
      Some(area) -> layout.valid_area(area)
      None -> True
    }
  })
  model
}

pub fn laws_over_random_runs_test() {
  use Scenario(spec:, steps:) <- qcheck.run(config(), scenario_gen())
  let #(deck, supply) = build(spec, id.test_supply(1))
  let start =
    Model(
      deck,
      layout.empty(),
      history.new(deck, layout.empty()),
      supply,
      None,
      0,
    )
    |> check_state
  let _ = list.fold(steps, start, run)
  Nil
}

/// Law 10: cut then paste restores the ID and the layout record, wherever
/// the paste goes.
pub fn law_cut_and_paste_test() {
  let gen =
    qcheck.tuple4(
      spec_gen(),
      qcheck.bounded_int(0, 60),
      qcheck.bounded_int(0, 60),
      qcheck.bounded_int(0, 60),
    )
  use #(spec, a, b, n) <- qcheck.run(config(), gen)
  let #(deck, supply) = build(spec, id.test_supply(1))
  case nth(deck.cells(deck), a) {
    None -> Nil
    Some(cut) -> {
      let assert Ok(styled) =
        layout.apply(
          layout.empty(),
          deck,
          layout.Place(cut.id, layout.Area(60, 120, 180, 240)),
        )
      let assert Ok(styled) =
        layout.apply(styled, deck, layout.SetVariant(cut.id, Some("quiet")))
      let t = timestamp.unix_epoch
      let assert Ok(#(without, effects, supply)) =
        op.apply(deck, op.Delete(cut.id), supply)
      let orphaned = layout.fold_effects(styled, effects, t)
      let assert Some(target) = nth(without.slides, b)
      let at = Position(target.id, n % { list.length(target.cells) + 1 })
      let assert Ok(#(back, effects, _)) =
        op.apply(without, op.Paste(cut, at), supply)
      let restored = layout.fold_effects(orphaned, effects, t)
      assert deck.find_cell(back, cut.id) |> result_cell == Some(cut)
      assert layout.record(restored, cut.id) == layout.record(styled, cut.id)
      assert restored.orphans == []
    }
  }
}

fn result_cell(found: Result(deck.Location, Nil)) -> Option(Cell) {
  case found {
    Ok(location) -> Some(location.cell)
    Error(Nil) -> None
  }
}

/// Law 4 also for imported text: whatever a file says, once parsed, prints
/// to a canonical file that parses back to the same deck.
pub fn law_round_trip_of_any_text_test() {
  let mixed = list.append(pool, typed_pool)
  let gen =
    qcheck.generic_list(qcheck.bounded_int(0, 60), qcheck.bounded_int(0, 30))
    |> qcheck.map(fn(indexes) { text(indexes, mixed) })
  use input <- qcheck.run(config(), gen)
  case file.parse(input, id.test_supply(1)) {
    Error(_) -> Nil
    Ok(#(deck, _)) -> {
      assert deck.violations(deck) == []
      let printed = file.print(deck)
      let assert Ok(#(parsed, _)) = file.parse(printed, id.test_supply(2))
      assert parsed == deck
      assert file.print(parsed) == printed
    }
  }
}

/// Law 3 for `Split` at every position of random sources: a cut may never
/// leave a structural line (` ---` cut after the space, `<!-- cell -->x`
/// cut before the `x`).
pub fn law_split_everywhere_test() {
  use lines <- qcheck.run(config(), lines_gen())
  let #(deck, supply) = build([[#(False, lines)]], id.test_supply(1))
  let assert [Slide(cells: [cell], ..)] = deck.slides
  list.each(positions(string.length(cell.source)), fn(at) {
    case op.apply(deck, op.Split(cell.id, at), supply) {
      Ok(#(after, _, _)) -> {
        assert deck.violations(after) == []
      }
      Error(_) -> Nil
    }
  })
}

fn positions(length: Int) -> List(Int) {
  do_positions(length, [])
}

fn do_positions(n: Int, acc: List(Int)) -> List(Int) {
  case n < 0 {
    True -> acc
    False -> do_positions(n - 1, [n, ..acc])
  }
}
