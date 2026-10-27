//// Splits unmarked text into top-level blocks (reading rule 5) without a
//// full parser: blank lines separate blocks, except inside a code fence or
//// between items and continuations of the same list.

import gleam/list
import gleam/string

type Kind {
  Plain
  BulletKind(marker: String)
  OrderedKind
}

type State {
  State(
    done: List(List(String)),
    current: List(String),
    kind: Kind,
    fence: Int,
    blanks: List(String),
  )
}

pub fn split(text: String) -> List(String) {
  let lines = string.split(text, "\n")
  let final = list.fold(lines, State([], [], Plain, 0, []), step)
  [final.current, ..final.done]
  |> list.filter(fn(block) { block != [] })
  |> list.map(fn(block) { block |> list.reverse |> string.join("\n") })
  |> list.reverse
}

fn step(state: State, line: String) -> State {
  let trimmed = string.trim_start(line)
  let ticks = fence_ticks(trimmed)
  case state.fence > 0 {
    True -> {
      let fence = case ticks >= state.fence && only_ticks(trimmed) {
        True -> 0
        False -> state.fence
      }
      State(..state, current: [line, ..state.current], fence: fence)
    }
    False ->
      case string.trim(line) == "" {
        True ->
          case state.current {
            [] -> state
            _ -> State(..state, blanks: [line, ..state.blanks])
          }
        False ->
          case state.blanks == [] || continues_list(state.kind, line, trimmed) {
            True ->
              State(
                ..state,
                current: [line, ..list.append(state.blanks, state.current)],
                fence: ticks,
                blanks: [],
                kind: case state.current {
                  [] -> kind_of(trimmed)
                  _ -> state.kind
                },
              )
            False ->
              State(
                done: [state.current, ..state.done],
                current: [line],
                kind: kind_of(trimmed),
                fence: ticks,
                blanks: [],
              )
          }
      }
  }
}

fn continues_list(kind: Kind, line: String, trimmed: String) -> Bool {
  let indented = string.starts_with(line, " ")
  case kind {
    Plain -> False
    BulletKind(marker) -> indented || string.starts_with(trimmed, marker)
    OrderedKind -> indented || kind_of(trimmed) == OrderedKind
  }
}

fn kind_of(trimmed: String) -> Kind {
  case trimmed {
    "- " <> _ | "-" -> BulletKind("- ")
    "* " <> _ | "*" -> BulletKind("* ")
    "+ " <> _ | "+" -> BulletKind("+ ")
    _ ->
      case string.split_once(trimmed, ". ") {
        Ok(#(digits, _)) ->
          case digits != "" && list.all(string.to_graphemes(digits), is_digit) {
            True -> OrderedKind
            False -> Plain
          }
        Error(_) -> Plain
      }
  }
}

fn is_digit(g: String) -> Bool {
  string.contains("0123456789", g)
}

fn fence_ticks(trimmed: String) -> Int {
  let n =
    trimmed
    |> string.to_graphemes
    |> list.take_while(fn(g) { g == "`" })
    |> list.length
  case n >= 3 {
    True -> n
    False -> 0
  }
}

fn only_ticks(trimmed: String) -> Bool {
  string.to_graphemes(string.trim(trimmed)) |> list.all(fn(g) { g == "`" })
}
