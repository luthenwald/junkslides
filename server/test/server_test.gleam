//// The server apart from the outside edit scenarios: protocol replies,
//// undo, view state, the theme, static files, `junkslides init` and the store.

import envoy
import filepath
import gleam/dict
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import junkslides/dialect
import junkslides/file
import junkslides/op
import junkslides/protocol.{Token, View}
import junkslides/render/styles
import junkslides_server
import junkslides_server/highlighter
import junkslides_server/pdf
import junkslides_server/settings
import junkslides_server/shade
import junkslides_server/state
import junkslides_server/store
import junkslides_server/theme
import junkslides_server/view
import junkslides_server/web
import simplifile
import stratus
import support/harness.{example_id}

pub fn failed_op_is_rejected_and_changes_nothing_test() {
  let h = harness.start("rejected", 4891)
  let _ = harness.next_state(h)
  harness.send(h, protocol.Apply(7, [op.Delete(example_id("ff"))]))
  assert harness.next(h) == protocol.Rejected(7, "unknown cell")
  // All or nothing: the edit before the failing op is not applied either.
  harness.send(
    h,
    protocol.Apply(8, [
      op.EditText(example_id("03"), "Changed."),
      op.Delete(example_id("ff")),
    ]),
  )
  assert harness.next(h) == protocol.Rejected(8, "unknown cell")
  harness.send(h, protocol.Hello)
  let #(deck, _) = harness.next_state(h)
  let assert Ok(cell) = harness.find(deck, example_id("03"))
  assert string.starts_with(cell.source, "A lens is")
}

pub fn undo_restores_and_writes_test() {
  let h = harness.start("undo", 4892)
  let #(before, _) = harness.next_state(h)
  let original = harness.read(h.folder, "deck.md")
  harness.send(h, protocol.Apply(1, [op.Delete(example_id("03"))]))
  let #(deck, _) = harness.next_state(h)
  assert harness.eventually(fn() {
    harness.read(h.folder, "deck.md") == file.print(deck)
  })
  harness.send(h, protocol.Undo)
  let #(undone, _) = harness.next_state(h)
  assert undone == before
  assert harness.eventually(fn() {
    harness.read(h.folder, "deck.md") == original
  })
  harness.send(h, protocol.Redo)
  let #(redone, _) = harness.next_state(h)
  assert redone == deck
}

pub fn view_is_stored_per_deck_test() {
  let h = harness.start("view", 4893)
  let _ = harness.next_state(h)
  let wide =
    View(cells_width: 55, cells_hidden: True, slide_hidden: False, snap: 10)
  harness.send(h, protocol.SaveView(wide))
  // The next client of this deck gets it.
  assert harness.eventually(fn() {
    view.load(h.folder <> ".view.json", h.folder) == wide
  })
  let other = harness.connect(h.folder, 4893)
  let assert protocol.State(view:, ..) = harness.next(other)
  assert view == wide
}

pub fn view_file_keeps_other_decks_test() {
  let file = filepath.join(scratch("views"), "junkslides/view.json")
  let a = View(30, False, False, 30)
  let b = View(70, False, True, 120)
  assert view.load(file, "/a") == protocol.default_view
  let assert Ok(Nil) = view.save(file, "/a", a)
  let assert Ok(Nil) = view.save(file, "/b", b)
  assert view.load(file, "/a") == a
  assert view.load(file, "/b") == b
  assert view.default_file("/home/u") == "/home/u/.config/junkslides/view.json"
}

pub fn view_file_without_snap_loads_test() {
  let file = filepath.join(scratch("old-views"), "junkslides/view.json")
  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.directory_name(file))
  let assert Ok(Nil) =
    simplifile.write(
      file,
      "{\"version\": 1, \"decks\": {\"/a\": {\"cells_width\": 30, \"cells_hidden\": false, \"slide_hidden\": true}}}",
    )
  assert view.load(file, "/a")
    == View(cells_width: 30, cells_hidden: False, slide_hidden: True, snap: 30)
}

pub fn theme_change_reloads_and_updates_variants_test() {
  let h = harness.start("theme", 4894)
  let assert protocol.State(variants:, ..) = harness.next(h)
  assert variants == ["large", "small", "quiet", "emphasis"]
  harness.write(h.folder, "theme.css", ":root { --js-variants: \"loud\"; }\n")
  assert harness.next(h) == protocol.ReloadTheme
  let assert protocol.State(variants:, ..) = harness.next(h)
  assert variants == ["loud"]
  // A change that keeps the variants only reloads.
  harness.write(
    h.folder,
    "theme.css",
    ":root { --js-variants: \"loud\"; }\n.js-slide { color: #000; }\n",
  )
  assert harness.next(h) == protocol.ReloadTheme
  assert harness.quiet(h, 200)
}

/// A mark is fine once the theme lists it, and diagnosed until then (D28).
pub fn marks_follow_the_theme_test() {
  let h = harness.start("marks", 4970)
  let _ = harness.next_state(h)
  let cell = example_id("03")
  harness.send(h, protocol.Apply(1, [op.EditText(cell, "A [word]{.now}.")]))
  let assert protocol.State(diagnostics:, ..) = next_full_state(h)
  assert diagnostics == [protocol.Diagnostic(cell, [dialect.UnknownMark])]
  harness.write(h.folder, "theme.css", ":root { --js-marks: \"now\"; }\n")
  let assert protocol.State(diagnostics:, ..) = next_full_state(h)
  assert diagnostics == []
}

fn next_full_state(h: harness.Harness) -> protocol.ServerMsg {
  case harness.next(h) {
    protocol.State(..) as state -> state
    _ -> next_full_state(h)
  }
}

