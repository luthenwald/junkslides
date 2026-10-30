import gleam/list
import gleam/string
import lustre/element
import zeno_client/slide

fn render(source: String) -> String {
  slide.body(source) |> list.map(element.to_string) |> string.concat
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
  // Code keeps its own lines, highlighted for its language.
  assert render("```hs\nmain =\n  pure ()\n```")
    == "<pre><code data-language=\"hs\">main <span class=\"zeno-tok-operator\">=</span>\n  pure <span class=\"zeno-tok-punctuation\">()</span>\n</code></pre>"
}
