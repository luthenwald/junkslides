import gleam/list
import gleam/option.{None, Some}
import zeno/dialect.{
  AttributesUsed, BulletSpelling, DivUsed, ExtraUsed, FootnoteUsed, MathUsed,
  OrdinalSpelling, RawBlockUsed, ReferenceDefinitionUsed, ReferenceLinkUsed,
  SpanUsed, ThematicBreakUsed,
}

pub fn allowed_test() {
  let allowed = [
    "Plain paragraph.", "# One", "###### Six", "- a\n- b", "1. one\n2. two",
    "- a\n\n  - nested", "```gleam\nlet x = {1}\n```", "> quote",
    "![alt](assets/x.png)", "_em_ and *strong* and `co{de}`",
    "[link](https://example.com)", "Escapes: \\_x\\_", "hard\\\nbreak",
    "a set {1, 2}",
  ]
  assert list_problems(allowed) == []
}

fn list_problems(sources) {
  list.flat_map(sources, dialect.problems)
}

pub fn forbidden_test() {
  let cases = [
    #("***", ThematicBreakUsed),
    #("```=html\n<b>x</b>\n```", RawBlockUsed),
    #(":::\nx\n:::", DivUsed),
    #("[x]{.big}", SpanUsed),
    #("{.big}\nPara", AttributesUsed),
    #("_x_{.big}", AttributesUsed),
    #("{=mark=}", AttributesUsed),
    #("[x][ref]\n\n[ref]: https://example.com", ReferenceLinkUsed),
    #("[ref]: https://example.com", ReferenceDefinitionUsed),
    #("a[^1]\n\n[^1]: note", FootnoteUsed),
    #("$`x^2`", MathUsed),
    #("x^2^", ExtraUsed),
    #("H~2~O", ExtraUsed),
    #("a {+ins+}", ExtraUsed),
    #(":smile:", ExtraUsed),
    #("* star", BulletSpelling),
    #("1) one", OrdinalSpelling),
    #("3. three", OrdinalSpelling),
  ]
  list.each(cases, fn(c) {
    let #(source, problem) = c
    assert list.contains(dialect.problems(source), problem)
  })
}

pub fn safe_url_test() {
  assert dialect.safe_url("assets/a.png") == Some("assets/a.png")
  assert dialect.safe_url("https://x.org/a:b") == Some("https://x.org/a:b")
  assert dialect.safe_url("mailto:me@x.org") == Some("mailto:me@x.org")
  assert dialect.safe_url("./a:b") == Some("./a:b")
  assert dialect.safe_url("javascript:alert(1)") == None
  assert dialect.safe_url(" JavaScript:alert(1)") == None
  assert dialect.safe_url("data:text/html,x") == None
}
