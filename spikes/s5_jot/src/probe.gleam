//// Prints jot's AST and HTML for every corpus case.

import corpus
import gleam/dict
import gleam/io
import gleam/list
import gleam/string
import jot

pub fn main() -> Nil {
  use case_ <- list.each(corpus.cases())
  let doc = jot.parse(case_.source)
  io.println("== " <> case_.name)
  io.println("ast   " <> string.inspect(doc.content))
  case dict.size(doc.references), dict.size(doc.footnotes) {
    0, 0 -> Nil
    r, f ->
      io.println(
        "refs  " <> string.inspect(r) <> " footnotes " <> string.inspect(f),
      )
  }
  io.println("html  " <> string.inspect(jot.document_to_html(doc)))
}
