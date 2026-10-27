import blocks
import check
import corpus
import gleam/list
import gleeunit
import jot

pub fn main() -> Nil {
  gleeunit.main()
}

/// Each case is flagged exactly when the dialect forbids it, except the
/// constructs jot drops or reads as plain text (listed in the S5 note).
pub fn classification_test() {
  let unseen = [
    "raw html inline", "raw inline", "inline attribute", "table",
    "definition list", "mark", "setext heading",
  ]
  let wrong =
    corpus.cases()
    |> list.filter(fn(c) { !list.contains(unseen, c.name) })
    |> list.filter(fn(c) {
      { check.problems(jot.parse(c.source)) == [] } != c.allowed
    })
    |> list.map(fn(c) { c.name })
  assert wrong == []
}

/// The splitter agrees with jot: every chunk is one top-level block, and
/// the chunks together have as many blocks as the whole text.
pub fn split_matches_jot_test() {
  let sources = [
    "# H\n\npara\n\n- a\n- b\n\n- c\n\n```\nx\n\ny\n```\n\n> q",
    "- a\n\n  more\n\n- b\n\n1. c\n\n2. d\n\ntext",
    "- a\n\n  - inner\n\n- b\n\n![img](a.png)",
    "> a\n\n> b\n\n````\n```\n\n````\n\n* s\n\n- d",
    "- a\n\n  ```\n  x\n\n  y\n  ```\n\npara\nlazy",
  ]
  let mismatched =
    list.filter(sources, fn(source) {
      let chunks = blocks.split(source)
      let each_one =
        list.all(chunks, fn(chunk) {
          list.length(jot.parse(chunk).content) == 1
        })
      !each_one || list.length(chunks) != list.length(jot.parse(source).content)
    })
  assert mismatched == []
}

pub fn split_keeps_text_test() {
  assert blocks.split("a\n\n\n\nb") == ["a", "b"]
  assert blocks.split("```\na\n\nb\n```") == ["```\na\n\nb\n```"]
  assert blocks.split("x\n\n- a\n\n- b") == ["x", "- a\n\n- b"]
}
