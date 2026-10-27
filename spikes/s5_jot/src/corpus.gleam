//// The S5 corpus: one small cell body per construct of the dialect.

pub type Case {
  Case(name: String, source: String, allowed: Bool)
}

pub fn cases() -> List(Case) {
  [
    // Allowed blocks
    Case("paragraph", "A lens is a pair\nof functions.", True),
    Case("heading 1", "# Why lenses", True),
    Case("heading 6", "###### Small", True),
    Case("bullet list", "- one\n- two", True),
    Case("ordered list", "1. one\n2. two", True),
    Case("nested list", "- one\n\n  - inner\n\n- two", True),
    Case("code fence", "```\nlet x = 1\n```", True),
    Case("code fence lang", "```gleam\nlet x = 1\n```", True),
    Case("block quote", "> quoted\n> text", True),
    Case("image line", "![A lens](assets/lens.png)", True),
    Case("two blocks", "# Title\n\nBody text.", True),
    // Allowed inlines
    Case("emphasis", "_get_ and _put_", True),
    Case("strong", "*strong*", True),
    Case("inline code", "use `jot` here", True),
    Case("link", "[Gleam](https://gleam.run)", True),
    Case("inline image", "see ![x](assets/x.png) here", True),
    Case("escape", "not \\_emph\\_", True),
    Case("hard break", "line one\\\nline two", True),
    // Forbidden
    Case("thematic break dashes", "a\n\n---\n\nb", False),
    Case("thematic break stars", "a\n\n***\n\nb", False),
    Case("thematic break spaced", "a\n\n* * *\n\nb", False),
    Case("raw html inline", "a <b>bold</b> word", False),
    Case("raw block", "``` =html\n<div>x</div>\n```", False),
    Case("raw inline", "a `<b>`{=html} b", False),
    Case("reference link", "[text][ref]\n\n[ref]: https://x.org", False),
    Case("reference definition only", "[ref]: https://x.org", False),
    Case("footnote", "text[^1]\n\n[^1]: note", False),
    Case("block attribute", "{.big}\nparagraph", False),
    Case("inline attribute", "_word_{.big}", False),
    Case("div", "::: warning\ntext\n:::", False),
    Case("table", "| a | b |\n|---|---|\n| 1 | 2 |", False),
    Case("definition list", ": term\n\n  definition", False),
    Case("math", "$`x^2`", False),
    Case("display math", "$$`x^2`", False),
    Case("span", "[word]{.big}", False),
    Case("mark", "{=marked=}", False),
    Case("setext heading", "Title\n=====", False),
    Case("star bullet", "* one\n* two", False),
    Case("paren ordinal", "1) one\n2) two", False),
  ]
}
