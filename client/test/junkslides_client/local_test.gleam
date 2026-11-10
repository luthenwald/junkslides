import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/timestamp
import junkslides/deck.{Cell, Content, Deck, Slide}
import junkslides/id
import junkslides/layout
import junkslides/op
import junkslides/protocol
import junkslides/shade
import junkslides_client/app
import junkslides_client/keymap
import junkslides_client/local

const now = timestamp.unix_epoch

fn supply() {
  id.supply(1_700_000_000_000, <<1, 2, 3, 4, 5, 6, 7, 8>>)
}

fn started() {
  let assert Ok(slide) = id.parse("019a7000-0000-7000-8000-000000000001")
  let assert Ok(cell) = id.parse("019a7000-0000-7000-8000-000000000002")
  let deck = Deck([Slide(slide, [Cell(cell, Content, "# Hello")])])
  let given = protocol.CodeBlock("gleam", "let x = 1\n")
  let greeting = [
    protocol.State(
      1,
      deck,
      layout.empty(),
      [],
      ["large"],
      protocol.default_view,
    ),
    protocol.Highlights([
      protocol.Highlight(given, [protocol.Token(Some("keyword"), "let x = 1")]),
    ]),
    protocol.Figures([#("assets/a.svg", "<svg/>")]),
  ]
  let assert Ok(#(page, greeted)) =
    local.start(greeting, ["now"], shade.default_rules)
  #(page, greeted, cell, slide)
}

/// A deck in the page greets the editor as a server would and answers its
/// messages: states with rising versions, refusals, undo, and highlights
/// from the page's own tokens or the simple rules.
pub fn a_deck_in_the_page_answers_as_the_server_does_test() {
  let #(page, greeted, cell, slide) = started()
  let assert [protocol.State(version: 1, variants: ["large"], ..), _, figures] =
    greeted
  assert figures == protocol.Figures([#("assets/a.svg", "<svg/>")])
  // An edit: a new state, and tokens for the new code block. The block the
  // page came with keeps its tokens; another is shaded by the rules.
  let edit = fn(text) { protocol.Apply(1, [op.EditText(cell, text)]) }
  let #(page, answers) =
    local.handle(page, edit("```gleam\nlet x = 1\n```"), supply(), now)
  let assert [protocol.State(version: 2, ..), protocol.Highlights([given])] =
    answers
  assert given.tokens == [protocol.Token(Some("keyword"), "let x = 1")]
  let #(page, answers) =
    local.handle(page, edit("```gleam\nlet y = 2\n```"), supply(), now)
  let assert [_, protocol.Highlights([shaded])] = answers
  assert list.length(shaded.tokens) > 1
  // An unknown mark is a problem, from the marks the page was made with.
  let #(page, answers) = local.handle(page, edit("[x]{.gone}"), supply(), now)
  let assert [protocol.State(diagnostics: [_], ..), ..] = answers
  // A layout op, then undo twice, then a refusal.
  let off = layout.SetSlide(slide, layout.SlideRecord(False, True))
  let #(page, _) =
    local.handle(page, protocol.ApplyLayout(2, off), supply(), now)
  assert layout.slide_record(page.session.layout, slide).number == False
  let #(page, _) = local.handle(page, protocol.Undo, supply(), now)
  assert page.session.layout == layout.empty()
  let #(_, answers) =
    local.handle(
      page,
      protocol.Apply(3, [op.Delete(slide_cell())]),
      supply(),
      now,
    )
  let assert [protocol.Rejected(seq: 3, ..)] = answers
}

fn slide_cell() {
  let assert Ok(cell) = id.parse("019a7000-0000-7000-8000-00000000ffff")
  cell
}

/// With a deck in the page, `E` offers deck.md and layout.json as they are
/// now, and the next state takes the offer away.
pub fn export_offers_the_files_test() {
  let #(page, greeting, cell, _) = started()
  let #(model, _) = app.init(app.Standalone(page, greeting))
  let #(model, _) = app.update(model, app.Answered(greeting))
  let assert app.InPage(page) = model.connection
  let #(page, answers) =
    local.handle(
      page,
      protocol.Apply(1, [op.EditText(cell, "# Changed")]),
      supply(),
      now,
    )
  let model = app.Model(..model, connection: app.InPage(page))
  let #(model, _) = app.update(model, app.Answered(answers))
  let #(model, _) = app.update(model, app.CommandKey(keymap_export()))
  let assert [#("deck.md", text), #("layout.json", laid)] = model.downloads
  assert string.contains(text, "# Changed")
  assert string.contains(laid, "\"version\": 2")
  assert model.notice != None
  let #(model, _) = app.update(model, app.Answered(answers))
  assert model.downloads == []
}

fn keymap_export() {
  keymap.Export
}
