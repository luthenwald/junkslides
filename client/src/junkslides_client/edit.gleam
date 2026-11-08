//// Edit mode: turning the text in a cell's text area into ops (05-editor.md,
//// Edit mode). The text area shows the draft as typed; the deck gets the
//// normalised text.

import gleam/int
import gleam/list
import gleam/string
import junkslides/deck.{type Deck}
import junkslides/id.{type CellTag, type Id}
import junkslides/line
import junkslides/op.{type EditProblem, type Op}

/// What to send while the user is still typing. A `---` line splits the
/// cell only on commit, so that a half-typed break does not move text to a
/// new slide; until then nothing is sent.
pub fn while_typing(
  deck: Deck,
  cell: Id(CellTag),
  text: String,
) -> Result(List(Op), EditProblem) {
  case op.normalize_edit(deck, cell, text) {
    Ok([op.EditText(..)] as ops) | Ok([] as ops) -> Ok(ops)
    Ok(_) -> Ok([])
    Error(problem) -> Error(problem)
  }
}

/// What to send when the edit is committed.
pub fn commit(
  deck: Deck,
  cell: Id(CellTag),
  text: String,
) -> Result(List(Op), EditProblem) {
  op.normalize_edit(deck, cell, text)
}

pub type SplitProblem {
  /// The text has a `---` line; commit it first.
  HasBreak
  Problem(EditProblem)
}

/// Splits the cell at the cursor, which the browser gives in UTF-16 code
/// units of the text as typed. The text is committed first, so the split
/// position is moved past any leading blank lines that normalising drops.
pub fn split(
  deck: Deck,
  cell: Id(CellTag),
  text: String,
  cursor: Int,
) -> Result(List(Op), SplitProblem) {
  case op.normalize_edit(deck, cell, text) {
    Error(problem) -> Error(Problem(problem))
    Ok(ops) ->
      case list.all(ops, is_edit_text) {
        False -> Error(HasBreak)
        True -> {
          let normalised = line.trim_blank_lines(text)
          let leading = case normalised {
            "" -> 0
            _ ->
              case string.split_once(text, normalised) {
                Ok(#(before, _)) -> string.length(before)
                Error(Nil) -> 0
              }
          }
          let at = graphemes_before(text, cursor) - leading
          let at = int.clamp(at, 0, string.length(normalised))
          Ok(list.append(ops, [op.Split(cell, at)]))
        }
      }
  }
}

fn is_edit_text(o: Op) -> Bool {
  case o {
    op.EditText(..) -> True
    _ -> False
  }
}

/// How many whole graphemes lie before a UTF-16 offset.
pub fn graphemes_before(text: String, utf16: Int) -> Int {
  string.to_graphemes(text)
  |> list.fold_until(#(0, 0), fn(acc, grapheme) {
    let #(count, units) = acc
    let units = units + utf16_length(grapheme)
    case units <= utf16 {
      True -> list.Continue(#(count + 1, units))
      False -> list.Stop(acc)
    }
  })
  |> fn(acc) { acc.0 }
}

fn utf16_length(text: String) -> Int {
  string.to_utf_codepoints(text)
  |> list.fold(0, fn(sum, point) {
    case string.utf_codepoint_to_int(point) > 0xFFFF {
      True -> sum + 2
      False -> sum + 1
    }
  })
}

/// A one-line message for an edit problem.
pub fn describe(problem: EditProblem) -> String {
  case problem {
    op.MarkerLine(line) ->
      "Line "
      <> int.to_string(line)
      <> " is a junkslides marker line, which cannot be part of a cell."
    op.EditUnknownCell -> "This cell no longer exists."
  }
}
