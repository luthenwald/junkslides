//// Messages between the client and the server, one WebSocket per client
//// (06-runtime.md, Protocol). JSON text frames; both sides use these codecs.

import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import junkslides/codec.{type Value, Arr, Num, Obj, Str}
import junkslides/deck.{type Deck}
import junkslides/dialect.{type Problem}
import junkslides/id.{type CellTag, type Id}
import junkslides/layout.{type Layout, type LayoutOp}
import junkslides/op.{type Op, type OpError}

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

/// A code block on a slide: the language written after its fence, and its
/// text as jot gives it.
pub type CodeBlock {
  CodeBlock(language: String, code: String)
}

/// A piece of a code block's text; `kind` is a highlight name such as
/// `keyword` or `punctuation.bracket`. Joined, the pieces give the text back.
pub type Token {
  Token(kind: Option(String), text: String)
}

pub type Highlight {
  Highlight(block: CodeBlock, tokens: List(Token))
}

pub type ClientMsg {
  Hello
  Apply(seq: Int, ops: List(Op))
  ApplyLayout(seq: Int, op: LayoutOp)
  Undo
  Redo
  SaveView(view: View)
  /// Write the current state as a static folder (04-layout.md, Export).
  Export
  /// The same folder, and a PDF of its page in it.
  ExportPdf
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
  /// The files that are not being written now, each with the reason: a
  /// deck.md or layout.json with an open problem, or a write that failed.
  /// Sent whenever the list changes, the empty list too, and to a new
  /// client when there are any. Unlike a notice it describes a state, which
  /// the editor shows for as long as it lasts.
  Unsaved(files: List(#(String, String)))
  ReloadTheme
  /// The tokens of the deck's code blocks, as far as the server has them.
  /// A block without an entry is drawn plain.
  Highlights(blocks: List(Highlight))
  /// The text of the drawings and charts the deck's cells name (D29), by
  /// their path as written, whole. A figure without an entry could not be
  /// read or used: a drawing is then an `img`, a chart a placeholder.
  Figures(files: List(#(String, String)))
}

/// The drawings and charts the deck's content cells name, each once.
pub fn figures(deck: Deck) -> List(String) {
  deck.cells(deck)
  |> list.filter(fn(cell) { cell.kind == deck.Content })
  |> list.flat_map(fn(cell) { dialect.figures(cell.source) })
  |> list.unique
}

/// The code blocks with a language in the deck's content cells, each once.
pub fn code_blocks(deck: Deck) -> List(CodeBlock) {
  deck.cells(deck)
  |> list.filter(fn(cell) { cell.kind == deck.Content })
  |> list.flat_map(fn(cell) { dialect.code_blocks(cell.source) })
  |> list.map(fn(pair) { CodeBlock(pair.0, pair.1) })
  |> list.unique
}

/// Diagnostics for every cell with at least one problem. `marks` are the
/// mark classes the theme lists (D28).
pub fn diagnostics(deck: Deck, marks: List(String)) -> List(Diagnostic) {
  deck.cells(deck)
  |> list.filter_map(fn(cell) {
    let problems =
      list.append(
        dialect.problems(cell.source),
        dialect.unknown_marks(cell.source, marks),
      )
    case problems {
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
    Export -> tagged("export", [])
    ExportPdf -> tagged("export-pdf", [])
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
    "export" -> decode.success(Export)
    "export-pdf" -> decode.success(ExportPdf)
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
    Unsaved(files:) ->
      tagged("unsaved", [
        #(
          "files",
          Arr(
            list.map(files, fn(file) {
              Obj([#("name", Str(file.0)), #("reason", Str(file.1))])
            }),
          ),
        ),
      ])
    ReloadTheme -> tagged("reload_theme", [])
    Highlights(blocks:) ->
      tagged("highlights", [
        #("blocks", Arr(list.map(blocks, highlight_value))),
      ])
    Figures(files:) ->
      tagged("figures", [
        #(
          "files",
          Arr(
            list.map(files, fn(file) {
              Obj([#("path", Str(file.0)), #("text", Str(file.1))])
            }),
          ),
        ),
      ])
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
    "unsaved" -> {
      let file = {
        use name <- decode.field("name", decode.string)
        use reason <- decode.field("reason", decode.string)
        decode.success(#(name, reason))
      }
      use files <- decode.field("files", decode.list(file))
      decode.success(Unsaved(files))
    }
    "reload_theme" -> decode.success(ReloadTheme)
    "highlights" -> {
      use blocks <- decode.field("blocks", decode.list(highlight_decoder()))
      decode.success(Highlights(blocks))
    }
    "figures" -> {
      let file = {
        use path <- decode.field("path", decode.string)
        use text <- decode.field("text", decode.string)
        decode.success(#(path, text))
      }
      use files <- decode.field("files", decode.list(file))
      decode.success(Figures(files))
    }
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

fn highlight_value(highlight: Highlight) -> Value {
  Obj([
    #("language", Str(highlight.block.language)),
    #("code", Str(highlight.block.code)),
    #(
      "tokens",
      Arr(
        list.map(highlight.tokens, fn(token) {
          Obj([
            #("kind", case token.kind {
              Some(kind) -> Str(kind)
              None -> codec.Null
            }),
            #("text", Str(token.text)),
          ])
        }),
      ),
    ),
  ])
}

fn highlight_decoder() -> Decoder(Highlight) {
  use language <- decode.field("language", decode.string)
  use code <- decode.field("code", decode.string)
  use tokens <- decode.field(
    "tokens",
    decode.list({
      use kind <- decode.field("kind", decode.optional(decode.string))
      use text <- decode.field("text", decode.string)
      decode.success(Token(kind, text))
    }),
  )
  decode.success(Highlight(CodeBlock(language, code), tokens))
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

/// A problem's name on the wire. The compiler asks for a name when a
/// problem is added to the dialect, so the server can always say it.
fn problem_name(problem: Problem) -> String {
  case problem {
    dialect.ThematicBreakUsed -> "thematic_break"
    dialect.RawBlockUsed -> "raw_block"
    dialect.DivUsed -> "div"
    dialect.SpanUsed -> "span"
    dialect.AttributesUsed -> "attributes"
    dialect.ReferenceLinkUsed -> "reference_link"
    dialect.ReferenceDefinitionUsed -> "reference_definition"
    dialect.FootnoteUsed -> "footnote"
    dialect.MathUsed -> "math"
    dialect.ExtraUsed -> "extra"
    dialect.BulletSpelling -> "bullet_spelling"
    dialect.OrdinalSpelling -> "ordinal_spelling"
    dialect.TableShape -> "table_shape"
    dialect.UnknownMark -> "unknown_mark"
    dialect.CodeAttribute -> "code_attribute"
  }
}

/// Every problem, for reading a name back. One missing here is not read by
/// the editor, which says so; `server_messages_round_trip_test` sends them
/// all.
pub const problems = [
  dialect.ThematicBreakUsed,
  dialect.RawBlockUsed,
  dialect.DivUsed,
  dialect.SpanUsed,
  dialect.AttributesUsed,
  dialect.ReferenceLinkUsed,
  dialect.ReferenceDefinitionUsed,
  dialect.FootnoteUsed,
  dialect.MathUsed,
  dialect.ExtraUsed,
  dialect.BulletSpelling,
  dialect.OrdinalSpelling,
  dialect.TableShape,
  dialect.UnknownMark,
  dialect.CodeAttribute,
]

fn problem_value(problem: Problem) -> Value {
  Str(problem_name(problem))
}

fn problem_decoder() -> Decoder(Problem) {
  use name <- decode.then(decode.string)
  case list.find(problems, fn(problem) { problem_name(problem) == name }) {
    Ok(problem) -> decode.success(problem)
    Error(Nil) -> decode.failure(dialect.ThematicBreakUsed, "Problem")
  }
}
