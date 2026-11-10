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
  let assert Ok(page) = local.start(greeting, ["now"], shade.default_rules)
  #(page, local.greeting(page), cell, slide)
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
  let #(model, _) = app.init(app.Standalone(page, page))
  let #(model, _) = app.update(model, app.Answered(greeting))
  let assert app.InPage(local: page, home:) = model.connection
  let #(page, answers) =
    local.handle(
      page,
      protocol.Apply(1, [op.EditText(cell, "# Changed")]),
      supply(),
      now,
    )
  let model = app.Model(..model, connection: app.InPage(page, home))
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

/// What the browser keeps brings an edited deck back: nothing for the
/// page's own deck untouched, its text once edited, and only onto the deck
/// the edits were made on.
pub fn an_edited_deck_is_kept_and_resumed_test() {
  let #(home, _, cell, _) = started()
  assert local.kept(home) == None
  let #(page, _) =
    local.handle(
      home,
      protocol.Apply(1, [op.EditText(cell, "# Changed")]),
      supply(),
      now,
    )
  let assert Some(text) = local.kept(page)
  let assert Ok(back) = local.resume(home, text, supply(), now)
  assert back.session.deck == page.session.deck
  assert back.session.layout == page.session.layout
  assert back.origin == home.origin
  // The figures and the theme's names are the page's own.
  assert back.figures == home.figures
  assert back.variants == ["large"]
  // Edits made on another deck do not come back onto this one.
  let assert local.Site(base:) = home.origin
  let other = local.Local(..home, origin: local.Site(base <> "x"))
  assert local.resume(other, text, supply(), now) == Error(Nil)
  assert local.resume(home, "not json", supply(), now) == Error(Nil)
}

const folder = [
  #("deck.md", "# Mine\n\n![](fan.svg)\n\n![](bad.svg)\n\n[x]{.now}\n"),
  #("junkslides.toml", "[palette]\naccent = \"#123456\"\n"),
  #("theme.css", ":root { --js-variants: \"loud\"; --js-marks: \"now\"; }\n"),
  #("fan.svg", "<svg><path d=\"M0,0\"/></svg>"),
  #("bad.svg", "<svg><script>1</script></svg>"),
]

/// A folder's files become a deck in the page: its settings and theme as
/// sheets, the theme's names, its drawings checked, and a word about each
/// figure that cannot be drawn. It is kept whole and resumed.
pub fn a_folder_opens_as_a_copy_test() {
  let assert Ok(page) = local.open("talk", folder, supply(), now)
  let assert [slide] = page.session.deck.slides
  let assert [_, _, _, _] = slide.cells
  assert page.variants == ["loud"]
  assert page.marks == ["now"]
  assert page.figures == [#("fan.svg", "<svg><path d=\"M0,0\"/></svg>")]
  let assert Some(#(settings, theme)) = local.sheets(page)
  assert string.contains(settings, "#123456")
  assert string.contains(theme, "--js-variants")
  let assert [
    protocol.State(diagnostics: [], ..),
    protocol.Highlights(_),
    protocol.Figures([_]),
    protocol.Notice(notice),
  ] = local.greeting(page)
  assert notice == "The figure bad.svg cannot be drawn: it has a script."
  assert local.figure_files("![](a/b.svg)\n") == ["a/b.svg"]
  // Kept even untouched, since the page has no other copy of it.
  let assert Some(text) = local.kept(page)
  let assert Ok(back) = local.resume(page, text, supply(), now)
  assert back.session.deck == page.session.deck
  assert back.origin == page.origin
  assert back.figures == page.figures
  // The page's own deck gives way to it too.
  let #(home, _, _, _) = started()
  let assert Ok(back) = local.resume(home, text, supply(), now)
  assert back.origin == page.origin
}

/// A folder that cannot be read as a deck is refused with the reason.
pub fn a_folder_without_a_deck_is_refused_test() {
  assert local.open("talk", [], supply(), now)
    == Error("There is no deck.md in talk.")
  let with = fn(path, text) { [#("deck.md", "# Mine\n"), #(path, text)] }
  assert local.open("talk", with("layout.json", "{"), supply(), now)
    == Error("layout.json in talk is not valid.")
  let assert Error("junkslides.toml: " <> _) =
    local.open("talk", with("junkslides.toml", "[palette"), supply(), now)
}

/// Opening a folder and starting over change the deck under the editor.
pub fn the_editor_changes_decks_test() {
  let #(home, _, _, _) = started()
  let #(model, _) = app.init(app.Standalone(home, home))
  let #(model, _) = app.update(model, app.FolderRead(Ok(#("talk", folder))))
  let assert app.InPage(local: page, ..) = model.connection
  assert page.origin
    == local.Folder("talk", list.filter(folder, fn(f) { f.0 != "deck.md" }))
  let #(model, _) = app.update(model, app.Answered(local.greeting(page)))
  let assert Some(shared) = model.deck
  assert shared.variants == ["loud"]
  // A folder that is no deck leaves the editor where it was.
  let #(model, _) = app.update(model, app.FolderRead(Ok(#("empty", []))))
  assert model.notice == Some("There is no deck.md in empty.")
  let assert app.InPage(local: still, ..) = model.connection
  assert still == page
  // Closing the picker says nothing.
  let aborted = app.FolderRead(Error("AbortError: The user aborted a request."))
  let #(model, _) = app.update(model, aborted)
  assert model.notice == Some("There is no deck.md in empty.")
  let #(model, _) = app.update(model, app.StartOver)
  let assert app.InPage(local: page, ..) = model.connection
  assert page == home
}
