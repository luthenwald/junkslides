//// Messages between the client and the server, one WebSocket per client
//// (06-runtime.md, Protocol). JSON text frames; both sides use these codecs.

import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import zeno/codec.{type Value, Arr, Num, Obj, Str}
import zeno/deck.{type Deck}
import zeno/dialect.{type Problem}
import zeno/id.{type CellTag, type Id}
import zeno/layout.{type Layout, type LayoutOp}
import zeno/op.{type Op, type OpError}

/// Per-user view state of one deck (05-editor.md, View state).
pub type View {
  /// `cells_width` is the cells pane's share of the window in percent.
  /// `snap` is the canvas's snap step in design pixels; 0 is off.
  View(cells_width: Int, cells_hidden: Bool, slide_hidden: Bool, snap: Int)
}

pub const default_view =
  View(cells_width: 40, cells_hidden: False, slide_hidden: False, snap: 30)

pub type Diagnostic {
  Diagnostic(cell: Id(CellTag), problems: List(Problem))
}

pub type ClientMsg {
  Hello
  Apply(seq: Int, ops: List(Op))
  ApplyLayout(seq: Int, op: LayoutOp)
  Undo
  Redo
  SaveView(view: View)
}

pub type ServerMsg {
  State(
    version: Int,
    deck: Deck,
    layout: Layout,
    diagnostics: List(Diagnostic),
    variants: List(String),
    view: View,
  )
  Rejected(seq: Int, reason: String)
  Notice(text: String)
  ReloadTheme
}

/// Diagnostics for every cell with at least one problem.
pub fn diagnostics(deck: Deck) -> List(Diagnostic) {
  deck.cells(deck)
  |> list.filter_map(fn(cell) {
    case dialect.problems(cell.source) {
      [] -> Error(Nil)
      problems -> Ok(Diagnostic(cell.id, problems))
    }
  })
}

pub fn describe_error(error: OpError) -> String {
  case error {
    op.UnknownCell(_) -> "unknown cell"
    op.UnknownSlide(_) -> "unknown slide"
    op.PositionOutOfRange -> "position out of range"
    op.NoNextCell -> "no next cell in this slide"
    op.RemoveFirstBreak -> "the first slide has no break to remove"
    op.DeleteOnlySlide -> "the only slide cannot be deleted"
    op.AreaOffSlide -> "area too far off the slide"
    op.Unnormalised -> "text contains a structural line or blank edges"
  }
}

// Client messages ----------------------------------------------------------

