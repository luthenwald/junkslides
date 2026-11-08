//// The deck's settings in junkslides.toml (02-file-format.md, Settings; D27): its
//// fonts, palette, type scale and slide furniture. The file is written by hand
//// and only read here. It becomes a stylesheet that sits between the base
//// styles and theme.css (04-layout.md, Stylesheets), so the theme still wins.
////
//// Pure: the caller reads the file, and checks that the font files exist.

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import junkslides_server/shade
import tom.{type Toml}

pub type Settings {
  Settings(
    text_font: Option(Font),
    code_font: Option(Font),
    background: Option(String),
    text: Option(String),
    quiet: Option(String),
    accent: Option(String),
    size: Option(Float),
    line_height: Option(Float),
    code_scale: Option(Float),
    numbers: Option(Numbers),
    /// The body area's inset in rows and columns of the theme grid.
    margin: Option(#(Int, Int)),
    gap: Option(Float),
    /// Keywords for code without a tree-sitter grammar (D30).
    keywords: Option(List(String)),
    /// The markers that start a comment, for the same code.
    comments: Option(List(String)),
    /// Languages shaded by the simple rules even with a grammar.
    simple: Option(List(String)),
  )
}

/// A family by name, and the files of its faces, relative to the deck. A
/// family without files is one the system has.
pub type Font {
  Font(family: String, fallback: Option(String), faces: List(#(Face, String)))
}

pub type Face {
  Regular
  Italic
  Bold
  BoldItalic
}

/// How slide numbers show: `01/12`, `01 / 12`, `01`, or not at all.
pub type Numbers {
  Full
  Spaced
  Short
  Hidden
}

/// No settings: the stylesheet is empty and the slide looks as it would
/// without junkslides.toml.
pub const empty =
  Settings(
    text_font: None,
    code_font: None,
    background: None,
    text: None,
    quiet: None,
    accent: None,
    size: None,
    line_height: None,
    code_scale: None,
    numbers: None,
    margin: None,
    gap: None,
    keywords: None,
    comments: None,
    simple: None,
  )

/// The faces in the order of their keys in a font table.
const faces = [
  #("regular", Regular),
  #("italic", Italic),
  #("bold", Bold),
  #("bold-italic", BoldItalic),
]

/// The junkslides.toml `junkslides init` writes, kept equal to examples/talk/junkslides.toml
/// (checked by a test): the look the default theme had before D27, with the
/// default fonts from the deck's `fonts/`.
pub const default_toml =
  "# Settings for this deck. theme.css comes after them and can change anything.

[font.text]
family = \"et-book\"
fallback = 'Palatino, \"Palatino Linotype\", \"Book Antiqua\", Georgia, serif'
regular = \"fonts/et-book-roman.woff2\"
italic = \"fonts/et-book-italic.woff2\"
bold = \"fonts/et-book-bold.woff2\"

[font.code]
family = \"Victor Mono\"
fallback = \"ui-monospace, Menlo, Consolas, monospace\"
regular = \"fonts/victor-mono-regular.woff2\"
italic = \"fonts/victor-mono-italic.woff2\"
bold = \"fonts/victor-mono-bold.woff2\"

[palette]
background = \"#fafafa\"
text = \"#222\"
quiet = \"#777\"   # slide numbers and the quiet variant
accent = \"#222\"  # for themes, as var(--js-accent)

[type]
size = 32        # pixels on a 1920 by 1080 slide
line-height = 1.4
code-scale = 1   # code size against its text, such as 0.875

[slide]
numbers = \"01/12\"  # or \"01 / 12\", \"01\", or \"none\"
margin = 2         # body inset in 60 px grid units, or [rows, columns]
gap = 24           # pixels between cells that flow
"

// Reading ---------------------------------------------------------------------

/// The settings in a junkslides.toml, or a message for the user naming the key at
/// fault. Unknown keys are refused, so that a misspelt one is not silently
/// ignored.
pub fn parse(source: String) -> Result(Settings, String) {
  use document <- result.try(
    tom.parse(source) |> result.map_error(syntax_message),
  )
  use top <- result.try(
    keys(document, "", ["font", "palette", "type", "slide", "code"]),
  )
  use font <- result.try(section(top, "font", ["text", "code"]))
  use palette <- result.try(
    section(top, "palette", ["background", "text", "quiet", "accent"]),
  )
  use type_ <- result.try(
    section(top, "type", ["size", "line-height", "code-scale"]),
  )
  use slide <- result.try(section(top, "slide", ["numbers", "margin", "gap"]))
  use code <- result.try(
    section(top, "code", ["keywords", "comments", "simple"]),
  )

  use text_font <- result.try(field(font, "font", "text", read_font))
  use code_font <- result.try(field(font, "font", "code", read_font))
  use background <- result.try(field(palette, "palette", "background", colour))
  use text <- result.try(field(palette, "palette", "text", colour))
  use quiet <- result.try(field(palette, "palette", "quiet", colour))
  use accent <- result.try(field(palette, "palette", "accent", colour))
  use size <- result.try(field(type_, "type", "size", number(8.0, 400.0)))
  use line_height <- result.try(field(
    type_,
    "type",
    "line-height",
    number(0.5, 4.0),
  ))
  use code_scale <- result.try(field(
    type_,
    "type",
    "code-scale",
    number(0.25, 4.0),
  ))
  use numbers <- result.try(field(slide, "slide", "numbers", read_numbers))
  use margin <- result.try(field(slide, "slide", "margin", read_margin))
  use gap <- result.try(field(slide, "slide", "gap", number(0.0, 1080.0)))
  use keywords <- result.try(field(code, "code", "keywords", read_keywords))
  use comments <- result.try(field(code, "code", "comments", read_comments))
  use simple <- result.try(field(code, "code", "simple", read_languages))
  Ok(Settings(
    text_font:,
    code_font:,
    background:,
    text:,
    quiet:,
    accent:,
    size:,
    line_height:,
    code_scale:,
    numbers:,
    margin:,
    gap:,
    keywords:,
    comments:,
    simple:,
  ))
}

/// The rules of the simple shading (D30): the settings' own, or the
/// defaults for what they leave out.
pub fn shading(settings: Option(Settings)) -> shade.Rules {
  let pick = fn(get, default) {
    option.then(settings, get) |> option.unwrap(default)
  }
  shade.Rules(
    keywords: pick(fn(s: Settings) { s.keywords }, shade.default_keywords),
    comments: pick(fn(s: Settings) { s.comments }, shade.default_comments),
    simple: pick(fn(s: Settings) { s.simple }, []),
  )
}

/// A list of comment markers, each a few characters without spaces.
fn read_comments(value: Toml, path: String) -> Result(List(String), String) {
  strings(value, path, "comment markers without spaces", fn(text) {
    text != ""
    && string.length(text) <= 4
    && !list.any(string.to_graphemes(text), fn(g) { string.trim(g) == "" })
  })
}

/// A list of language names, as fences write them.
fn read_languages(value: Toml, path: String) -> Result(List(String), String) {
  strings(value, path, "language names", fn(text) {
    text != ""
    && list.all(string.to_graphemes(text), fn(g) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-+#.",
        g,
      )
    })
  })
}

fn strings(
  value: Toml,
  path: String,
  what: String,
  ok: fn(String) -> Bool,
) -> Result(List(String), String) {
  let message =
    "junkslides.toml: "
    <> path
    <> " should be a list of "
    <> what
    <> " in quotes."
  case value {
    tom.Array(items) ->
      list.try_map(items, fn(item) {
        case item {
          tom.String(text) ->
            case ok(text) {
              True -> Ok(text)
              False -> Error(message)
            }
          _ -> Error(message)
        }
      })
    _ -> Error(message)
  }
}

/// A list of words, each of letters, digits, `_` and `'`.
fn read_keywords(value: Toml, path: String) -> Result(List(String), String) {
  let message =
    "junkslides.toml: " <> path <> " should be a list of words in quotes."
  let word = fn(text) {
    text != ""
    && list.all(string.to_graphemes(text), fn(g) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'",
        g,
      )
    })
  }
  case value {
    tom.Array(items) ->
      list.try_map(items, fn(item) {
        case item {
          tom.String(text) ->
            case word(text) {
              True -> Ok(text)
              False -> Error(message)
            }
          _ -> Error(message)
        }
      })
    _ -> Error(message)
  }
}

