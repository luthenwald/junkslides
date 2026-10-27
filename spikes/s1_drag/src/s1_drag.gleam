//// S1: drag and resize a box on a 32x18 grid with Lustre and CSS only.
////
//// While a drag is active, an overlay of 32x18 invisible hit cells covers
//// the slide. Each hit cell reports `pointerenter` with its own column and
//// row, so snapping needs neither pointer capture nor measurement.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn main() -> Nil {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub type Area {
  Area(col: Int, row: Int, w: Int, h: Int)
}

type Mode {
  Moving
  Resizing
}

type Drag {
  Drag(mode: Mode, start: Area, grab: #(Int, Int), preview: Area)
}

type Model {
  Model(area: Area, drag: Option(Drag), commits: Int, hovers: Int)
}

type Msg {
  /// The grab offset inside the box, in grid units.
  Down(mode: Mode, dx: Int, dy: Int)
  Hover(col: Int, row: Int)
  Up
}

fn init(_flags: Nil) -> Model {
  Model(Area(4, 3, 8, 4), None, 0, 0)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg, model.drag {
    Down(mode, dx, dy), None -> {
      let grab = #(model.area.col + dx, model.area.row + dy)
      Model(..model, drag: Some(Drag(mode, model.area, grab, model.area)))
    }
    Hover(col, row), Some(drag) -> {
      let drag = case drag.mode, drag.grab {
        Moving, #(gc, gr) ->
          Drag(
            ..drag,
            preview: clamp(
              Area(
                ..drag.start,
                col: drag.start.col + col - gc,
                row: drag.start.row + row - gr,
              ),
            ),
          )
        Resizing, _ ->
          Drag(
            ..drag,
            preview: clamp(
              Area(
                ..drag.start,
                w: col - drag.start.col + 1,
                h: row - drag.start.row + 1,
              ),
            ),
          )
      }
      Model(..model, drag: Some(drag), hovers: model.hovers + 1)
    }
    // One commit per drag: this is where the single `Place` op would go.
    Up, Some(drag) ->
      Model(..model, area: drag.preview, drag: None, commits: model.commits + 1)
    _, _ -> model
  }
}

/// Keep the area inside the 32x18 grid, at least one unit in each direction.
pub fn clamp(a: Area) -> Area {
  let w = int.clamp(a.w, 1, 32)
  let h = int.clamp(a.h, 1, 18)
  Area(
    col: int.clamp(a.col, 0, 32 - w),
    row: int.clamp(a.row, 0, 18 - h),
    w: w,
    h: h,
  )
}

fn view(model: Model) -> Element(Msg) {
  let shown = case model.drag {
    Some(drag) -> drag.preview
    None -> model.area
  }
  // The stage covers the viewport, so a release outside the slide still ends
  // the drag. A release outside the window is not seen without capture.
  html.div(
    [
      attribute.class("stage"),
      event.on("pointerup", decode_always(Up)),
      event.on("pointercancel", decode_always(Up)),
    ],
    [
      html.style([], css),
      html.div(
        [
          attribute.class("slide"),
          attribute.id("slide"),
        ],
        [
          html.div(
            [
              attribute.class("box"),
              attribute.id("box"),
              attribute.attribute("data-area", area_text(shown)),
              grid_area(shown),
              event.on("pointerdown", grab_decoder())
                |> event.prevent_default,
            ],
            [
              html.span([], [html.text("Drag me")]),
              html.div(
                [
                  attribute.class("handle"),
                  attribute.id("handle"),
                  event.on("pointerdown", decode_always(Down(Resizing, 0, 0)))
                    |> event.prevent_default
                    |> event.stop_propagation,
                ],
                [],
              ),
            ],
          ),
          hit_cells(option.is_some(model.drag)),
        ],
      ),
      html.p([attribute.id("status")], [
        html.text(
          "area "
          <> area_text(model.area)
          <> " commits "
          <> int.to_string(model.commits)
          <> " hovers "
          <> int.to_string(model.hovers),
        ),
      ]),
    ],
  )
}

/// The overlay is always rendered and only shown during a drag, so its 576
/// cells are created once.
fn hit_cells(active: Bool) -> Element(Msg) {
  {
    html.div(
      [attribute.class("hits"), attribute.classes([#("active", active)])],
      list.flat_map(range(0, 17), fn(row) {
        list.map(range(0, 31), fn(col) {
          html.div(
            [
              attribute.class("hit"),
              grid_area(Area(col, row, 1, 1)),
              event.on("pointerenter", decode_always(Hover(col, row))),
            ],
            [],
          )
        })
      }),
    )
  }
}

/// offsetX and offsetY are in the box's own (unscaled) coordinates, so one
/// grid unit is 60 px whatever the scale.
fn grab_decoder() -> decode.Decoder(Msg) {
  use x <- decode.field("offsetX", decode.float)
  use y <- decode.field("offsetY", decode.float)
  decode.success(Down(
    Moving,
    float.truncate(x /. 60.0),
    float.truncate(y /. 60.0),
  ))
}

fn decode_always(msg: Msg) -> decode.Decoder(Msg) {
  decode.success(msg)
}

fn range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..range(from + 1, to)]
  }
}

fn grid_area(a: Area) -> Attribute(Msg) {
  attribute.style(
    "grid-area",
    string.join(
      [
        int.to_string(a.row + 1),
        int.to_string(a.col + 1),
        "span " <> int.to_string(a.h),
        "span " <> int.to_string(a.w),
      ],
      " / ",
    ),
  )
}

fn area_text(a: Area) -> String {
  [a.col, a.row, a.w, a.h] |> list.map(int.to_string) |> string.join(" ")
}

const css =
  "
html, body { margin: 0; height: 100%; background: #f4f4f4; }
.stage { position: fixed; inset: 0; container-type: size;
  font-family: system-ui; }
.slide { position: absolute; left: 50%; top: 50%; translate: -50% -50%;
  width: 1920px; height: 1080px; background: #fff;
  display: grid; grid-template-columns: repeat(32, 60px);
  grid-template-rows: repeat(18, 60px);
  scale: min(100cqw / 1920px, 100cqh / 1080px);
  background-image:
    linear-gradient(to right, #eee 1px, transparent 1px),
    linear-gradient(to bottom, #eee 1px, transparent 1px);
  background-size: 60px 60px; touch-action: none; user-select: none; }
.box { position: relative; background: #ddd; outline: 2px solid #555;
  display: grid; place-items: center; font-size: 40px; cursor: grab; }
.box > :not(.handle) { pointer-events: none; }
.handle { position: absolute; right: -12px; bottom: -12px; width: 24px;
  height: 24px; background: #555; cursor: nwse-resize; }
.hits { position: absolute; inset: 0; display: grid;
  grid-template-columns: repeat(32, 60px); grid-template-rows: repeat(18, 60px);
  z-index: 10; visibility: hidden; }
.hits.active { visibility: visible; }
#status { position: fixed; left: 8px; bottom: 0; margin: 4px; color: #555; }
"