/// A drawing's text reaches clients, again after an edit, and one that
/// could run script is refused with a notice (D29).
pub fn drawings_and_charts_reach_clients_test() {
  let h = harness.start("drawings", 4972)
  let _ = harness.next_state(h)
  harness.write(h.folder, "fan.svg", "<svg class=\"fan\"></svg>")
  let cell = example_id("03")
  harness.send(h, protocol.Apply(1, [op.EditText(cell, "![paths](fan.svg)")]))
  assert next_figures(h) == [#("fan.svg", "<svg class=\"fan\"></svg>")]
  harness.write(h.folder, "fan.svg", "<svg class=\"fan two\"></svg>")
  assert next_figures(h) == [#("fan.svg", "<svg class=\"fan two\"></svg>")]
  harness.write(h.folder, "fan.svg", "<svg onload=\"x()\"></svg>")
  assert next_figures(h) == []
  assert harness.next_notice(h)
    == "The figure fan.svg cannot be drawn: it has event handler attributes."
  // A chart spec goes to clients as it is; the renderer reads it.
  harness.write(h.folder, "c.json", "{\"kind\": \"dots\"}")
  harness.send(h, protocol.Apply(2, [op.EditText(cell, "![c](c.json)")]))
  assert next_figures(h) == [#("c.json", "{\"kind\": \"dots\"}")]
}

fn next_figures(h: harness.Harness) -> List(#(String, String)) {
  case harness.next(h) {
    protocol.Figures(files) -> files
    _ -> next_figures(h)
  }
}

pub fn variants_are_read_from_the_theme_test() {
  assert theme.marks(
      ":root { --js-marks: \"now quiet\"; --js-variants: \"a\" }",
    )
    == ["now", "quiet"]
  assert theme.marks(theme.default_css) == []
  assert theme.variants(theme.default_css)
    == ["large", "small", "quiet", "emphasis"]
  assert theme.variants(":root {\n  --js-variants:\n    'a  b'\n    \"c\" ;\n}")
    == ["a", "b", "c"]
  assert theme.variants(".x { color: red; }") == []
  assert theme.variants(":root { --js-variants: \"a a\" }") == ["a"]
}

pub fn files_the_theme_loads_are_read_test() {
  let css =
    "@font-face { src: url(\"fonts/a.woff2\") format(\"woff2\"), url( 'b.woff' ); }
/* .old { background: url(old.png); } */
.x { background: url( c d.png ) , url(fonts/a.woff2); }
.y { background: url(data:image/png;base64,AAAA); mask: url(#m); }
@import url(https://example.com/font.css);
.z { background: url(\"\"); cursor: url(sub/e:f.png), auto; }"
  assert theme.urls(css)
    == ["fonts/a.woff2", "b.woff", "c d.png", "sub/e:f.png"]
  assert theme.urls(".x { color: red; }") == []
  assert theme.urls("/* never closed url(x.png)") == []
}

pub fn default_theme_is_the_example_theme_test() {
  let assert Ok(css) = simplifile.read("../examples/talk/theme.css")
  assert theme.default_css == css
  let assert Ok(toml) = simplifile.read("../examples/talk/junkslides.toml")
  assert settings.default_toml == toml
  let assert Ok(defaults) = settings.parse(toml)
  assert list.all(settings.files(defaults), fn(file) {
    simplifile.is_file("../examples/talk/" <> file) == Ok(True)
  })
  let assert Ok(fonts) = theme.fonts_folder()
  let assert Ok(names) = simplifile.read_directory(fonts)
  list.each(names, fn(name) {
    assert simplifile.read_bits("../examples/talk/fonts/" <> name)
      == simplifile.read_bits(filepath.join(fonts, name))
  })
}

pub fn static_files_stay_inside_the_deck_folder_test() {
  let h = harness.start("static", 4895)
  let _ = harness.next_state(h)
  let get = fn(path) {
    let assert Ok(req) = request.to("http://127.0.0.1:4895" <> path)
    let assert Ok(response) = httpc.send(req)
    #(response.status, response.body)
  }
  let #(status, body) = get("/")
  assert status == 200
  assert string.contains(body, "/.js/junkslides_client.js")
  assert string.contains(body, "/.js/base.css")
  assert get("/.js/base.css") == #(200, styles.base_css)
  // The default fonts, as raw files, and nothing else from around them.
  let assert Ok(req) =
    request.to("http://127.0.0.1:4895/.js/fonts/et-book-roman.woff2")
  let assert Ok(font) = httpc.send_bits(request.set_body(req, <<>>))
  assert font.status == 200
  assert response.get_header(font, "content-type") == Ok("font/woff2")
  assert get("/.js/fonts/victor-mono.LICENSE").0 == 200
  assert get("/.js/fonts/%2e%2e/static/junkslides.css").0 == 404
  assert get("/theme.css") == #(200, harness.read(h.folder, "theme.css"))
  let assert Ok(Nil) =
    simplifile.write(filepath.join(h.folder, "a b.txt"), "spaced")
  assert get("/a%20b.txt") == #(200, "spaced")
  // The editor's own paths start with a dot, so they hide no deck file.
  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.join(h.folder, "js"))
  let assert Ok(Nil) =
    simplifile.write(filepath.join(h.folder, "js/junkslides.css"), "mine")
  assert get("/js/junkslides.css") == #(200, "mine")
  let assert Ok(Nil) = simplifile.write(filepath.join(h.folder, "ws"), "too")
  assert get("/ws") == #(200, "too")
  assert get("/missing.png").0 == 404
  assert get("/.deck.md.js-tmp").0 == 404
  assert get("/%2e%2e/static/theme.css").0 == 404
  assert get("/a%2f..%2f..%2fstatic%2ftheme.css").0 == 404
}

/// The editor's page runs only its own script, a deck's pages and drawings
/// are served apart from the editor's origin, and every file keeps the type
/// it is sent as.
pub fn pages_say_what_may_run_test() {
  let h = harness.start("policies", 4974)
  let _ = harness.next_state(h)
  let assert Ok(Nil) =
    simplifile.write(filepath.join(h.folder, "viz.html"), "<p>mine</p>")
  let assert Ok(Nil) =
    simplifile.write(filepath.join(h.folder, "fan.svg"), "<svg/>")
  let get = fn(path) {
    let assert Ok(req) = request.to("http://127.0.0.1:4974" <> path)
    let assert Ok(response) = httpc.send(req)
    response
  }
  let policy = response.get_header(_, "content-security-policy")
  let nonce_of = fn(page: response.Response(String)) {
    let assert Ok("script-src 'nonce-" <> rest) = policy(page)
    let assert Ok(#(nonce, "; object-src 'none'; base-uri 'none'")) =
      string.split_once(rest, "'")
    assert string.contains(
      page.body,
      "<script type=module nonce=" <> nonce <> " src=",
    )
    nonce
  }
  let first = nonce_of(get("/"))
  assert string.length(first) >= 22
  assert nonce_of(get("/")) != first
  assert policy(get("/viz.html")) == Ok("sandbox allow-scripts")
  assert policy(get("/fan.svg")) == Ok("sandbox allow-scripts")
  assert policy(get("/theme.css")) == Error(Nil)
  assert policy(get("/.js/base.css")) == Error(Nil)
  list.each(
    ["/", "/viz.html", "/theme.css", "/.js/base.css", "/nothing"],
    fn(path) {
      assert response.get_header(get(path), "x-content-type-options")
        == Ok("nosniff")
    },
  )
}

pub fn serve_says_when_the_port_is_taken_test() {
  let h = harness.start("port-taken", 4899)
  let _ = harness.next_state(h)
  let assert Error(message) = junkslides_server.serve(h.folder, 4899)
  assert string.contains(message, "Could not listen on 127.0.0.1:4899.")
  assert string.contains(message, "--port N")
}

pub fn resolve_refuses_paths_leaving_the_folder_test() {
  assert store.resolve(["assets", "lens.png"]) == Ok("assets/lens.png")
  assert store.resolve(["a%20b.png"]) == Ok("a b.png")
  assert store.resolve([]) == Error(Nil)
  assert store.resolve([".."]) == Error(Nil)
  assert store.resolve(["%2e%2e", "x"]) == Error(Nil)
  assert store.resolve(["a%2F..%2F..%2Fx"]) == Error(Nil)
  assert store.resolve([".hidden"]) == Error(Nil)
  assert store.resolve(["a%00b"]) == Error(Nil)
  assert store.resolve(["a\\..\\b"]) == Error(Nil)
}

pub fn init_creates_a_deck_and_never_replaces_one_test() {
  let folder = filepath.join(scratch("init"), "new deck")
  let assert Ok(Nil) = junkslides_server.init(folder)
  let assert Ok(text) = simplifile.read(filepath.join(folder, "deck.md"))
  let assert Ok(#(deck, _)) = file.parse(text, state.new_supply())
  assert file.print(deck) == text
  let assert [slide] = deck.slides
  let assert [cell] = slide.cells
  assert cell.source == "# Untitled"
  assert simplifile.read(filepath.join(folder, "theme.css"))
    == Ok(theme.default_css)
  assert simplifile.read(filepath.join(folder, "junkslides.toml"))
    == Ok(settings.default_toml)
  // The fonts the default settings name, with their licences.
  let assert Ok(fonts) = theme.fonts_folder()
  let assert Ok(names) = simplifile.read_directory(fonts)
  assert list.length(names) == 8
  list.each(names, fn(name) {
    assert simplifile.read_bits(filepath.join(folder, "fonts/" <> name))
      == simplifile.read_bits(filepath.join(fonts, name))
  })
  let assert Ok(defaults) = settings.parse(settings.default_toml)
  assert list.all(settings.files(defaults), fn(file) {
    list.contains(names, string.drop_start(file, 6))
  })
  let assert Ok(layout) = simplifile.read(filepath.join(folder, "layout.json"))
  assert result.is_ok(file.parse_layout(layout))
  let assert Error(message) = junkslides_server.init(folder)
  assert string.contains(message, "already")
  assert simplifile.read(filepath.join(folder, "deck.md")) == Ok(text)
}

pub fn init_keeps_an_existing_theme_and_settings_test() {
  let folder = scratch("init-theme")
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "theme.css"), "mine")
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "junkslides.toml"), "# mine")
  let assert Ok(Nil) = junkslides_server.init(folder)
  assert simplifile.read(filepath.join(folder, "theme.css")) == Ok("mine")
  assert simplifile.read(filepath.join(folder, "junkslides.toml"))
    == Ok("# mine")
  // Settings of its own bring their own fonts.
  assert simplifile.is_directory(filepath.join(folder, "fonts")) == Ok(False)
}

pub fn serve_refuses_a_folder_without_a_deck_test() {
  let assert Error(message) = junkslides_server.serve(scratch("empty"), 4896)
  assert string.contains(message, "junkslides init")
}

pub fn atomic_write_leaves_no_temporary_file_test() {
  let folder = scratch("store")
  let path = filepath.join(folder, "deck.md")
  let assert Ok(one) = store.write_atomic(path, <<"one":utf8>>)
  let assert Ok(two) = store.write_atomic(path, <<"two":utf8>>)
  assert one != two
  assert store.read(path) == Ok(#(<<"two":utf8>>, two))
  assert simplifile.read_directory(folder) == Ok(["deck.md"])
}

// Helpers -------------------------------------------------------------------

fn scratch(name: String) -> String {
  let assert Ok(cwd) = simplifile.current_directory()
  let folder = filepath.join(cwd, "build/scratch/" <> name)
  let _ = simplifile.delete(folder)
  let assert Ok(Nil) = simplifile.create_directory_all(folder)
  folder
}

/// A write that fails is said once, and the file is listed as not saved,
/// to late clients too, until a write of it works. It is tried again every
/// second.
pub fn a_failed_write_is_said_until_one_works_test() {
  let h = harness.start("unwritable", 4979)
  let _ = harness.next_state(h)
  let laws = example_id("08")
  let assert Ok(Nil) = simplifile.set_permissions_octal(h.folder, 0o555)
  harness.send(h, protocol.Apply(1, [op.EditText(laws, "## In memory")]))
  let problem = harness.next_notice(h)
  let restore = fn() {
    let assert Ok(Nil) = simplifile.set_permissions_octal(h.folder, 0o755)
  }
  case string.starts_with(problem, "Could not write deck.md: ") {
    True -> Nil
    False -> {
      restore()
      panic as problem
    }
  }
  let unsaved = harness.next_unsaved(h)
  let late = harness.connect(h.folder, 4979)
  let told = harness.next_unsaved(late)
  restore()
  assert unsaved == [#("deck.md", problem)]
  assert told == unsaved
  // The write is tried again by itself, without a further edit.
  assert harness.next_unsaved(h) == []
  assert string.contains(harness.read(h.folder, "deck.md"), "## In memory")
}

/// A deck.md that is a link to a file kept elsewhere stays a link, and the
/// file behind it is the one replaced, with the permissions it had.
pub fn atomic_write_goes_through_a_link_and_keeps_permissions_test() {
  let folder = scratch("store-link")
  let elsewhere = scratch("store-link-elsewhere")
  let real = filepath.join(elsewhere, "real.md")
  let link = filepath.join(folder, "deck.md")
  let assert Ok(Nil) = simplifile.write(real, "one")
  let assert Ok(Nil) = simplifile.set_permissions_octal(real, 0o600)
  let assert Ok(Nil) =
    simplifile.create_symlink("../store-link-elsewhere/real.md", link)
  let assert Ok(_) = store.write_atomic(link, <<"two":utf8>>)
  assert simplifile.is_symlink(link) == Ok(True)
  assert simplifile.read(real) == Ok("two")
  let assert Ok(info) = simplifile.file_info(real)
  assert simplifile.file_info_permissions_octal(info) == 0o600
  assert simplifile.read_directory(folder) == Ok(["deck.md"])
  assert simplifile.read_directory(elsewhere) == Ok(["real.md"])
}

/// The server's own write is not read back as an outside edit: an undo that
/// follows a write, before any poll, survives the next flush.
pub fn own_write_is_not_an_outside_edit_test() {
  let h = harness.serve_with(harness.folder("own-write"), 4898, 60_000, 50)
  let #(before, _) = harness.next_state(h)
  let original = harness.read(h.folder, "deck.md")
  harness.send(h, protocol.Apply(1, [op.Delete(example_id("03"))]))
  let #(deck, _) = harness.next_state(h)
  assert harness.eventually(fn() {
    harness.read(h.folder, "deck.md") == file.print(deck)
  })
  harness.send(h, protocol.Undo)
  let #(undone, _) = harness.next_state(h)
  assert undone == before
  assert harness.eventually(fn() {
    harness.read(h.folder, "deck.md") == original
  })
  assert harness.quiet(h, 200)
}

pub fn dump_languages_names_the_grammars_test() {
  let languages =
    highlighter.parse_languages(
      "name: c\nscope: source.c\nparser: \"/x\"\nfile_types: [\"c\", \"h\"]\ncontent_regex: None\n\n"
      <> "name: clojure\nscope: \nfile_types: []\n\n"
      <> "name: haskell\nscope: haskell\nfile_types: [\"hs\", \"hs-boot\"]\n",
    )
  assert dict.get(languages, "c") == Ok("source.c")
  assert dict.get(languages, "source.c") == Ok("source.c")
  assert dict.get(languages, "h") == Ok("source.c")
  assert dict.get(languages, "hs") == Ok("haskell")
  assert dict.get(languages, "haskell") == Ok("haskell")
  // A grammar without a scope cannot be asked for.
  assert dict.get(languages, "clojure") == Error(Nil)
}

/// The shape of the real command's output, from tree-sitter 0.26.1.
const sample =
  "<!doctype HTML>
<table>
<tr><td class=line-number>1</td><td class=line><span class='comment'>-- a &lt; b</span>
</td></tr>
<tr><td class=line-number>2</td><td class=line><span class='function'><span class='function'><span class='type'>f</span> <span class='operator'>::</span></span></span> <span class='string special'><span class='punctuation bracket'>(</span><span class='punctuation bracket'>)</span></span>
</td></tr>
<tr><td class=line-number>3</td><td class=line>  <span class='string'>&quot;&amp;&#39;&quot;</span>
</td></tr>
</table>
</body>"

pub fn highlight_output_becomes_tokens_test() {
  let code = "-- a < b\nf :: ()\n  \"&'\"\n"
  let assert Ok(tokens) = highlighter.tokens_of(sample, code)
  assert tokens
    == [
      Token(Some("comment"), "-- a < b"),
      Token(None, "\n"),
      Token(Some("type"), "f"),
      Token(None, " "),
      Token(Some("operator"), "::"),
      Token(None, " "),
      Token(Some("punctuation.bracket"), "()"),
      Token(None, "\n  "),
      Token(Some("string"), "\"&'\""),
      Token(None, "\n"),
    ]
  // Output that does not give the code back is not trusted.
  assert highlighter.tokens_of(sample, "other") == Error(Nil)
  assert highlighter.tokens_of("no table", code) == Error(Nil)
}

pub fn code_blocks_are_highlighted_for_clients_test() {
  let h =
    harness.serve_with_tree_sitter(
      harness.folder("highlights"),
      4879,
      "test/fixtures/fake-tree-sitter",
    )
  // The example's Gleam block arrives after the state; a block in a language
  // without a grammar stays out.
  let assert protocol.Highlights([protocol.Highlight(block, tokens)]) =
    harness.next_highlights(h)
  assert block.language == "gleam"
  assert string.starts_with(block.code, "pub type Lens")
  assert list.first(tokens) == Ok(Token(Some("keyword"), "pub"))
  // A new client gets them with its state.
  let other = harness.connect(h.folder, 4879)
  let assert protocol.Highlights([_]) = harness.next_highlights(other)
}

pub fn a_missing_command_leaves_code_plain_test() {
  assert highlighter.languages("js-no-such-command") == Error(Nil)
}

// Export ---------------------------------------------------------------------

/// A copy of the example deck to export, with images and a file or two that
/// must stay behind. The name is unique to a test.
fn export_deck(name: String) -> String {
  let folder = harness.folder(name)
  let write = fn(relative, contents) -> Nil {
    let path = filepath.join(folder, relative)
    let assert Ok(Nil) =
      simplifile.create_directory_all(filepath.directory_name(path))
    let assert Ok(Nil) = simplifile.write(path, contents)
    Nil
  }
  write("assets/lens.png", "lens")
  write("assets/icon.png", "icon")
  write("assets/sub/font.woff2", "font")
  write("assets/.hidden", "hidden")
  write("side.png", "side")
  write("../" <> name <> "-secret.png", "secret")
  let assert Ok(deck) = simplifile.read(filepath.join(folder, "deck.md"))
  write(
    "deck.md",
    deck
      <> "\n---\n\n<!-- cell -->\n![s](side.png) ![m](gone.png) ![u](../"
      <> name
      <> "-secret.png)\n\n<!-- notes -->\n![n](notes.png)\n",
  )
  write("notes.png", "only in notes")
  folder
}

/// A program that stands in for the browser, so these tests need none. `$out`
/// is where it was told to print.
fn fake_browser(name: String, body: String) -> String {
  let path = filepath.join(harness.folder(name), "fake-browser")
  let assert Ok(Nil) =
    simplifile.write(
      path,
      "#!/bin/sh\n"
        <> "for a in \"$@\"; do case \"$a\" in --print-to-pdf=*) out=\"${a#*=}\";; esac; done\n"
        <> body
        <> "\n",
    )
  let assert Ok(Nil) = simplifile.set_permissions_octal(path, 0o755)
  path
}

pub fn a_pdf_is_written_beside_the_page_named_after_the_deck_test() {
  let folder = export_deck("export-pdf")
  let deck = harness.read(folder, "deck.md")
  let browser =
    fake_browser("export-pdf-browser", "printf '%%PDF-1.7 x' > \"$out\"")
  let assert Ok(report) =
    junkslides_server.export_pdf(folder, None, "no-such-command", browser)
  let out = filepath.join(folder, "export")
  assert report.page == filepath.join(out, "export-pdf.pdf")
  assert harness.read(out, "export-pdf.pdf") == "%PDF-1.7 x"
  assert exists(out, "index.html")
  assert report.warnings != []
  assert harness.read(folder, "deck.md") == deck
  assert simplifile.read_directory(out)
    |> result.map(list.filter(_, string.ends_with(_, ".js-tmp")))
    == Ok([])
}

pub fn a_failed_pdf_leaves_the_last_one_alone_test() {
  let folder = export_deck("export-pdf-fails")
  let out = filepath.join(folder, "export")
  let assert Ok(Nil) = simplifile.create_directory_all(out)
  let assert Ok(Nil) =
    simplifile.write(filepath.join(out, "export-pdf-fails.pdf"), "the last one")
  let attempt = fn(name, body) {
    junkslides_server.export_pdf(
      folder,
      None,
      "no-such-command",
      fake_browser("export-pdf-fails-" <> name, body),
    )
  }
  let assert Error(not_a_pdf) = attempt("junk", "echo oops > \"$out\"")
  assert string.contains(not_a_pdf, "not a PDF")
  let assert Error(no_file) = attempt("silent", "exit 0")
  assert string.contains(no_file, "did not write")
  let assert Error(stopped) = attempt("stops", "echo broken; exit 3")
  assert string.contains(stopped, "code 3")
  assert string.contains(stopped, "broken")
  assert harness.read(out, "export-pdf-fails.pdf") == "the last one"
}

pub fn a_deck_that_does_not_read_makes_no_pdf_test() {
  let folder = export_deck("export-pdf-broken")
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "layout.json"), "not json")
  let browser = fake_browser("export-pdf-broken-browser", "echo x > \"$out\"")
  let assert Error(_) =
    junkslides_server.export_pdf(folder, None, "no-such-command", browser)
  assert !exists(folder, "export/export-pdf-broken.pdf")
}

pub fn the_browser_named_by_the_environment_comes_first_test() {
  let browser = fake_browser("export-pdf-find", "exit 0")
  let before = envoy.get("JUNKSLIDES_CHROME")
  envoy.set("JUNKSLIDES_CHROME", browser)
  let found = pdf.find()
  envoy.set("JUNKSLIDES_CHROME", "/no/such/browser")
  let missing = pdf.find()
  case before {
    Ok(value) -> envoy.set("JUNKSLIDES_CHROME", value)
    Error(Nil) -> envoy.unset("JUNKSLIDES_CHROME")
  }
  assert found == Ok(browser)
  assert missing
    == Error("JUNKSLIDES_CHROME names no program: /no/such/browser")
}

pub fn a_file_address_escapes_what_would_break_it_test() {
  assert pdf.file_url("/talks/my talk #2/index.html")
    == "file:///talks/my%20talk%20%232/index.html"
}

fn exists(folder: String, relative: String) -> Bool {
  simplifile.is_file(filepath.join(folder, relative)) == Ok(True)
}

/// The showcase deck exports whole: every figure found and drawn, every font
/// and file its theme and settings load, and nothing to warn about.
pub fn the_showcase_exports_whole_test() {
  let assert Ok(cwd) = simplifile.current_directory()
  let folder = filepath.join(cwd, "build/scenarios/showcase")
  let _ = simplifile.delete(folder)
  let assert Ok(Nil) = simplifile.copy_directory("../examples/showcase", folder)
  let assert Ok(report) =
    junkslides_server.export_deck(folder, None, "no-such-command")
  assert report.warnings == []
  let out = filepath.join(folder, "export")
  let page = harness.read(out, "index.html")
  assert list.length(string.split(page, "class=\"js-frame\"")) == 14
  assert string.contains(page, "--js-index:13;--js-total:13;")
  assert string.contains(page, "class=\"folder\"")
  assert string.contains(page, "class=\"rebase\"")
  assert list.length(string.split(page, "class=\"js-chart\"")) == 3
  assert !string.contains(page, "class=\"js-chart js-chart-missing\"")
  assert string.contains(page, "src=\"assets/settle.html\"")
  assert !string.contains(page, "Speaker notes like this one")
  assert exists(out, "assets/settle.html")
  assert exists(out, "fonts/et-book-roman.woff2")
  assert exists(out, "fonts/victor-mono.LICENSE")
}

pub fn export_writes_a_folder_and_leaves_the_deck_alone_test() {
  let folder = export_deck("export-folder")
  let deck = harness.read(folder, "deck.md")
  let layout = harness.read(folder, "layout.json")
  let assert Ok(report) =
    junkslides_server.export_deck(folder, None, "no-such-command")
  let out = filepath.join(folder, "export")
  assert report.page == filepath.join(out, "index.html")
  assert harness.read(out, "theme.css") == harness.read(folder, "theme.css")
  // The default theme's fonts come from the deck, with their licences.
  assert exists(out, "fonts/et-book-roman.woff2")
  assert exists(out, "fonts/victor-mono-italic.woff2")
  assert exists(out, "fonts/et-book.LICENSE")
  assert exists(out, "fonts/victor-mono.LICENSE")
  assert exists(out, "assets/lens.png")
  assert exists(out, "assets/sub/font.woff2")
  assert exists(out, "side.png")
  assert !exists(out, "assets/.hidden")
  assert !exists(out, "notes.png")
  // Nothing from outside the deck, whichever way it is reached.
  assert !exists(out, "../export-folder-secret.png")
  assert report.warnings
    == [
      "Missing image: gone.png",
      "Left out an image outside the deck: ../export-folder-secret.png",
    ]
  let page = harness.read(out, "index.html")
  assert string.contains(page, "<title>export-folder</title>")
  assert string.contains(page, "href=\"theme.css\"")
  assert string.contains(page, "src=\"side.png\"")
  assert !string.contains(page, "Mention Boomerang here.")
  assert harness.read(folder, "deck.md") == deck
  assert harness.read(folder, "layout.json") == layout
}

/// A font the theme loads from a folder of the deck reaches the export with the
/// licences beside it, nothing else of that folder does, and what cannot be
/// included is named.
pub fn export_copies_the_files_the_theme_loads_test() {
  let folder = export_deck("export-theme-files")
  // Only the theme loads files here.
  let assert Ok(Nil) =
    simplifile.delete(filepath.join(folder, "junkslides.toml"))
  let write = fn(relative, contents) {
    let path = filepath.join(folder, relative)
    let assert Ok(Nil) =
      simplifile.create_directory_all(filepath.directory_name(path))
    let assert Ok(Nil) = simplifile.write(path, contents)
    Nil
  }
  write("fonts/custom.woff2", "custom")
  write("fonts/OFL-licence.txt", "licence")
  write("fonts/.LICENSE.swp", "hidden")
  write("art/paper.png", "paper")
  write("../export-theme-files-outside.woff2", "outside")
  write(
    "theme.css",
    "@font-face { src: url(\"fonts/custom.woff2\") format(\"woff2\"); }
.js-slide { background: url('./art/paper.png?v=2'), url(gone.woff2); }
.a { background: url(../export-theme-files-outside.woff2); }
.b { background: url(/art/paper.png); }
.c { background: url(assets/sub/font.woff2); }
",
  )
  let assert Ok(report) =
    junkslides_server.export_deck(folder, None, "no-such-command")
  let out = filepath.join(folder, "export")
  assert harness.read(out, "fonts/custom.woff2") == "custom"
  assert harness.read(out, "art/paper.png") == "paper"
  assert exists(out, "assets/sub/font.woff2")
  assert exists(out, "fonts/et-book.LICENSE")
  assert exists(out, "fonts/OFL-licence.txt")
  assert !exists(out, "fonts/.LICENSE.swp")
  // Not loaded by this theme, so not exported, though junkslides ships it and the
  // default junkslides.toml names it.
  assert !exists(out, "fonts/et-book-roman.woff2")
  assert !exists(out, "../export-theme-files-outside.woff2")
  assert report.warnings
    == [
      "Missing image: gone.png",
      "Left out an image outside the deck: ../export-theme-files-secret.png",
      "Missing file in theme.css: gone.woff2",
      "Left out a file outside the deck in theme.css: ../export-theme-files-outside.woff2",
      "Use a relative path in theme.css: /art/paper.png",
    ]
}

/// The fonts junkslides.toml names reach the export with their licences, and its
/// settings.css names them by paths beside the page.
pub fn export_writes_the_settings_and_their_fonts_test() {
  let folder = export_deck("export-settings")
  let write = fn(relative, contents) {
    let path = filepath.join(folder, relative)
    let assert Ok(Nil) =
      simplifile.create_directory_all(filepath.directory_name(path))
    let assert Ok(Nil) = simplifile.write(path, contents)
    Nil
  }
  write("type/serif.woff2", "serif")
  write("type/LICENSE.txt", "licence")
  write("type/unused.woff2", "unused")
  write(
    "junkslides.toml",
    "[font.text]\nfamily = \"Serif\"\nregular = \"type/serif.woff2\"\n"
      <> "italic = \"type/gone.woff2\"\n[palette]\ntext = \"#333\"\n",
  )
  // A file of the deck's own by the name the export uses for the settings.
  write("settings.css", "mine")
  write("theme.css", ".x { background: url(settings.css); }\n")
  let assert Ok(report) =
    junkslides_server.export_deck(folder, None, "no-such-command")
  let out = filepath.join(folder, "export")
  assert harness.read(out, "type/serif.woff2") == "serif"
  assert exists(out, "type/LICENSE.txt")
  assert !exists(out, "type/unused.woff2")
  let css = harness.read(out, "settings.css")
  assert string.contains(css, "url(\"type/serif.woff2\")")
  assert string.contains(css, "--js-text: #333;")
  let page = harness.read(out, "index.html")
  let assert Ok(#(before_theme, _)) =
    string.split_once(page, "href=\"theme.css\"")
  assert string.contains(before_theme, "href=\"settings.css\"")
  assert report.warnings
    == [
      "Missing image: gone.png",
      "Left out an image outside the deck: ../export-settings-secret.png",
      "Missing file in junkslides.toml: type/gone.woff2",
      "theme.css loads settings.css, which the export writes from junkslides.toml.",
    ]
}

pub fn export_without_settings_links_none_test() {
  let folder = export_deck("export-no-settings")
  let _ = simplifile.delete(filepath.join(folder, "junkslides.toml"))
  let assert Ok(_) =
    junkslides_server.export_deck(folder, None, "no-such-command")
  let out = filepath.join(folder, "export")
  assert !exists(out, "settings.css")
  assert !string.contains(harness.read(out, "index.html"), "settings.css")
}

pub fn export_again_replaces_and_deletes_nothing_test() {
  let folder = export_deck("export-again")
  let out = filepath.join(folder, "elsewhere")
  let assert Ok(Nil) = simplifile.create_directory_all(out)
  let assert Ok(Nil) = simplifile.write(filepath.join(out, "mine.txt"), "mine")
  let assert Ok(_) =
    junkslides_server.export_deck(folder, Some(out), "no-such-command")
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "theme.css"), "new")
  let assert Ok(_) =
    junkslides_server.export_deck(folder, Some(out), "no-such-command")
  assert harness.read(out, "theme.css") == "new"
  assert harness.read(out, "mine.txt") == "mine"
}

pub fn export_refuses_the_deck_folder_and_its_assets_test() {
  let folder = export_deck("export-refuses")
  let assert Error(_) =
    junkslides_server.export_deck(folder, Some(folder), "no-such-command")
  let assert Error(_) =
    junkslides_server.export_deck(
      folder,
      Some(filepath.join(folder, "assets/out")),
      "no-such-command",
    )
  assert !exists(folder, "index.html")
  assert !exists(folder, "assets/out/index.html")
}

/// A path that names the deck's folder in another way, here through a link,
/// is the deck's folder: nothing is written, and no file is copied onto
/// itself, which would empty it.
pub fn export_refuses_the_deck_folder_by_another_name_test() {
  let folder = export_deck("export-alias")
  let alias = folder <> "-alias"
  let _ = simplifile.delete(alias)
  let assert Ok(Nil) = simplifile.create_symlink(folder, alias)
  assert junkslides_server.export_deck(folder, Some(alias), "no-such-command")
    == Error("Export to a folder of its own, not to the deck's folder.")
  let assert Error(_) =
    junkslides_server.export_deck(
      folder,
      Some(filepath.join(alias, "assets")),
      "no-such-command",
    )
  assert !exists(folder, "index.html")
  assert simplifile.read(filepath.join(folder, "assets/lens.png")) == Ok("lens")
  assert simplifile.read(filepath.join(folder, "side.png")) == Ok("side")
  let assert Ok(Nil) = simplifile.delete(alias)
}

pub fn export_writes_nothing_when_a_file_does_not_read_test() {
  let folder = export_deck("export-broken-deck")
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "deck.md"), "<!-- deck v99 -->\n")
  let assert Error(_) =
    junkslides_server.export_deck(folder, None, "no-such-command")
  assert simplifile.is_directory(filepath.join(folder, "export")) == Ok(False)
  let folder = export_deck("export-broken-layout")
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "layout.json"), "{")
  let assert Error(_) =
    junkslides_server.export_deck(folder, None, "no-such-command")
  assert simplifile.is_directory(filepath.join(folder, "export")) == Ok(False)
  let folder = export_deck("export-broken-settings")
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "junkslides.toml"), "[fonts]\n")
  let assert Error(message) =
    junkslides_server.export_deck(folder, None, "no-such-command")
  assert message == "junkslides.toml: fonts is not a setting."
  assert simplifile.is_directory(filepath.join(folder, "export")) == Ok(False)
}

