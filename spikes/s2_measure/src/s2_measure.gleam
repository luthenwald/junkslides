//// S2: growing text areas and overflow detection with Lustre and CSS only.
////
//// Overflow reaches the model through CSS: a hidden probe with the same size
//// and content as the box is a scroll-state container, and a flag inside it
//// runs the animation `fits` or `overflows` depending on whether the probe
//// can scroll. Each change starts a new animation, and Lustre receives its
//// `animationstart` event.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// Lustre's textarea sets the value property from its content on every
// render, so the model's text is always passed back in (a controlled input).

pub fn main() -> Nil {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

type Model {
  Model(
    texts: Dict(String, String),
    lines: Int,
    /// Probe name to "fits" or "overflows", as last reported by CSS.
    probes: Dict(String, String),
  )
}

type Msg {
  Typed(id: String, text: String)
  More
  Less
  Probe(name: String, state: String)
}

fn init(_flags: Nil) -> Model {
  Model(dict.new(), 2, dict.new())
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Typed(id, text) -> Model(..model, texts: dict.insert(model.texts, id, text))
    More -> Model(..model, lines: model.lines + 1)
    Less -> Model(..model, lines: int.max(model.lines - 1, 0))
    Probe(name, state) ->
      Model(..model, probes: dict.insert(model.probes, name, state))
  }
}

fn view(model: Model) -> Element(Msg) {
  html.main([], [
    html.style([], css),
    html.h2([], [html.text("Text areas")]),
    html.div([attribute.class("areas")], [
      // 1. CSS field-sizing.
      html.textarea(
        [
          attribute.id("ta-field"),
          attribute.class("field"),
          event.on_input(Typed("field", _)),
        ],
        text(model, "field"),
      ),
      // 2. A hidden mirror sharing one grid cell with the text area.
      html.div(
        [
          attribute.class("grow"),
          attribute.data("value", text(model, "mirror")),
        ],
        [
          html.textarea(
            [attribute.id("ta-mirror"), event.on_input(Typed("mirror", _))],
            text(model, "mirror"),
          ),
        ],
      ),
      // 3. Rows from the line count; ignores wrapping.
      html.textarea(
        [
          attribute.id("ta-rows"),
          attribute.rows(list.length(string.split(text(model, "rows"), "\n"))),
          event.on_input(Typed("rows", _)),
        ],
        text(model, "rows"),
      ),
    ]),
    html.h2([], [html.text("Overflow")]),
    html.button([attribute.id("more"), event.on_click(More)], [html.text("+")]),
    html.button([attribute.id("less"), event.on_click(Less)], [html.text("-")]),
    html.p([attribute.id("state")], [html.text(state_text(model))]),
    html.div([attribute.class("box")], [
      content(model.lines),
      probe("hidden", "probe probe-hidden", model.lines),
      probe("auto", "probe probe-auto", model.lines),
    ]),
    html.h2([], [html.text("Rows needed")]),
    // One probe per height in grid units; the smallest that fits is the
    // cell's rendered height. Rendered only while needed (a drag start).
    html.div(
      [attribute.class("rows")],
      list.map(range(1, 18), fn(h) {
        html.div(
          [
            attribute.class("probe probe-auto"),
            attribute.style("height", int.to_string(h * 30) <> "px"),
            on_probe("rows-" <> int.to_string(h)),
          ],
          [content(model.lines), html.div([attribute.class("flag")], [])],
        )
      }),
    ),
  ])
}

fn probe(name: String, class: String, lines: Int) -> Element(Msg) {
  html.div([attribute.class(class), on_probe(name)], [
    content(lines),
    html.div([attribute.class("flag")], []),
  ])
}

fn on_probe(name: String) -> attribute.Attribute(Msg) {
  event.on("animationstart", {
    use animation <- decode.field("animationName", decode.string)
    decode.success(Probe(name, animation))
  })
}

fn content(lines: Int) -> Element(Msg) {
  html.div(
    [attribute.class("content")],
    list.map(range(1, lines), fn(i) {
      html.p([], [html.text("Line " <> int.to_string(i))])
    }),
  )
}

fn text(model: Model, id: String) -> String {
  dict.get(model.texts, id) |> result_or("")
}

fn result_or(r: Result(a, b), default: a) -> a {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}

fn state_text(model: Model) -> String {
  let get = fn(name) { dict.get(model.probes, name) |> result_or("?") }
  let rows =
    list.find(range(1, 18), fn(h) { get("rows-" <> int.to_string(h)) == "fits" })
  "lines "
  <> int.to_string(model.lines)
  <> " hidden "
  <> get("hidden")
  <> " auto "
  <> get("auto")
  <> " rows "
  <> case rows {
    Ok(h) -> int.to_string(h)
    Error(_) -> "none"
  }
}

fn range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..range(from + 1, to)]
  }
}

const css =
  "
body { font-family: system-ui; margin: 16px; color: #222; }
textarea { font: 16px/20px system-ui; padding: 4px; border: 1px solid #888;
  width: 240px; box-sizing: border-box; resize: none; overflow: hidden; }
.areas { display: flex; gap: 16px; align-items: start; }
.field { field-sizing: content; min-height: 30px; }
.grow { display: grid; width: 240px; }
.grow::after { content: attr(data-value) ' '; white-space: pre-wrap;
  visibility: hidden; font: 16px/20px system-ui; padding: 4px;
  border: 1px solid transparent; overflow-wrap: break-word; }
.grow > textarea, .grow::after { grid-area: 1 / 1 / 2 / 2; width: 100%; }
.content { font: 20px/30px system-ui; }
.content p { margin: 0; }
.box { position: relative; width: 300px; height: 120px; outline: 1px solid #888; }
.probe { position: absolute; inset: 0; visibility: hidden;
  container-type: scroll-state; }
.probe-hidden { overflow: hidden; }
.probe-auto { overflow: auto; scrollbar-width: none; }
.rows { position: relative; width: 300px; height: 0; }
.rows .probe { inset: auto; top: 0; left: 0; width: 300px; }
.flag { position: absolute; top: 0; width: 1px; height: 1px;
  animation: fits 1ms; }
@container scroll-state(scrollable: bottom) {
  .flag { animation: overflows 1ms; }
}
@keyframes fits { to { opacity: 1; } }
@keyframes overflows { to { opacity: 1; } }
"