pub fn encode_client(msg: ClientMsg) -> String {
  let tagged = fn(tag, fields) { Obj([#("type", Str(tag)), ..fields]) }
  case msg {
    Hello -> tagged("hello", [])
    Apply(seq:, ops:) ->
      tagged("apply", [
        #("seq", Num(seq)),
        #("ops", Arr(list.map(ops, codec.op_value))),
      ])
    ApplyLayout(seq:, op:) ->
      tagged("apply_layout", [
        #("seq", Num(seq)),
        #("op", codec.layout_op_value(op)),
      ])
    Undo -> tagged("undo", [])
    Redo -> tagged("redo", [])
    SaveView(view:) -> tagged("save_view", [#("view", view_value(view))])
  }
  |> codec.to_string
}

pub fn decode_client(text: String) -> Result(ClientMsg, json.DecodeError) {
  json.parse(text, client_decoder())
}

fn client_decoder() -> Decoder(ClientMsg) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "hello" -> decode.success(Hello)
    "apply" -> {
      use seq <- decode.field("seq", decode.int)
      use ops <- decode.field("ops", decode.list(codec.op_decoder()))
      decode.success(Apply(seq, ops))
    }
    "apply_layout" -> {
      use seq <- decode.field("seq", decode.int)
      use op <- decode.field("op", codec.layout_op_decoder())
      decode.success(ApplyLayout(seq, op))
    }
    "undo" -> decode.success(Undo)
    "redo" -> decode.success(Redo)
    "save_view" -> {
      use view <- decode.field("view", view_decoder())
      decode.success(SaveView(view))
    }
    _ -> decode.failure(Hello, "ClientMsg")
  }
}

// Server messages ----------------------------------------------------------

pub fn encode_server(msg: ServerMsg) -> String {
  let tagged = fn(tag, fields) { Obj([#("type", Str(tag)), ..fields]) }
  case msg {
    State(version:, deck:, layout:, diagnostics:, variants:, view:) ->
      tagged("state", [
        #("version", Num(version)),
        #("deck", codec.deck_value(deck)),
        #("layout", codec.layout_value(layout)),
        #("diagnostics", Arr(list.map(diagnostics, diagnostic_value))),
        #("variants", Arr(list.map(variants, Str))),
        #("view", view_value(view)),
      ])
    Rejected(seq:, reason:) ->
      tagged("rejected", [#("seq", Num(seq)), #("reason", Str(reason))])
    Notice(text:) -> tagged("notice", [#("text", Str(text))])
    ReloadTheme -> tagged("reload_theme", [])
  }
  |> codec.to_string
}

pub fn decode_server(text: String) -> Result(ServerMsg, json.DecodeError) {
  json.parse(text, server_decoder())
}

fn server_decoder() -> Decoder(ServerMsg) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "state" -> {
      use version <- decode.field("version", decode.int)
      use deck <- decode.field("deck", codec.deck_decoder())
      use layout <- decode.field("layout", codec.layout_decoder())
      use diagnostics <- decode.field(
        "diagnostics",
        decode.list(diagnostic_decoder()),
      )
      use variants <- decode.field("variants", decode.list(decode.string))
      use view <- decode.field("view", view_decoder())
      decode.success(State(version, deck, layout, diagnostics, variants, view))
    }
    "rejected" -> {
      use seq <- decode.field("seq", decode.int)
      use reason <- decode.field("reason", decode.string)
      decode.success(Rejected(seq, reason))
    }
    "notice" -> {
      use text <- decode.field("text", decode.string)
      decode.success(Notice(text))
    }
    "reload_theme" -> decode.success(ReloadTheme)
    _ -> decode.failure(ReloadTheme, "ServerMsg")
  }
}

// Parts --------------------------------------------------------------------

pub fn view_value(view: View) -> Value {
  Obj([
    #("cells_width", Num(view.cells_width)),
    #("cells_hidden", codec.Bool(view.cells_hidden)),
    #("slide_hidden", codec.Bool(view.slide_hidden)),
    #("snap", Num(view.snap)),
  ])
}

pub fn view_decoder() -> Decoder(View) {
  use cells_width <- decode.field("cells_width", decode.int)
  use cells_hidden <- decode.field("cells_hidden", decode.bool)
  use slide_hidden <- decode.field("slide_hidden", decode.bool)
  // View files written before the snap setting existed have no `snap`.
  use snap <- decode.optional_field("snap", default_view.snap, decode.int)
  decode.success(View(cells_width, cells_hidden, slide_hidden, snap))
}

fn diagnostic_value(diagnostic: Diagnostic) -> Value {
  Obj([
    #("cell", codec.id_value(diagnostic.cell)),
    #("problems", Arr(list.map(diagnostic.problems, problem_value))),
  ])
}

fn diagnostic_decoder() -> Decoder(Diagnostic) {
  use cell <- decode.field("cell", id.decoder())
  use problems <- decode.field("problems", decode.list(problem_decoder()))
  decode.success(Diagnostic(cell, problems))
}

const problems = [
  #("thematic_break", dialect.ThematicBreakUsed),
  #("raw_block", dialect.RawBlockUsed),
  #("div", dialect.DivUsed),
  #("span", dialect.SpanUsed),
  #("attributes", dialect.AttributesUsed),
  #("reference_link", dialect.ReferenceLinkUsed),
  #("reference_definition", dialect.ReferenceDefinitionUsed),
  #("footnote", dialect.FootnoteUsed),
  #("math", dialect.MathUsed),
  #("extra", dialect.ExtraUsed),
  #("bullet_spelling", dialect.BulletSpelling),
  #("ordinal_spelling", dialect.OrdinalSpelling),
]

fn problem_value(problem: Problem) -> Value {
  let assert Ok(#(name, _)) = list.find(problems, fn(p) { p.1 == problem })
  Str(name)
}

fn problem_decoder() -> Decoder(Problem) {
  use name <- decode.then(decode.string)
  case list.key_find(problems, name) {
    Ok(problem) -> decode.success(problem)
    Error(Nil) -> decode.failure(dialect.ThematicBreakUsed, "Problem")
  }
}