pub fn export_highlights_code_test() {
  let folder = export_deck("export-highlight")
  let assert Ok(Nil) =
    simplifile.append(
      filepath.join(folder, "deck.md"),
      "\n---\n\n<!-- cell -->\n```hs\nmain\n```\n",
    )
  let assert Ok(cwd) = simplifile.current_directory()
  let assert Ok(report) =
    junkslides_server.export_deck(
      folder,
      None,
      filepath.join(cwd, "test/fixtures/fake-tree-sitter"),
    )
  assert string.contains(
    harness.read(filepath.directory_name(report.page), "index.html"),
    "js-tok-",
  )
}

pub fn settings_read_code_keywords_test() {
  let assert Ok(read) =
    settings.parse("[code]\nkeywords = [\"while\", \"do'\"]\n")
  assert settings.shading(Some(read))
    == shade.Rules(["while", "do'"], shade.default_comments, [])
  assert settings.shading(None) == shade.default_rules
  let assert Ok(read) =
    settings.parse(
      "[code]\ncomments = [\"--\"]\nsimple = [\"haskell\", \"c++\"]\n",
    )
  assert settings.shading(Some(read))
    == shade.Rules(shade.default_keywords, ["--"], ["haskell", "c++"])
  let assert Error(_) = settings.parse("[code]\ncomments = [\"- -\"]\n")
  let assert Error(_) = settings.parse("[code]\nsimple = [\"a b\"]\n")
  let assert Error(_) = settings.parse("[code]\nkeywords = [\"a b\"]\n")
  let assert Error(_) = settings.parse("[code]\nkeywords = \"while\"\n")
  let assert Error(_) = settings.parse("[code]\nwords = []\n")
}

