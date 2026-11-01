//// The server apart from the outside edit scenarios: protocol replies,
//// undo, view state, the theme, static files, `zeno init` and the store.

import filepath
import gleam/dict
import gleam/http/request
import gleam/httpc
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile
import support/harness.{example_id}
import zeno/file
import zeno/op
import zeno/protocol.{Token, View}
import zeno/render/styles
import zeno_server
import zeno_server/highlighter
import zeno_server/state
import zeno_server/store
import zeno_server/theme
import zeno_server/view
import zeno_server/web

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
  let file = filepath.join(scratch("views"), "zeno/view.json")
  let a = View(30, False, False, 30)
  let b = View(70, False, True, 120)
  assert view.load(file, "/a") == protocol.default_view
  let assert Ok(Nil) = view.save(file, "/a", a)
  let assert Ok(Nil) = view.save(file, "/b", b)
  assert view.load(file, "/a") == a
  assert view.load(file, "/b") == b
  assert view.default_file("/home/u") == "/home/u/.config/zeno/view.json"
}

pub fn view_file_without_snap_loads_test() {
  let file = filepath.join(scratch("old-views"), "zeno/view.json")
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
  harness.write(h.folder, "theme.css", ":root { --zeno-variants: \"loud\"; }\n")
  assert harness.next(h) == protocol.ReloadTheme
  let assert protocol.State(variants:, ..) = harness.next(h)
  assert variants == ["loud"]
  // A change that keeps the variants only reloads.
  harness.write(
    h.folder,
    "theme.css",
    ":root { --zeno-variants: \"loud\"; }\n.zeno-slide { color: #000; }\n",
  )
  assert harness.next(h) == protocol.ReloadTheme
  assert harness.quiet(h, 200)
}

pub fn variants_are_read_from_the_theme_test() {
  assert theme.variants(theme.default_css)
    == ["large", "small", "quiet", "emphasis"]
  assert theme.variants(
      ":root {\n  --zeno-variants:\n    'a  b'\n    \"c\" ;\n}",
    )
    == ["a", "b", "c"]
  assert theme.variants(".x { color: red; }") == []
  assert theme.variants(":root { --zeno-variants: \"a a\" }") == ["a"]
}

pub fn default_theme_is_the_example_theme_test() {
  let assert Ok(css) = simplifile.read("../examples/talk/theme.css")
  assert theme.default_css == css
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
  assert string.contains(body, "/.zeno/zeno_client.js")
  assert string.contains(body, "/.zeno/base.css")
  assert get("/.zeno/base.css") == #(200, styles.base_css)
  assert get("/theme.css") == #(200, harness.read(h.folder, "theme.css"))
  let assert Ok(Nil) =
    simplifile.write(filepath.join(h.folder, "a b.txt"), "spaced")
  assert get("/a%20b.txt") == #(200, "spaced")
  // The editor's own paths start with a dot, so they hide no deck file.
  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.join(h.folder, "zeno"))
  let assert Ok(Nil) =
    simplifile.write(filepath.join(h.folder, "zeno/zeno.css"), "mine")
  assert get("/zeno/zeno.css") == #(200, "mine")
  let assert Ok(Nil) = simplifile.write(filepath.join(h.folder, "ws"), "too")
  assert get("/ws") == #(200, "too")
  assert get("/missing.png").0 == 404
  assert get("/.deck.md.zeno-tmp").0 == 404
  assert get("/%2e%2e/static/theme.css").0 == 404
  assert get("/a%2f..%2f..%2fstatic%2ftheme.css").0 == 404
}

pub fn serve_says_when_the_port_is_taken_test() {
  let h = harness.start("port-taken", 4899)
  let _ = harness.next_state(h)
  let assert Error(message) = zeno_server.serve(h.folder, 4899)
  assert string.contains(message, "Could not listen on 127.0.0.1:4899.")
  assert string.contains(message, "--port N")
}

pub fn resolve_refuses_paths_leaving_the_folder_test() {
  assert web.resolve(["assets", "lens.png"]) == Ok("assets/lens.png")
  assert web.resolve(["a%20b.png"]) == Ok("a b.png")
  assert web.resolve([]) == Error(Nil)
  assert web.resolve([".."]) == Error(Nil)
  assert web.resolve(["%2e%2e", "x"]) == Error(Nil)
  assert web.resolve(["a%2F..%2F..%2Fx"]) == Error(Nil)
  assert web.resolve([".hidden"]) == Error(Nil)
  assert web.resolve(["a%00b"]) == Error(Nil)
  assert web.resolve(["a\\..\\b"]) == Error(Nil)
}

pub fn init_creates_a_deck_and_never_replaces_one_test() {
  let folder = filepath.join(scratch("init"), "new deck")
  let assert Ok(Nil) = zeno_server.init(folder)
  let assert Ok(text) = simplifile.read(filepath.join(folder, "deck.md"))
  let assert Ok(#(deck, _)) = file.parse(text, state.new_supply())
  assert file.print(deck) == text
  let assert [slide] = deck.slides
  let assert [cell] = slide.cells
  assert cell.source == "# Untitled"
  assert simplifile.read(filepath.join(folder, "theme.css"))
    == Ok(theme.default_css)
  let assert Ok(layout) = simplifile.read(filepath.join(folder, "layout.json"))
  assert result.is_ok(file.parse_layout(layout))
  let assert Error(message) = zeno_server.init(folder)
  assert string.contains(message, "already")
  assert simplifile.read(filepath.join(folder, "deck.md")) == Ok(text)
}

pub fn init_keeps_an_existing_theme_test() {
  let folder = scratch("init-theme")
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "theme.css"), "mine")
  let assert Ok(Nil) = zeno_server.init(folder)
  assert simplifile.read(filepath.join(folder, "theme.css")) == Ok("mine")
}

pub fn serve_refuses_a_folder_without_a_deck_test() {
  let assert Error(message) = zeno_server.serve(scratch("empty"), 4896)
  assert string.contains(message, "zeno init")
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
  assert highlighter.languages("zeno-no-such-command") == Error(Nil)
}
