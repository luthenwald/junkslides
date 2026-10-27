//// Structural lines of deck.md (02-file-format.md). A line is structural
//// only when it matches exactly, with no surrounding whitespace.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import zeno/id.{type CellTag, type Id, type SlideTag}

pub type Line {
  /// `<!-- deck vN -->`, with the version as written.
  Header(version: Int)
  /// `---`
  Break
  /// `<!-- slide UUID -->`
  SlideMarker(id: Id(SlideTag))
  /// `<!-- cell UUID -->`, `<!-- notes UUID -->`, `<!-- cell -->` or
  /// `<!-- notes -->`.
  CellMarker(notes: Bool, id: Option(Id(CellTag)))
  /// Anything else: part of a cell body.
  Body
}

pub fn classify(line: String) -> Line {
  case line {
    "---" -> Break
    "<!-- cell -->" -> CellMarker(notes: False, id: None)
    "<!-- notes -->" -> CellMarker(notes: True, id: None)
    "<!-- deck v" <> rest -> header(rest)
    "<!-- slide " <> rest ->
      case uuid(rest) {
        Ok(id) -> SlideMarker(id)
        Error(Nil) -> Body
      }
    "<!-- cell " <> rest ->
      case uuid(rest) {
        Ok(id) -> CellMarker(notes: False, id: Some(id))
        Error(Nil) -> Body
      }
    "<!-- notes " <> rest ->
      case uuid(rest) {
        Ok(id) -> CellMarker(notes: True, id: Some(id))
        Error(Nil) -> Body
      }
    _ -> Body
  }
}

pub fn is_structural(line: String) -> Bool {
  classify(line) != Body
}

fn header(rest: String) -> Line {
  case string.split_once(rest, " -->") {
    Ok(#(digits, "")) ->
      case int.parse(digits) {
        Ok(version) if version >= 0 ->
          case int.to_string(version) == digits {
            True -> Header(version)
            False -> Body
          }
        _ -> Body
      }
    _ -> Body
  }
}

fn uuid(rest: String) -> Result(Id(tag), Nil) {
  case string.split_once(rest, " -->") {
    Ok(#(text, "")) -> id.parse(text)
    _ -> Error(Nil)
  }
}

/// The text of a marker line.
pub fn header_line() -> String {
  "<!-- deck v1 -->"
}

pub fn slide_line(slide: Id(SlideTag)) -> String {
  "<!-- slide " <> id.to_string(slide) <> " -->"
}

pub fn cell_line(notes: Bool, cell: Id(CellTag)) -> String {
  case notes {
    True -> "<!-- notes " <> id.to_string(cell) <> " -->"
    False -> "<!-- cell " <> id.to_string(cell) <> " -->"
  }
}

/// Splits text into lines on LF.
pub fn lines(text: String) -> List(String) {
  string.split(text, "\n")
}

pub fn is_blank(line: String) -> Bool {
  string.trim(line) == ""
}

/// Removes leading and trailing blank lines (lines of only whitespace).
pub fn trim_blank_lines(text: String) -> String {
  lines(text)
  |> drop_blank
  |> reverse_drop_blank
  |> string.join("\n")
}

fn drop_blank(lines: List(String)) -> List(String) {
  case lines {
    [first, ..rest] ->
      case is_blank(first) {
        True -> drop_blank(rest)
        False -> lines
      }
    [] -> []
  }
}

fn reverse_drop_blank(lines: List(String)) -> List(String) {
  lines |> list.reverse |> drop_blank |> list.reverse
}