/// The example's gleam block has no grammar here, so it is shaded, and new
/// keywords in junkslides.toml shade it again (D30).
pub fn keywords_from_settings_shade_again_test() {
  let h = harness.start("keywords", 4971)
  let assert protocol.Highlights([block]) = harness.next_highlights(h)
  assert list.contains(block.tokens, Token(Some("keyword"), "fn"))
  harness.write(h.folder, "junkslides.toml", "[code]\nkeywords = [\"pub\"]\n")
  let assert protocol.Highlights([block]) = harness.next_highlights(h)
  assert list.contains(block.tokens, Token(Some("keyword"), "pub"))
  assert !list.contains(block.tokens, Token(Some("keyword"), "fn"))
}

pub fn settings_reload_and_keep_the_last_good_sheet_test() {
  let h = harness.start("settings", 4960)
  let _ = harness.next_state(h)
  let get = fn() {
    let assert Ok(req) = request.to("http://127.0.0.1:4960/.js/settings.css")
    let assert Ok(response) = httpc.send(req)
    assert response.status == 200
    response.body
  }
  let good = "[palette]\nbackground = \"#101010\"\n"
  let assert Ok(expected) = settings.parse(good)
  harness.write(h.folder, "junkslides.toml", good)
  assert harness.next(h) == protocol.ReloadTheme
  assert get() == settings.to_css(expected, "/")
  // A file that does not read keeps the sheet, says why, and reloads nothing.
  harness.write(
    h.folder,
    "junkslides.toml",
    "[palette]\nbackgrund = \"#000\"\n",
  )
  let notice = harness.next(h)
  assert notice
    == protocol.Notice(
      "junkslides.toml: palette.backgrund is not a setting. junkslides keeps the settings"
      <> " it last read until the file is fixed.",
    )
  assert harness.quiet(h, 300)
  assert get() == settings.to_css(expected, "/")
  // A client that joins now is told too.
  let late = harness.connect(h.folder, 4960)
  let _ = harness.next_state(late)
  assert harness.next_notice(late)
    == "junkslides.toml: palette.backgrund is not a setting. junkslides keeps the settings it last read until the file is fixed."
  harness.write(h.folder, "junkslides.toml", good <> "accent = \"#fff\"\n")
  assert harness.next(h) == protocol.Notice("junkslides.toml reads again.")
  assert harness.next(h) == protocol.ReloadTheme
  assert string.contains(get(), "--js-accent: #fff;")
  // Without the file there are no settings.
  let assert Ok(Nil) =
    simplifile.delete(filepath.join(h.folder, "junkslides.toml"))
  assert harness.next(h) == protocol.ReloadTheme
  assert get() == ""
}

