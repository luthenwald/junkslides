import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import zeno/protocol.{CodeBlock, Token}
import zeno_client/slide

fn render(source: String) -> String {
  render_with(source, dict.new())
}

fn render_with(source: String, highlights: slide.Highlights) -> String {
  slide.body(source, highlights) |> list.map(element.to_string) |> string.concat
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
