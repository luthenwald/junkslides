import gleam/io
import gleam/list
import gleam/string
import jot

pub fn main() -> Nil {
  use src <- list.each([
    "^sup^ ~sub~", "{-del-} {+ins+}", "{=mark=} after", "a :smile: b",
    "\"quotes\" -- and ... ", "- [ ] task\n- [x] done", "<https://gleam.run>",
    "```\nunclosed fence", "# Heading\nno blank line", "para\n# not heading",
    "- a\n- b\n\n1. c", "> quote\nlazy line", "  indented para",
    "![alt](a b.png)", "a\\\\b", "line  \nnext", "[link](javascript:alert(1))",
    "```=html\n<x>\n```", "a {.x} b", "{#id}\n# H", "x\n\n\n\ny",
  ])
  io.println("== " <> string.inspect(src))
  io.println("  " <> string.inspect(jot.parse(src).content))
  io.println("  " <> string.inspect(jot.to_html(src)))
}