fn syntax_message(error: tom.ParseError) -> String {
  case error {
    tom.Unexpected(got:, expected:) ->
      "junkslides.toml does not read: expected "
      <> expected
      <> ", found "
      <> string.inspect(got)
      <> "."
    tom.KeyAlreadyInUse(key:) ->
      "junkslides.toml sets " <> string.join(key, ".") <> " twice."
  }
}

/// The table, if every key in it is one of `allowed`.
fn keys(
  table: Dict(String, Toml),
  path: String,
  allowed: List(String),
) -> Result(Dict(String, Toml), String) {
  case list.find(dict.keys(table), fn(key) { !list.contains(allowed, key) }) {
    Ok(key) ->
      Error("junkslides.toml: " <> join(path, key) <> " is not a setting.")
    Error(Nil) -> Ok(table)
  }
}

/// A table at the top level; an absent one is empty.
fn section(
  top: Dict(String, Toml),
  name: String,
  allowed: List(String),
) -> Result(Dict(String, Toml), String) {
  case dict.get(top, name) {
    Error(Nil) -> Ok(dict.new())
    Ok(value) -> as_table(value, name) |> result.try(keys(_, name, allowed))
  }
}

fn as_table(value: Toml, path: String) -> Result(Dict(String, Toml), String) {
  case value {
    tom.Table(table) | tom.InlineTable(table) -> Ok(table)
    _ -> Error("junkslides.toml: " <> path <> " should be a table.")
  }
}

