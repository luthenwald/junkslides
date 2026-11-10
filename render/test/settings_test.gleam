import gleam/list
import gleam/option.{None, Some}
import gleam/string
import junkslides/settings.{Font}

const full =
  "
[font.text]
family = \"et-book\"
fallback = '\"Palatino Linotype\", Georgia, serif'
regular = \"./fonts/et-book-roman.woff2\"
bold-italic = \"fonts/et-book-bold-italic.ttf\"

[font.code]
family = \"Menlo\"

[palette]
background = \"#fafafa\"
text = \"rgb(20 20 20 / 90%)\"
quiet = \"#777\"
accent = \"black\"

[type]
size = 32
line-height = 1.4
code-scale = 0.875

[slide]
numbers = \"01\"
margin = [2, 3]
gap = 24
"

fn parsed(source: String) -> settings.Settings {
  let assert Ok(parsed) = settings.parse(source)
  parsed
}

fn refused(source: String) -> String {
  let assert Error(message) = settings.parse(source)
  message
}

pub fn every_setting_is_read_test() {
  let s = parsed(full)
  assert s.text_font
    == Some(
      Font("et-book", Some("\"Palatino Linotype\", Georgia, serif"), [
        #(settings.Regular, "fonts/et-book-roman.woff2"),
        #(settings.BoldItalic, "fonts/et-book-bold-italic.ttf"),
      ]),
    )
  assert s.code_font == Some(Font("Menlo", None, []))
  assert s.background == Some("#fafafa")
  assert s.text == Some("rgb(20 20 20 / 90%)")
  assert s.size == Some(32.0)
  assert s.code_scale == Some(0.875)
  assert s.numbers == Some(settings.Short)
  assert s.margin == Some(#(2, 3))
  assert s.gap == Some(24.0)
  assert settings.files(s)
    == ["fonts/et-book-roman.woff2", "fonts/et-book-bold-italic.ttf"]
}

pub fn an_empty_file_sets_nothing_test() {
  assert parsed("") == settings.empty
  assert parsed("# only a comment\n[palette]\n") == settings.empty
  assert settings.to_css(settings.empty, "/") == ""
}

pub fn unknown_and_misspelt_keys_are_refused_test() {
  assert refused("[fonts.text]\nfamily = \"x\"\n")
    == "junkslides.toml: fonts is not a setting."
  assert refused("[font.text]\nfamly = \"x\"\n")
    == "junkslides.toml: font.text.famly is not a setting."
  assert refused("[palette]\nlink = \"red\"\n")
    == "junkslides.toml: palette.link is not a setting."
}

pub fn wrong_values_name_their_key_test() {
  assert string.contains(
    refused("[font.text]\nregular = \"a.woff2\"\n"),
    "font.text needs a family",
  )
  assert string.contains(refused("[type]\nsize = \"big\"\n"), "type.size")
  assert string.contains(refused("[type]\nsize = 2\n"), "from 8 to 400")
  assert string.contains(
    refused("[slide]\nnumbers = \"1/12\"\n"),
    "slide.numbers",
  )
  assert string.contains(refused("[slide]\nmargin = 9\n"), "slide.margin")
  assert string.contains(refused("[slide]\nmargin = [2, 16]\n"), "slide.margin")
  assert string.contains(refused("palette = 3\n"), "palette should be a table")
  assert string.contains(refused("[palette\n"), "does not read")
  assert string.contains(refused("[type]\nsize = 1\nsize = 2\n"), "twice")
}

pub fn values_cannot_leave_their_declaration_test() {
  assert string.contains(
    refused("[palette]\ntext = \"red; } body { display: none\"\n"),
    "palette.text",
  )
  assert string.contains(
    refused("[font.text]\nfamily = 'x\"; } *{color:red} '\n"),
    "font.text.family",
  )
  assert string.contains(
    refused("[font.text]\nfamily = \"x\"\nfallback = '\"x, serif'\n"),
    "font.text.fallback",
  )
  assert string.contains(
    refused("[font.text]\nfamily = \"x; } * { color: red\"\n"),
    "font.text.family",
  )
  assert string.contains(
    refused(
      "[font.text]\nfamily = \"x\"\nfallback = \"serif; } * { color: red }\"\n",
    ),
    "font.text.fallback",
  )
  assert string.contains(
    refused("[palette]\nbackground = \"url(x)</style>\"\n"),
    "palette.background",
  )
}

pub fn font_files_stay_inside_the_deck_test() {
  let file = fn(path) {
    settings.parse(
      "[font.code]\nfamily = \"x\"\nregular = \"" <> path <> "\"\n",
    )
  }
  assert {
    let assert Ok(_) = file("fonts/x.woff2")
    True
  }
  let refused = fn(path) {
    case file(path) {
      Error(message) -> string.contains(message, "font.code.regular")
      Ok(_) -> False
    }
  }
  assert refused("/fonts/x.woff2")
  assert refused("../x.woff2")
  assert refused("fonts/../../x.woff2")
  assert refused(".hidden/x.woff2")
  assert refused("https://example.com/x.woff2")
  assert refused("fonts//x.woff2")
  assert refused("fonts/x%2e.woff2")
}

pub fn css_has_faces_properties_and_rules_test() {
  let css = settings.to_css(parsed(full), "/")
  assert string.contains(
    css,
    "  font-family: \"et-book\";\n  src: url(\"/fonts/et-book-roman.woff2\") format(\"woff2\");\n  font-weight: normal;\n  font-style: normal;",
  )
  assert string.contains(
    css,
    "src: url(\"/fonts/et-book-bold-italic.ttf\") format(\"truetype\");\n  font-weight: bold;\n  font-style: italic;",
  )
  assert string.contains(
    css,
    "--js-font-text: \"et-book\", \"Palatino Linotype\", Georgia, serif;",
  )
  assert string.contains(css, "--js-font-code: \"Menlo\";")
  assert string.contains(css, "--js-size: 32px;")
  assert string.contains(css, "--js-line-height: 1.4;")
  assert string.contains(css, "--js-code-scale: 0.875;")
  assert string.contains(css, "--js-accent: black;")
  assert string.contains(css, "background: var(--js-background);")
  assert string.contains(css, "grid-area: 3 / 4 / 17 / 30;")
  assert string.contains(css, "gap: 24px;")
  assert string.contains(css, ":where(.js-page-total) {\n  display: none;")
  // Spaced numbers put a space each side of the slash.
  let assert Ok(spaced) = settings.parse("[slide]\nnumbers = \"01 / 12\"\n")
  assert string.contains(
    settings.to_css(spaced, ""),
    ":where(.js-page-slash)::before, :where(.js-page-slash)::after {\n  content: \" \";\n  white-space: pre;",
  )
  // Every rule has zero specificity, so the theme wins.
  assert string.split(css, "\n")
    |> list.filter(string.ends_with(_, " {"))
    |> list.all(fn(line) {
      string.starts_with(line, ":where(")
      || line == ":root {"
      || line == "@font-face {"
    })
}

pub fn css_has_only_what_is_set_test() {
  let css = settings.to_css(parsed("[palette]\nquiet = \"#888\"\n"), "/")
  assert string.contains(css, "--js-quiet: #888;")
  assert string.contains(css, "color: var(--js-quiet);")
  assert !string.contains(css, "@font-face")
  assert !string.contains(css, "js-background")
  assert !string.contains(css, "grid-area")
  assert !string.contains(css, "display")
}

pub fn numbers_can_be_hidden_test() {
  let css = settings.to_css(parsed("[slide]\nnumbers = \"none\"\n"), "/")
  assert string.contains(css, ":where(.js-page) {\n  display: none;")
  assert !string.contains(
    settings.to_css(parsed("[slide]\nnumbers = \"01/12\"\n"), "/"),
    "display",
  )
}

pub fn exports_use_paths_beside_the_page_test() {
  let css = settings.to_css(parsed(full), "")
  assert string.contains(css, "url(\"fonts/et-book-roman.woff2\")")
  assert !string.contains(css, "url(\"/")
}