pub fn settings_name_missing_font_files_test() {
  let h = harness.start("settings-fonts", 4961)
  let _ = harness.next_state(h)
  harness.write(
    h.folder,
    "junkslides.toml",
    "[font.text]\nfamily = \"Gone\"\nregular = \"fonts/gone.woff2\"\n",
  )
  assert harness.next(h)
    == protocol.Notice(
      "junkslides.toml names files that are missing: fonts/gone.woff2.",
    )
  assert harness.next(h) == protocol.ReloadTheme
}

pub fn only_the_editors_own_page_reaches_the_server_test() {
  let at = fn(host, origin) {
    let req = request.new() |> request.set_header("host", host)
    case origin {
      "" -> req
      _ -> request.set_header(req, "origin", origin)
    }
  }
  assert web.trusted(at("127.0.0.1:4800", ""), 4800)
  assert web.trusted(at("localhost:4800", ""), 4800)
  // A name that resolves here, and another port.
  assert !web.trusted(at("evil.example:4800", ""), 4800)
  assert !web.trusted(at("127.0.0.1:4801", ""), 4800)
  assert !web.trusted(request.new(), 4800)
  assert web.same_origin(at("127.0.0.1:4800", ""), 4800)
  assert web.same_origin(at("127.0.0.1:4800", "http://localhost:4800"), 4800)
  assert !web.same_origin(at("127.0.0.1:4800", "null"), 4800)
  assert !web.same_origin(at("127.0.0.1:4800", "https://example.com"), 4800)
  assert !web.same_origin(at("127.0.0.1:4800", "http://127.0.0.1:4801"), 4800)
  // A socket from a sandboxed frame is refused; the editor's is not.
  let h = harness.start("origins", 4973)
  let _ = harness.next_state(h)
  let open = fn(origin) {
    let assert Ok(req) = request.to("http://127.0.0.1:4973/.js/ws")
    stratus.new(request: request.set_header(req, "origin", origin), state: Nil)
    |> stratus.on_message(fn(state, _, _) { stratus.continue(state) })
    |> stratus.start
    |> result.is_ok
  }
  assert !open("null")
  assert open("http://127.0.0.1:4973")
}
