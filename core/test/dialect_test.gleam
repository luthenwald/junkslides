import gleam/list
import gleam/option.{None, Some}
import jot.{Text}
import zeno/dialect.{
  AlignCenter, AlignDefault, AlignEnd, AlignStart, AttributesUsed,
  BulletSpelling, DivUsed, ExtraUsed, FootnoteUsed, MathUsed, OrdinalSpelling,
  RawBlockUsed, ReferenceDefinitionUsed, ReferenceLinkUsed, SpanUsed, TableShape,
  ThematicBreakUsed,
}

pub fn allowed_test() {
  let allowed = [
    "Plain paragraph.", "# One", "###### Six", "- a\n- b", "1. one\n2. two",
    "- a\n\n  - nested", "```gleam\nlet x = {1}\n```", "> quote",
    "![alt](assets/x.png)", "_em_ and *strong* and `co{de}`",
    "[link](https://example.com)", "Escapes: \\_x\\_", "hard\\\nbreak",
    "a set {1, 2}", "| a | b |\n|---|---:|\n| 1 | 2 |",
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

pub fn continuation_indents_test() {
  // The heading's text starts after `# `, at column 2; its next lines start
  // at column 4, two further in.
  assert dialect.continuation_indents(
      "# ( forward symbolic \n    execution for bounded GCL \n    verification )",
    )
    == [[2, 2]]
  // Paragraphs count from their first line; less indented lines count 0.
  assert dialect.continuation_indents("one\n  two\nthree\n\n  four\n      five")
    == [[2, 0], [4]]
  // List items count from their text, and a marker starts a new item.
  assert dialect.continuation_indents(
      "- first\n    more\n- second\n  same\n\n  - nested\n      deep",
    )
    == [[2, 0, 2]]
  assert dialect.continuation_indents("1. one\n     two") == [[2]]
  // Quote markers belong to the margin.
  assert dialect.continuation_indents("> a\n>   b\n> c") == [[2, 0]]
  // A heading may repeat its hashes on the next line.
  assert dialect.continuation_indents("## a\n##   b") == [[2]]
  // Code fences have no continuations; a paragraph line starting with a
  // dash is text, not an item.
  assert dialect.continuation_indents("```\na\n  b\n```") == [[]]
  assert dialect.continuation_indents("a\n- b") == [[0]]
  assert dialect.continuation_indents("") == []
}

pub fn code_blocks_test() {
  assert dialect.code_blocks("text\n\n```hs\nmain\n```\n\n```\nplain\n```")
    == [#("hs", "main\n")]
  assert dialect.code_blocks("> ```c\n> x\n> ```\n\n- ```zig\n  y\n  ```")
    == [#("c", "x\n"), #("zig", "  y\n")]
  assert dialect.code_blocks("no code") == []
}

// Tables -----------------------------------------------------------------------

fn table_of(source: String) -> dialect.Table {
  let assert Some(table) = dialect.table(source)
  table
}

pub fn what_is_a_table_test() {
  assert dialect.table("| a | b |\n|---|---|\n| 1 | 2 |") != None
  // The header's separator is required.
  assert dialect.table("| a | b |") == None
  assert dialect.table("|x|") == None
  assert dialect.table("| a |\n| b |") == None
  assert dialect.table("|---|\n") == None
  assert dialect.table("a | b\n---|---") == None
  assert dialect.table("| a |\n|-x-|") == None
  assert dialect.table("| a |\n||") == None
  // The header alone is enough.
  assert table_of("| a |\n|---|").rows == []
  // Leading and trailing spaces do not matter.
  assert table_of("  | a |  \n  |---|  ").regular
}

pub fn column_alignment_test() {
  assert table_of("| a | b | c | d |\n|---|:---|:--:|---:|").columns
    == [AlignDefault, AlignStart, AlignCenter, AlignEnd]
  assert table_of("| a |\n| - |").columns == [AlignDefault]
  assert table_of("| a |\n| :-: |").columns == [AlignCenter]
}

pub fn table_cells_are_inline_test() {
  assert table_of("| *a* | `b` |\n|---|---|").head
    == [[jot.Strong([Text("a")])], [jot.Code("b")]]
  // What would start a block at the start of a line is text here.
  assert table_of("| # a | - b | > c | 1. d |\n|---|---|---|---|").head
    == [[Text("# a")], [Text("- b")], [Text("> c")], [Text("1. d")]]
  // Marks do not pair across cells.
  assert table_of("| *a | b* |\n|---|---|").head == [[Text("*a")], [Text("b*")]]
  // Text around marks is kept whole.
  assert table_of("| x _y_ z |\n|---|").head
    == [[Text("x "), jot.Emphasis([Text("y")]), Text(" z")]]
  // Empty cells are empty.
  assert table_of("|  | a |\n|---|---|").head == [[], [Text("a")]]
}

pub fn pipes_in_table_cells_test() {
  // An escaped pipe is text.
  assert table_of("| a \\| b | c |\n|---|---|").head
    == [[Text("a | b")], [Text("c")]]
  // A pipe in inline code is text, for any length of backtick run.
  assert table_of("| `a|b` | ``c`|d`` |\n|---|---|").head
    == [[jot.Code("a|b")], [jot.Code("c`|d")]]
  // A backslash in code escapes nothing, so the pipe after it ends the cell.
  assert table_of("| `a\\` | b |\n|---|---|").head
    == [[jot.Code("a\\")], [Text("b")]]
  assert table_of("| `a\\` | b |\n|---|---|").regular
}

pub fn irregular_tables_are_padded_and_reported_test() {
  let shape = fn(source) { list.contains(dialect.problems(source), TableShape) }
  let width = fn(table: dialect.Table) { list.length(table.columns) }
  assert !shape("| a | b |\n|---|---|\n| 1 | 2 |")
  // A short row is padded.
  let short = "| a | b |\n|---|---|\n| 1 |"
  assert shape(short)
  assert table_of(short).rows == [[[Text("1")], []]]
  // A long row makes a column for all.
  let long = "| a |\n|---|\n| 1 | 2 |"
  assert shape(long)
  assert width(table_of(long)) == 2
  assert table_of(long).head == [[Text("a")], []]
  assert table_of(long).columns == [AlignDefault, AlignDefault]
  // A row being typed: no closing pipe yet, and no opening one.
  let open = "| a | b |\n|---|---|\n| 1 | 2"
  assert shape(open)
  assert table_of(open).rows == [[[Text("1")], [Text("2")]]]
  let bare = "| a | b |\n|---|---|\n1"
  assert shape(bare)
  assert table_of(bare).rows == [[[Text("1")], []]]
  // A line of a code span left open has no closing pipe.
  assert shape("| a | b |\n|---|---|\n| `1 | 2 |")
  // A header of another width than its separator.
  assert shape("| a |\n|---|---|")
  // A second separator is reported and drawn as text, in which jot reads
  // three dashes as a long dash, as it does in a paragraph.
  let second = "| a |\n|---|\n|---|"
  assert shape(second)
  assert table_of(second).rows == [[[Text("\u{2014}")]]]
}

pub fn forbidden_syntax_in_a_table_cell_is_reported_test() {
  let in_cell = fn(text) { "| a |\n|---|\n| " <> text <> " |" }
  assert dialect.problems(in_cell("*fine* `too`")) == []
  assert list.contains(dialect.problems(in_cell("x^2^")), ExtraUsed)
  assert list.contains(dialect.problems(in_cell("$`x`")), MathUsed)
  assert list.contains(dialect.problems(in_cell("[x][r]")), ReferenceLinkUsed)
  // Tables are only tables at the top level, and no problem elsewhere.
  assert dialect.problems("> | a |\n> |---|") == []
}

pub fn tables_among_other_blocks_test() {
  let source = "# ( one\n    two )\n\n| a |\n|---|\n\ntext\n  more\n\n|x|"
  let assert [
    dialect.Contained(jot.Heading(..), [2]),
    dialect.Tabular(_),
    dialect.Contained(jot.Paragraph(..), [2]),
    dialect.Contained(jot.Paragraph(..), []),
  ] = dialect.top_level(source)
  // In a quote or a list a table stays what jot reads.
  let assert [dialect.Contained(jot.BlockQuote(..), _)] =
    dialect.top_level("> | a |\n> |---|")
  let assert [dialect.Contained(jot.BulletList(..), _)] =
    dialect.top_level("- | a |\n  |---|")
}