/// A value read with `read` from its full key, if the table has it.
fn field(
  table: Dict(String, Toml),
  path: String,
  key: String,
  read: fn(Toml, String) -> Result(a, String),
) -> Result(Option(a), String) {
  case dict.get(table, key) {
    Error(Nil) -> Ok(None)
    Ok(value) -> read(value, join(path, key)) |> result.map(Some)
  }
}

fn join(path: String, key: String) -> String {
  case path {
    "" -> key
    _ -> path <> "." <> key
  }
}

fn read_font(value: Toml, path: String) -> Result(Font, String) {
  use table <- result.try(as_table(value, path))
  use table <- result.try(
    keys(table, path, ["family", "fallback", ..list.map(faces, fn(f) { f.0 })]),
  )
  use family <- result.try(case field(table, path, "family", family) {
    Ok(Some(family)) -> Ok(family)
    Ok(None) -> Error("junkslides.toml: " <> path <> " needs a family.")
    Error(message) -> Error(message)
  })
  use fallback <- result.try(field(table, path, "fallback", fallback))
  use files <- result.try(
    list.try_map(faces, fn(face) {
      field(table, path, face.0, file)
      |> result.map(option.map(_, fn(file) { #(face.1, file) }))
    }),
  )
  Ok(Font(family:, fallback:, faces: option.values(files)))
}

fn text(value: Toml, path: String) -> Result(String, String) {
  case value {
    tom.String(text) -> Ok(text)
    _ -> Error("junkslides.toml: " <> path <> " should be text in quotes.")
  }
}

/// Characters that could end a declaration, a rule or the stylesheet's own
/// string, so a value cannot reach past its place in the CSS.
fn breaks_out(value: String) -> Bool {
  list.any(
    [";", "{", "}", "<", ">", "\\", "\n", "\r", "\u{0}"],
    string.contains(value, _),
  )
}

fn family(value: Toml, path: String) -> Result(String, String) {
  use name <- result.try(text(value, path))
  case
    string.trim(name) == "" || breaks_out(name) || string.contains(name, "\"")
  {
    True -> Error("junkslides.toml: " <> path <> " is not a font family name.")
    False -> Ok(string.trim(name))
  }
}

/// A list of families as CSS writes it, such as `"Gill Sans", sans-serif`.
fn fallback(value: Toml, path: String) -> Result(String, String) {
  use list_ <- result.try(text(value, path))
  let balanced = fn(quote) {
    int.is_even(list.length(string.split(list_, quote)) - 1)
  }
  case breaks_out(list_) || !balanced("\"") || !balanced("'") {
    True ->
      Error("junkslides.toml: " <> path <> " is not a list of font families.")
    False -> Ok(string.trim(list_))
  }
}

/// A colour as CSS writes it: `#222`, `white`, `rgb(20 20 20 / 50%)`.
fn colour(value: Toml, path: String) -> Result(String, String) {
  use colour <- result.try(text(value, path))
  let allowed = fn(grapheme) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#(),.%-/ ",
      grapheme,
    )
  }
  case
    string.trim(colour) != "" && list.all(string.to_graphemes(colour), allowed)
  {
    True -> Ok(string.trim(colour))
    False ->
      Error(
        "junkslides.toml: " <> path <> " should be a colour such as \"#222\".",
      )
  }
}

/// A path inside the deck: relative, without hidden or empty segments, and
/// without characters that a URL or the stylesheet would read differently.
fn file(value: Toml, path: String) -> Result(String, String) {
  use file <- result.try(text(value, path))
  let file = case file {
    "./" <> rest -> rest
    file -> file
  }
  let segment_ok = fn(segment) {
    segment != "" && !string.starts_with(segment, ".")
  }
  let ok =
    !breaks_out(file)
    && !list.any(["\"", "%", "?", "#", ":"], string.contains(file, _))
    && list.all(string.split(file, "/"), segment_ok)
  case ok {
    True -> Ok(file)
    False ->
      Error(
        "junkslides.toml: "
        <> path
        <> " should be a path inside the deck, such as \"fonts/serif.woff2\".",
      )
  }
}

fn number(
  low: Float,
  high: Float,
) -> fn(Toml, String) -> Result(Float, String) {
  fn(value, path) { in_range(value, path, low, high) }
}

fn in_range(
  value: Toml,
  path: String,
  low: Float,
  high: Float,
) -> Result(Float, String) {
  let value = case value {
    tom.Int(n) -> Ok(int.to_float(n))
    // tom reads 0.875 as 0.8750000000000001; four places are plenty.
    tom.Float(x) -> Ok(float.to_precision(x, 4))
    _ -> Error(Nil)
  }
  case value {
    Ok(x) if x >=. low && x <=. high -> Ok(x)
    _ ->
      Error(
        "junkslides.toml: "
        <> path
        <> " should be a number from "
        <> number_text(low)
        <> " to "
        <> number_text(high)
        <> ".",
      )
  }
}

fn read_numbers(value: Toml, path: String) -> Result(Numbers, String) {
  case value {
    tom.String("01/12") -> Ok(Full)
    tom.String("01 / 12") -> Ok(Spaced)
    tom.String("01") -> Ok(Short)
    tom.String("none") -> Ok(Hidden)
    _ ->
      Error(
        "junkslides.toml: "
        <> path
        <> " should be \"01/12\", \"01 / 12\", \"01\" or \"none\".",
      )
  }
}

/// One inset for both, or `[rows, columns]`. At least two rows and two
/// columns stay inside.
fn read_margin(value: Toml, path: String) -> Result(#(Int, Int), String) {
  let fits = fn(rows, columns) {
    rows >= 0 && rows <= 8 && columns >= 0 && columns <= 15
  }
  case value {
    tom.Int(n) if n >= 0 && n <= 8 -> Ok(#(n, n))
    tom.Array([tom.Int(rows), tom.Int(columns)]) ->
      case fits(rows, columns) {
        True -> Ok(#(rows, columns))
        False -> Error(margin_message(path))
      }
    _ -> Error(margin_message(path))
  }
}

fn margin_message(path: String) -> String {
  "junkslides.toml: "
  <> path
  <> " should be a whole number of grid units from 0 to 8, or [rows, columns]"
  <> " with columns up to 15."
}

/// The deck's own files the settings name, each once.
pub fn files(settings: Settings) -> List(String) {
  [settings.text_font, settings.code_font]
  |> option.values
  |> list.flat_map(fn(font) { list.map(font.faces, fn(face) { face.1 }) })
  |> list.unique
}

// Writing ---------------------------------------------------------------------

/// The stylesheet: `@font-face` rules for the font files, custom properties on
/// `:root` that a theme may use, and zero-specificity rules that apply them.
/// Only keys that are set appear. `prefix` goes before each file's path: `/`
/// in the editor, where the sheet is served from `/.js/`, and nothing in an
/// export, where it sits beside the page.
pub fn to_css(settings: Settings, prefix: String) -> String {
  let fonts =
    [settings.text_font, settings.code_font]
    |> option.values
    |> list.flat_map(font_faces(_, prefix))
  let properties =
    [
      #("--js-font-text", option.map(settings.text_font, font_list)),
      #("--js-font-code", option.map(settings.code_font, font_list)),
      #("--js-background", settings.background),
      #("--js-text", settings.text),
      #("--js-quiet", settings.quiet),
      #("--js-accent", settings.accent),
      #("--js-size", option.map(settings.size, px)),
      #("--js-line-height", option.map(settings.line_height, number_text)),
      #("--js-code-scale", option.map(settings.code_scale, number_text)),
    ]
    |> declarations
  let set = fn(value: Option(a), declaration: String) {
    option.map(value, fn(_) { declaration })
  }
  let rules =
    [
      rule(":where(.js-slide)", [
        set(settings.background, "background: var(--js-background);"),
        set(settings.text, "color: var(--js-text);"),
        set(settings.text_font, "font-family: var(--js-font-text);"),
        set(settings.size, "font-size: var(--js-size);"),
        set(settings.line_height, "line-height: var(--js-line-height);"),
      ]),
      rule(":where(.js-slide pre, .js-slide code)", [
        set(settings.code_font, "font-family: var(--js-font-code);"),
      ]),
      // Code inside `pre` is scaled once, by its `pre`.
      rule(":where(.js-slide pre, .js-slide :not(pre) > code)", [
        set(settings.code_scale, "font-size: calc(var(--js-code-scale) * 1em);"),
      ]),
      rule(":where(.js-cell[data-variant=\"quiet\"], .js-page)", [
        set(settings.quiet, "color: var(--js-quiet);"),
      ]),
      rule(":where(.js-body)", [
        option.map(settings.margin, body_area),
        option.map(settings.gap, fn(gap) { "gap: " <> px(gap) <> ";" }),
      ]),
      case settings.numbers {
        Some(Short) -> rule(":where(.js-page-total)", [Some("display: none;")])
        Some(Hidden) -> rule(":where(.js-page)", [Some("display: none;")])
        Some(Spaced) ->
          rule(":where(.js-page-slash)::before, :where(.js-page-slash)::after", [
            Some("content: \" \";"),
            Some("white-space: pre;"),
          ])
        Some(Full) | None -> None
      },
    ]
    |> option.values
  let root = case properties {
    [] -> []
    _ -> [":root {\n" <> string.join(properties, "\n") <> "\n}"]
  }
  case list.flatten([fonts, root, rules]) {
    [] -> ""
    blocks ->
      "/* From junkslides.toml. theme.css comes after this and wins. */\n\n"
      <> string.join(blocks, "\n\n")
      <> "\n"
  }
}

fn font_faces(font: Font, prefix: String) -> List(String) {
  list.map(font.faces, fn(face) {
    let #(weight, style) = case face.0 {
      Regular -> #("normal", "normal")
      Italic -> #("normal", "italic")
      Bold -> #("bold", "normal")
      BoldItalic -> #("bold", "italic")
    }
    let source = "url(\"" <> prefix <> face.1 <> "\")" <> format(face.1)
    "@font-face {\n"
    <> string.join(
      [
        "  font-family: \"" <> font.family <> "\";",
        "  src: " <> source <> ";",
        "  font-weight: " <> weight <> ";",
        "  font-style: " <> style <> ";",
        "  font-display: swap;",
      ],
      "\n",
    )
    <> "\n}"
  })
}

/// The `format()` hint for a font file, from its extension.
fn format(file: String) -> String {
  let extension = case list.last(string.split(string.lowercase(file), ".")) {
    Ok(extension) -> extension
    Error(Nil) -> ""
  }
  case extension {
    "woff2" -> " format(\"woff2\")"
    "woff" -> " format(\"woff\")"
    "otf" -> " format(\"opentype\")"
    "ttf" -> " format(\"truetype\")"
    _ -> ""
  }
}

fn font_list(font: Font) -> String {
  let family = "\"" <> font.family <> "\""
  case font.fallback {
    Some(fallback) if fallback != "" -> family <> ", " <> fallback
    _ -> family
  }
}

fn declarations(pairs: List(#(String, Option(String)))) -> List(String) {
  list.filter_map(pairs, fn(pair) {
    option.to_result(pair.1, Nil)
    |> result.map(fn(value) { "  " <> pair.0 <> ": " <> value <> ";" })
  })
}

fn rule(
  selector: String,
  declarations: List(Option(String)),
) -> Option(String) {
  case option.values(declarations) {
    [] -> None
    present ->
      Some(
        selector
        <> " {\n"
        <> string.join(list.map(present, fn(d) { "  " <> d }), "\n")
        <> "\n}",
      )
  }
}

/// The body area for an inset, on the theme grid of 18 rows by 32 columns.
fn body_area(margin: #(Int, Int)) -> String {
  let #(rows, columns) = margin
  "grid-area: "
  <> string.join(
    list.map([rows + 1, columns + 1, 19 - rows, 33 - columns], int.to_string),
    " / ",
  )
  <> ";"
}

fn px(x: Float) -> String {
  number_text(x) <> "px"
}

/// Whole numbers without a decimal point.
fn number_text(x: Float) -> String {
  case float.floor(x) == x {
    True -> int.to_string(float.truncate(x))
    False -> float.to_string(x)
  }
}
