//// The editor without a server: a deck kept in the page, for the copy of
//// the editor that is published as a static site. It answers the client's
//// messages as the server's owner would, through the same
//// `junkslides/session`.
////
//// The deck is the one the page was made with, or a copy of a folder the
//// user opened. Nothing is written to disk. What the browser's storage
//// should hold to bring the deck back after a reload is `kept`, and
//// `resume` reads it again. All of it is pure; `junkslides_client/browser`
//// does the reading and storing.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import junkslides/contract
import junkslides/deck.{type Deck}
import junkslides/dialect
import junkslides/drawing
import junkslides/file
import junkslides/id.{type IdSupply}
import junkslides/layout.{type Layout}
import junkslides/protocol.{
  type ClientMsg, type CodeBlock, type Highlight, type ServerMsg, type Token,
  type View, Highlight,
}
import junkslides/session.{type Session}
import junkslides/settings
import junkslides/shade

pub type Local {
  Local(
    session: Session,
    version: Int,
    view: View,
    origin: Origin,
    /// From the deck's theme.
    variants: List(String),
    marks: List(String),
    /// The simple shading's rules, from the deck's settings.
    rules: shade.Rules,
    /// Tokens that came with the page, by block; other blocks are shaded by
    /// the simple rules.
    given: Dict(CodeBlock, List(Token)),
    highlights: List(Highlight),
    /// The text of the deck's drawings and charts, by path.
    figures: List(#(String, String)),
    /// Said once, when the editor is greeted.
    notices: List(String),
  )
}

pub type Origin {
  /// The deck the page was made with. `base` is its text as it came, to
  /// tell an edited deck from an untouched one, and kept edits that belong
  /// to an older page from this one's.
  Site(base: String)
  /// A copy of a folder the user opened: its name, and the text of its
  /// files other than deck.md and layout.json, by path.
  Folder(name: String, files: List(#(String, String)))
}

/// The stylesheets a deck brings as text, settings first: an opened folder
/// has them, and the page's own deck has files beside the page.
pub fn sheets(local: Local) -> Option(#(String, String)) {
  case local.origin {
    Site(_) -> None
    Folder(files:, ..) -> {
      let css =
        list.key_find(files, settings_file)
        |> result.try(fn(text) {
          settings.parse(text) |> result.replace_error(Nil)
        })
        |> result.map(settings.to_css(_, ""))
        |> result.unwrap("")
      Some(#(css, list.key_find(files, theme_file) |> result.unwrap("")))
    }
  }
}

const deck_file = "deck.md"

const layout_file = "layout.json"

const settings_file = "junkslides.toml"

const theme_file = "theme.css"

/// The files to read from a folder before anything else.
pub const first_files = [deck_file, layout_file, settings_file, theme_file]

/// A deck in the page, from the messages a server would greet a client
/// with (a state, and perhaps highlights and figures), the theme's mark
/// classes and the shading rules. Fails without a state among them.
pub fn start(
  greeting: List(ServerMsg),
  marks: List(String),
  rules: shade.Rules,
) -> Result(Local, Nil) {
  use #(deck, layout, variants, view) <- result.try(
    list.find_map(greeting, fn(message) {
      case message {
        protocol.State(deck:, layout:, variants:, view:, ..) ->
          Ok(#(deck, layout, variants, view))
        _ -> Error(Nil)
      }
    }),
  )
  let given =
    list.flat_map(greeting, fn(message) {
      case message {
        protocol.Highlights(blocks) ->
          list.map(blocks, fn(h) { #(h.block, h.tokens) })
        _ -> []
      }
    })
    |> dict.from_list
  let figures =
    list.flat_map(greeting, fn(message) {
      case message {
        protocol.Figures(files) -> files
        _ -> []
      }
    })
  Ok(
    shaded(
      Local(
        session: session.new(deck, layout),
        version: 1,
        view:,
        origin: Site(text_of(deck, layout)),
        variants:,
        marks:,
        rules:,
        given:,
        highlights: [],
        figures:,
        notices: [],
      ),
    ),
  )
}

/// What greets the editor: the state, the tokens, the figures, and what
/// there is to say about the deck.
pub fn greeting(local: Local) -> List(ServerMsg) {
  [
    state(local),
    protocol.Highlights(local.highlights),
    protocol.Figures(local.figures),
    ..list.map(local.notices, protocol.Notice)
  ]
}

/// The figures a deck's text names, to read from its folder after deck.md.
/// A deck that does not parse names none.
pub fn figure_files(deck_text: String) -> List(String) {
  case file.parse(deck_text, id.supply(0, <<>>)) {
    Ok(#(deck, _)) -> protocol.figures(deck)
    Error(_) -> []
  }
}

/// A copy of a folder as a deck in the page, from the text of its files by
/// path: deck.md, and if they are there layout.json, junkslides.toml,
/// theme.css and the figures the deck names. A file that does not read is
/// named in the error, as `junkslides serve` would name it. Pictures and
/// font files are not copied, so the page shows the deck without them.
pub fn open(
  name: String,
  files: List(#(String, String)),
  supply: IdSupply,
  now: Timestamp,
) -> Result(Local, String) {
  let find = fn(path) { list.key_find(files, path) |> option.from_result }
  use deck_text <- result.try(
    list.key_find(files, deck_file)
    |> result.replace_error("There is no deck.md in " <> name <> "."),
  )
  use #(deck, _) <- result.try(
    file.parse(deck_text, supply) |> result.map_error(file.describe),
  )
  use layout <- result.try(case find(layout_file) {
    None -> Ok(layout.empty())
    Some(text) ->
      file.parse_layout(text)
      |> result.replace_error("layout.json in " <> name <> " is not valid.")
  })
  use read <- result.try(case find(settings_file) {
    None -> Ok(None)
    Some(text) ->
      settings.parse(text)
      |> result.map(Some)
      |> result.map_error(fn(why) { settings_file <> ": " <> why })
  })
  let css = find(theme_file) |> option.unwrap("")
  let drawn =
    list.map(protocol.figures(deck), fn(url) {
      let text =
        list.key_find(files, url)
        |> result.replace_error("missing")
        |> result.try(fn(text) {
          case dialect.figure_kind(url) {
            Some(dialect.Drawing) -> drawing.safe(text)
            _ -> Ok(text)
          }
        })
      #(url, text)
    })
  let figures =
    list.filter_map(drawn, fn(pair) {
      result.map(pair.1, fn(text) { #(pair.0, text) })
    })
  let notices =
    list.filter_map(drawn, fn(pair) {
      case pair.1 {
        Ok(_) -> Error(Nil)
        Error(why) ->
          Ok("The figure " <> pair.0 <> " cannot be drawn: " <> why <> ".")
      }
    })
  Ok(
    shaded(Local(
      session: session.new(deck, layout.consistency(layout, deck, now)),
      version: 1,
      view: protocol.default_view,
      origin: Folder(
        name:,
        files: list.filter(files, fn(file) {
          file.0 != deck_file && file.0 != layout_file
        }),
      ),
      variants: contract.variants(css),
      marks: contract.marks(css),
      rules: settings.shading(read),
      given: dict.new(),
      highlights: [],
      figures:,
      notices:,
    )),
  )
}

// Kept across reloads -----------------------------------------------------------

/// What the browser should keep to bring this deck back after a reload, as
/// text. The page's own deck, untouched, needs nothing kept.
pub fn kept(local: Local) -> Option(String) {
  let deck = file.print(local.session.deck)
  let layout = file.print_layout(local.session.layout)
  let origin = case local.origin {
    Site(base:) if base == deck <> layout -> None
    Site(base:) -> Some([#("base", json.string(base))])
    Folder(name:, files:) ->
      Some([
        #("name", json.string(name)),
        #(
          "files",
          json.array(files, fn(file) {
            json.preprocessed_array([json.string(file.0), json.string(file.1)])
          }),
        ),
      ])
  }
  use origin <- option.map(origin)
  [#("deck", json.string(deck)), #("layout", json.string(layout)), ..origin]
  |> json.object
  |> json.to_string
}

/// The deck `kept` wrote, in place of `home`, the page's own. Edits to the
/// page's own deck come back only onto the deck they were made on, so a
/// page made again with another deck starts fresh. Undo starts anew.
pub fn resume(
  home: Local,
  text: String,
  supply: IdSupply,
  now: Timestamp,
) -> Result(Local, Nil) {
  let pair = {
    use path <- decode.field(0, decode.string)
    use text <- decode.field(1, decode.string)
    decode.success(#(path, text))
  }
  let decoder = {
    use deck <- decode.field("deck", decode.string)
    use layout <- decode.field("layout", decode.string)
    use base <- decode.optional_field("base", "", decode.string)
    use name <- decode.optional_field("name", "", decode.string)
    use files <- decode.optional_field("files", [], decode.list(pair))
    decode.success(#(deck, layout, base, name, files))
  }
  use #(deck_text, layout_text, base, name, files) <- result.try(
    json.parse(text, decoder) |> result.replace_error(Nil),
  )
  case home.origin, name {
    Site(base: ours), "" if ours == base -> {
      use #(deck, _) <- result.try(
        file.parse(deck_text, supply) |> result.replace_error(Nil),
      )
      use layout <- result.try(
        file.parse_layout(layout_text) |> result.replace_error(Nil),
      )
      // Past the first version, as an edited deck is.
      Ok(shaded(Local(..home, session: session.new(deck, layout), version: 2)))
    }
    _, "" -> Error(Nil)
    _, name ->
      open(
        name,
        [#(deck_file, deck_text), #(layout_file, layout_text), ..files],
        supply,
        now,
      )
      |> result.replace_error(Nil)
  }
}

fn text_of(deck: Deck, layout: Layout) -> String {
  file.print(deck) <> file.print_layout(layout)
}

fn shaded(local: Local) -> Local {
  Local(..local, highlights: highlights(local))
}

/// What the owner would answer. `Export` is the editor's to handle, since
/// only it can hand over files; here it answers nothing.
pub fn handle(
  local: Local,
  message: ClientMsg,
  supply: IdSupply,
  now: Timestamp,
) -> #(Local, List(ServerMsg)) {
  let refuse = fn(seq, error) {
    #(local, [protocol.Rejected(seq, protocol.describe_error(error))])
  }
  let step = fn(stepped) {
    case stepped {
      None -> #(local, [state(local)])
      Some(session) -> changed(local, session)
    }
  }
  case message {
    protocol.Hello -> #(local, [state(local)])
    protocol.Apply(seq:, ops:) ->
      case session.apply(local.session, ops, supply, now) {
        Ok(session) -> changed(local, session)
        Error(error) -> refuse(seq, error)
      }
    protocol.ApplyLayout(seq:, op:) ->
      case session.apply_layout(local.session, op) {
        Ok(session) -> changed(local, session)
        Error(error) -> refuse(seq, error)
      }
    protocol.Undo -> step(session.undo(local.session))
    protocol.Redo -> step(session.redo(local.session))
    protocol.SaveView(view:) -> #(Local(..local, view:), [])
    protocol.Export -> #(local, [])
    protocol.ExportPdf -> #(local, [
      protocol.Notice(
        "A PDF needs junkslides on your own computer. E gives you the deck's files from here.",
      ),
    ])
  }
}

fn changed(local: Local, session: Session) -> #(Local, List(ServerMsg)) {
  let local = Local(..local, session:, version: local.version + 1)
  let shaded = highlights(local)
  case shaded == local.highlights {
    True -> #(local, [state(local)])
    False -> #(Local(..local, highlights: shaded), [
      state(local),
      protocol.Highlights(shaded),
    ])
  }
}

fn state(local: Local) -> ServerMsg {
  protocol.State(
    version: local.version,
    deck: local.session.deck,
    layout: local.session.layout,
    diagnostics: protocol.diagnostics(local.session.deck, local.marks),
    variants: local.variants,
    view: local.view,
  )
}

fn highlights(local: Local) -> List(Highlight) {
  protocol.code_blocks(local.session.deck)
  |> list.filter_map(fn(block) {
    let tokens = case dict.get(local.given, block) {
      Ok(tokens) -> tokens
      Error(Nil) -> shade.tokens(block.code, local.rules)
    }
    case tokens {
      [] -> Error(Nil)
      tokens -> Ok(Highlight(block, tokens))
    }
  })
}
