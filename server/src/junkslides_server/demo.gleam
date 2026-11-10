//// The opening state of the editor that runs without a server (the `demo`
//// package, published as a static site): a deck as the messages its owner
//// would greet a client with, written out as a Gleam module for that
//// package to compile in. The page has no way to read files, so everything
//// the server would read for it goes into the module.

import gleam/bit_array
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import junkslides/deck.{type Deck}
import junkslides/layout.{type Layout}
import junkslides/protocol
import junkslides_server/export
import junkslides_server/figures
import junkslides_server/highlighter
import junkslides_server/settings
import junkslides_server/theme

/// The source of `junkslides_demo/deck`: the greeting as protocol JSON, the
/// theme's mark classes for the diagnostics, and the simple shading's rules
/// for code typed later. A deck or settings that do not read stop it.
pub fn module(
  folder folder: String,
  deck deck: Deck,
  layout layout: Layout,
  tree_sitter tree_sitter: String,
) -> Result(String, String) {
  use settings <- result.try(export.read_settings(folder))
  use theme_bytes <- result.try(export.read_theme(folder))
  let css =
    theme_bytes
    |> option.map(bit_array.to_string)
    |> option.map(result.unwrap(_, ""))
    |> option.unwrap("")
  let marks = theme.marks(css)
  let rules = settings.shading(settings)
  let figure_files =
    protocol.figures(deck)
    |> list.map(fn(url) { #(url, figures.read(folder, url)) })
  let greeting = [
    protocol.State(
      version: 1,
      deck:,
      layout:,
      diagnostics: protocol.diagnostics(deck, marks),
      variants: theme.variants(css),
      view: protocol.default_view,
    ),
    protocol.Highlights(highlighter.highlight(
      tree_sitter,
      protocol.code_blocks(deck),
      rules,
    )),
    protocol.Figures(figures.usable(figure_files)),
  ]
  Ok(
    "//// Made by `junkslides demo-module`; not kept in version control.\n\n"
    <> constant("greeting", list.map(greeting, protocol.encode_server))
    <> constant("marks", marks)
    <> constant("keywords", rules.keywords)
    <> constant("comments", rules.comments)
    <> constant("simple", rules.simple),
  )
}

/// A public constant holding a list of strings.
fn constant(name: String, items: List(String)) -> String {
  "pub const "
  <> name
  <> ": List(String) = ["
  <> string.join(list.map(items, literal), ", ")
  <> "]\n\n"
}

/// A Gleam string literal of `text`.
fn literal(text: String) -> String {
  let escaped =
    text
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\n")
    |> string.replace("\r", "\\r")
    |> string.replace("\t", "\\t")
  "\"" <> escaped <> "\""
}
