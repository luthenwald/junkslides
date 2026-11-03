import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import zeno/protocol.{CodeBlock, Token}
import zeno/render

fn render(source: String) -> String {
  render_with(source, dict.new())
}

fn render_with(source: String, highlights: render.Highlights) -> String {
  render.body(source, highlights)
  |> list.map(element.to_string)
  |> string.concat
}

pub fn lines_and_indentation_are_kept_test() {
  assert render(
      "# ( forward symbolic \n    execution for bounded GCL \n    verification )",
    )
    == "<h1>( forward symbolic <br><span class=\"zeno-indent\">  </span>execution for bounded GCL <br><span class=\"zeno-indent\">  </span>verification )</h1>"
  // A paragraph's lines, emphasis across a break, and a hard break.
  assert render("one _two\n  three_\\\nfour")
    == "<p>one <em>two<br><span class=\"zeno-indent\">  </span>three</em><br>four</p>"
  // List items count from their text.
  assert render("- a\n    b\n- c")
    == "<ul><li>a<br><span class=\"zeno-indent\">  </span>b</li><li>c</li></ul>"
  // Code keeps its own lines.
  assert render("```hs\nmain =\n  pure ()\n```")
    == "<pre><code data-language=\"hs\">main =\n  pure ()\n</code></pre>"
}

pub fn code_is_drawn_with_the_tokens_it_has_test() {
  let source = "```hs\nmain\n```"
  let highlights =
    dict.from_list([
      #(CodeBlock("hs", "main\n"), [
        Token(Some("punctuation.bracket"), "main"),
        Token(None, "\n"),
      ]),
    ])
  assert render_with(source, highlights)
    == "<pre><code data-language=\"hs\"><span class=\"zeno-tok-punctuation zeno-tok-punctuation-bracket\">main</span>\n</code></pre>"
  // Other text, or another language, is drawn plain.
  assert render_with("```hs\nother\n```", highlights)
    == "<pre><code data-language=\"hs\">other\n</code></pre>"
  assert render_with("```c\nmain\n```", highlights)
    == "<pre><code data-language=\"c\">main\n</code></pre>"
}

pub fn tables_are_drawn_test() {
  assert render(
      "| a | *b* | c |\n|:--|:-:|--:|\n| 1 | `2` | 3 |\n| 4 | 5 | 6 |",
    )
    == "<table><thead><tr>"
    <> "<th data-align=\"start\" scope=\"col\">a</th>"
    <> "<th data-align=\"center\" scope=\"col\"><strong>b</strong></th>"
    <> "<th data-align=\"end\" scope=\"col\">c</th>"
    <> "</tr></thead><tbody><tr>"
    <> "<td data-align=\"start\">1</td>"
    <> "<td data-align=\"center\"><code>2</code></td>"
    <> "<td data-align=\"end\">3</td>"
    <> "</tr><tr>"
    <> "<td data-align=\"start\">4</td>"
    <> "<td data-align=\"center\">5</td>"
    <> "<td data-align=\"end\">6</td>"
    <> "</tr></tbody></table>"
}

pub fn a_table_without_alignment_or_rows_test() {
  assert render("| a |\n|---|")
    == "<table><thead><tr><th scope=\"col\">a</th></tr></thead><tbody></tbody></table>"
}

pub fn short_table_rows_are_padded_test() {
  assert render("| a | b |\n|---|---|\n| 1 |")
    == "<table><thead><tr><th scope=\"col\">a</th><th scope=\"col\">b</th></tr></thead>"
    <> "<tbody><tr><td>1</td><td></td></tr></tbody></table>"
}

pub fn table_cells_go_through_the_url_check_test() {
  let source =
    "| a |\n|---|\n| [x](javascript:alert) ![y](data:z) [k](https://e.org) |"
  let drawn = render(source)
  assert !string.contains(drawn, "javascript:")
  assert !string.contains(drawn, "data:")
  assert string.contains(drawn, "<a href=\"https://e.org\">k</a>")
}

pub fn tables_stay_among_other_blocks_with_their_lines_test() {
  assert render("# ( one\n    two )\n\n| a |\n|---|\n\ntext\n  more")
    == "<h1>( one<br><span class=\"zeno-indent\">  </span>two )</h1>"
    <> "<table><thead><tr><th scope=\"col\">a</th></tr></thead><tbody></tbody></table>"
    <> "<p>text<br><span class=\"zeno-indent\">  </span>more</p>"
}

pub fn marks_are_classes_test() {
  assert render("A [120]{.now} and [x]{.quiet .side}.")
    == "<p>A <span class=\"now\">120</span> and <span class=\"quiet side\">x</span>.</p>"
  // Nothing else of a span's attributes reaches the page.
  assert render("[x]{#id}") == "<p><span>x</span></p>"
}

pub fn code_attributes_light_lines_and_mark_text_test() {
  // A lit line, and a mark whose delimiters are left out.
  assert render("{lit=2 now=\"⟦⟧\"}\n```\na\nb ⟦c⟧ d\ne\n```")
    == "<pre><code>a\n<span class=\"zeno-lit\">b <span class=\"now\">c</span> d</span>\ne\n</code></pre>"
  // Ranges, and a mark that runs to the end of its line.
  assert render("{lit=\"1-2\" to=\"<>\"}\n```\nx <y\nz\n```")
    == "<pre><code><span class=\"zeno-lit\">x <span class=\"to\">y</span></span>\n<span class=\"zeno-lit\">z</span>\n</code></pre>"
}

pub fn marks_in_code_cut_tokens_test() {
  let source = "{now=\"⟦⟧\"}\n```hs\nab⟦cd⟧e\n```"
  // The server highlights the text without delimiters.
  let highlights =
    dict.from_list([
      #(CodeBlock("hs", "abcde\n"), [
        Token(Some("keyword"), "abc"),
        Token(None, "de"),
        Token(None, "\n"),
      ]),
    ])
  assert render_with(source, highlights)
    == "<pre><code data-language=\"hs\"><span class=\"zeno-tok-keyword\">ab</span><span class=\"now\"><span class=\"zeno-tok-keyword\">c</span>d</span>e\n</code></pre>"
  // Tokens of another text are not used.
  assert render_with("{now=\"⟦⟧\"}\n```hs\nab⟦cd⟧x\n```", highlights)
    == "<pre><code data-language=\"hs\">ab<span class=\"now\">cd</span>x\n</code></pre>"
}
