//// The editor without a server: a deck kept in the page, for the copy of
//// the editor that is published as a static site. It answers the client's
//// messages as the server's owner would, through the same
//// `junkslides/session`. Nothing is read from or written to disk, so edits
//// last as long as the page.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import junkslides/id.{type IdSupply}
import junkslides/protocol.{
  type ClientMsg, type CodeBlock, type Highlight, type ServerMsg, type Token,
  type View, Highlight,
}
import junkslides/session.{type Session}
import junkslides/shade

pub type Local {
  Local(
    session: Session,
    version: Int,
    view: View,
    /// From the deck's theme when the page was made.
    variants: List(String),
    marks: List(String),
    /// The simple shading's rules, from the deck's settings.
    rules: shade.Rules,
    /// Tokens that came with the page, by block; other blocks are shaded by
    /// the simple rules.
    given: Dict(CodeBlock, List(Token)),
    highlights: List(Highlight),
  )
}

/// A deck in the page, from the messages a server would greet a client
/// with (a state, and perhaps highlights and figures), the theme's mark
/// classes and the shading rules. Gives the messages to greet the editor
/// with. Fails without a state among them.
pub fn start(
  greeting: List(ServerMsg),
  marks: List(String),
  rules: shade.Rules,
) -> Result(#(Local, List(ServerMsg)), Nil) {
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
  let local =
    Local(
      session: session.new(deck, layout),
      version: 1,
      view:,
      variants:,
      marks:,
      rules:,
      given:,
      highlights: [],
    )
  let local = Local(..local, highlights: highlights(local))
  let rest =
    list.filter(greeting, fn(message) {
      case message {
        protocol.Figures(_) -> True
        _ -> False
      }
    })
  Ok(#(local, [state(local), protocol.Highlights(local.highlights), ..rest]))
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
