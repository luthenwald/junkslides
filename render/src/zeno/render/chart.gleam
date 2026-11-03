//// Charts from a spec in JSON (D29; 02-file-format.md, Charts): lines over a
//// linear or log axis, dots on a log axis, stacked bars, and horizontal bars
//// on a log scale. Drawn as HTML around one SVG per panel, in the manner of
//// the PSaV talk's charts, whose spec this is.
////
//// A panel's viewBox is its box in units of two design pixels, so text in a
//// chart keeps one size whatever the chart's size. A chart with a grid of
//// panels shows one row at a time, picked by radio buttons, without script:
//// the base styles show the row whose button is checked.

import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/attribute.{attribute, class}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/element/svg

// The spec ----------------------------------------------------------------------

pub type Chart {
  Lines(
    x: Axis,
    y: Axis,
    wall: Option(Float),
    panels: List(LinePanel),
    grid: Option(Grid),
  )
  Dots(x: Axis, panels: List(DotPanel))
  Stacked(x: Axis, y: Axis, order: List(String), panels: List(BarPanel))
  Bars(log: Bool, groups: List(Group))
}

pub type Axis {
  Axis(label: String, log: Bool)
}

/// The rows and columns of a chart's panels. Each row is one view.
pub type Grid {
  Grid(rows: List(String), cols: List(String))
}

pub type LinePanel {
  LinePanel(
    title: String,
    row: Option(String),
    col: Option(String),
    series: List(Series),
  )
}

pub type Series {
  Series(label: String, look: Look, points: List(Point))
}

/// A series' shade, marker shape and dash, as class names for the theme.
pub type Look {
  Look(shade: String, shape: String, dash: String)
}

/// A censored point is a run stopped at a wall, drawn with an open marker.
pub type Point {
  Point(x: Float, y: Float, censored: Bool)
}

pub type DotPanel {
  DotPanel(title: String, items: List(Item))
}

pub type Item {
  Item(label: String, value: Float, best: Bool)
}

pub type BarPanel {
  BarPanel(title: String, bars: List(Bar))
}

pub type Bar {
  Bar(x: Float, parts: Dict(String, Float))
}

pub type Group {
  Group(label: String, note: String, rows: List(BarRow))
}

pub type BarRow {
  BarRow(label: String, value: Float, now: Bool)
}

// Reading -----------------------------------------------------------------------

/// The chart in a spec, or why it is not one.
pub fn decode(text: String) -> Result(Chart, String) {
  json.parse(text, chart_decoder())
  |> result.map_error(fn(error) {
    case error {
      json.UnableToDecode(errors) ->
        list.map(errors, fn(e) {
          e.expected <> " at " <> string.join(e.path, ".")
        })
        |> string.join("; ")
      _ -> "not JSON"
    }
  })
}

fn chart_decoder() -> Decoder(Chart) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "lines" -> {
      use x <- decode.field("x", axis())
      use y <- decode.field("y", axis())
      use wall <- decode.optional_field("wall", None, decode.optional(number()))
      use panels <- decode.field("panels", decode.list(line_panel()))
      use grid <- decode.optional_field("grid", None, decode.optional(grid()))
      decode.success(Lines(x:, y:, wall:, panels:, grid:))
    }
    "dots" -> {
      use x <- decode.field("x", axis())
      use panels <- decode.field("panels", decode.list(dot_panel()))
      decode.success(Dots(x:, panels:))
    }
    "stacked" -> {
      use x <- decode.field("x", axis())
      use y <- decode.field("y", axis())
      use order <- decode.field("order", decode.list(name()))
      use panels <- decode.field("panels", decode.list(bar_panel()))
      decode.success(Stacked(x:, y:, order:, panels:))
    }
    "bars" -> {
      use log <- decode.optional_field("log", True, decode.bool)
      use groups <- decode.field("groups", decode.list(group()))
      decode.success(Bars(log:, groups:))
    }
    _ -> decode.failure(Bars(True, []), "a kind: lines, dots, stacked or bars")
  }
}

fn number() -> Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

/// A name that becomes a class: letters, digits, spaces and `-`; spaces
/// become `-` in the class.
fn name() -> Decoder(String) {
  use text <- decode.then(decode.string)
  let ok =
    text != ""
    && list.all(string.to_graphemes(text), fn(g) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789- ",
        g,
      )
    })
  case ok {
    True -> decode.success(text)
    False -> decode.failure("", "a name of letters, digits, spaces and -")
  }
}

fn axis() -> Decoder(Axis) {
  use label <- decode.optional_field("label", "", decode.string)
  use log <- decode.optional_field("log", False, decode.bool)
  decode.success(Axis(label:, log:))
}

fn grid() -> Decoder(Grid) {
  use rows <- decode.field("rows", decode.list(decode.string))
  use cols <- decode.field("cols", decode.list(decode.string))
  decode.success(Grid(rows:, cols:))
}

fn line_panel() -> Decoder(LinePanel) {
  use title <- decode.optional_field("title", "", decode.string)
  use row <- decode.optional_field("row", None, decode.optional(decode.string))
  use col <- decode.optional_field("col", None, decode.optional(decode.string))
  use series <- decode.field("series", decode.list(series()))
  decode.success(LinePanel(title:, row:, col:, series:))
}

fn series() -> Decoder(Series) {
  use label <- decode.optional_field("label", "", decode.string)
  use look <- decode.optional_field(
    "look",
    Look("black", "circle", "solid"),
    look(),
  )
  use points <- decode.field("points", decode.list(point()))
  decode.success(Series(label:, look:, points:))
}

fn look() -> Decoder(Look) {
  use shade <- decode.optional_field("shade", "black", name())
  use shape <- decode.optional_field("shape", "circle", name())
  use dash <- decode.optional_field("dash", "solid", name())
  decode.success(Look(shade:, shape:, dash:))
}

fn point() -> Decoder(Point) {
  use x <- decode.field("x", number())
  use y <- decode.field("y", number())
  use censored <- decode.optional_field("censored", False, decode.bool)
  decode.success(Point(x:, y:, censored:))
}

fn dot_panel() -> Decoder(DotPanel) {
  use title <- decode.optional_field("title", "", decode.string)
  use items <- decode.field("items", decode.list(item()))
  decode.success(DotPanel(title:, items:))
}

fn item() -> Decoder(Item) {
  use label <- decode.optional_field("label", "", decode.string)
  use value <- decode.field("value", number())
  use best <- decode.optional_field("best", False, decode.bool)
  decode.success(Item(label:, value:, best:))
}

fn bar_panel() -> Decoder(BarPanel) {
  use title <- decode.optional_field("title", "", decode.string)
  use bars <- decode.field("bars", decode.list(bar()))
  decode.success(BarPanel(title:, bars:))
}

fn bar() -> Decoder(Bar) {
  use x <- decode.field("x", number())
  use parts <- decode.field("parts", decode.dict(decode.string, number()))
  decode.success(Bar(x:, parts:))
}

fn group() -> Decoder(Group) {
  use label <- decode.optional_field("label", "", decode.string)
  use note <- decode.optional_field("note", "", decode.string)
  use rows <- decode.field("rows", decode.list(bar_row()))
  decode.success(Group(label:, note:, rows:))
}

fn bar_row() -> Decoder(BarRow) {
  use label <- decode.optional_field("label", "", decode.string)
  use value <- decode.field("value", number())
  use now <- decode.optional_field("now", False, decode.bool)
  decode.success(BarRow(label:, value:, now:))
}

// Scales and ticks --------------------------------------------------------------

/// The sizes of a chart's frame in slide pixels, as the base styles set them:
/// the legend row without and with a switch, the x and y labels, and the gaps
/// around the panels.
const frame_top = 31.0

const frame_top_switch = 39.0

const frame_label = 28.0

const frame_row_gap = 12.0

const frame_column_gap = 14.0

/// Slide pixels per viewBox unit.
const per_unit = 2.0

/// The margins inside a panel, in viewBox units: left, right, top, bottom.
const pad_l = 30.0

const pad_r = 8.0

const pad_t = 6.0

const pad_b = 18.0

/// The width of the labels beside the first panel of dots, in units.
const labels_width = 108.0

pub type Scale {
  Scale(lo: Float, hi: Float, log: Bool, a: Float, b: Float, ticks: List(Float))
}

/// A scale from `domain` to `[a, b]`, with room around the data: a quarter
/// more each way on a log axis, four percent on a linear one, which starts at
/// zero when the data is close to it.
pub fn scale(domain: #(Float, Float), a: Float, b: Float, log: Bool) -> Scale {
  let #(lo, hi) = domain
  let #(lo, hi) = case log {
    True -> #(lo /. 1.25, hi *. 1.25)
    False -> {
      let span = case hi -. lo {
        0.0 -> 1.0
        span -> span
      }
      let pad = span *. 0.04
      let lo = case lo <. 0.0 || lo >. pad {
        True -> lo -. pad
        False -> 0.0
      }
      #(lo, hi +. pad)
    }
  }
  let ticks = case log {
    True -> log_ticks(lo, hi)
    False -> linear_ticks(lo, hi)
  }
  Scale(lo:, hi:, log:, a:, b:, ticks:)
}

pub fn at(scale: Scale, x: Float) -> Float {
  let t = case scale.log {
    True -> log10
    False -> fn(x) { x }
  }
  scale.a
  +. { t(x) -. t(scale.lo) }
  /. { t(scale.hi) -. t(scale.lo) }
  *. { scale.b -. scale.a }
}

/// Powers of ten within the range, or with fewer than three of them, the
/// ones, twos and fives.
pub fn log_ticks(lo: Float, hi: Float) -> List(Float) {
  let from = float.truncate(float.floor(log10(lo))) - 1
  let to = float.truncate(float.ceiling(log10(hi))) + 1
  let exponents = int.range(from, to + 1, [], list.prepend) |> list.reverse
  let within = fn(v) { v >=. lo && v <=. hi }
  let tens =
    list.map(exponents, fn(e) { significant(ten(e), 3) })
    |> list.filter(within)
  case list.length(tens) >= 3 {
    True -> tens
    False ->
      list.flat_map(exponents, fn(e) {
        list.map([1.0, 2.0, 5.0], fn(m) { significant(m *. ten(e), 3) })
      })
      |> list.filter(within)
      |> list.unique
  }
}

/// About four steps of 1, 2, 2.5 or 5 times a power of ten.
pub fn linear_ticks(lo: Float, hi: Float) -> List(Float) {
  let raw = { hi -. lo } /. 4.0
  let magnitude = ten(float.truncate(float.floor(log10(raw))))
  let step =
    [1.0, 2.0, 2.5, 5.0, 10.0]
    |> list.map(fn(m) { m *. magnitude })
    |> list.find(fn(s) { s >=. raw })
    |> result.unwrap(10.0 *. magnitude)
  let first = float.ceiling(lo /. step) *. step
  linear_loop(first, hi, step, [])
}

fn linear_loop(
  v: Float,
  hi: Float,
  step: Float,
  done: List(Float),
) -> List(Float) {
  case v <=. hi && list.length(done) < 100 {
    True -> linear_loop(v +. step, hi, step, [significant(v, 6), ..done])
    False -> list.reverse(done)
  }
}

fn log10(x: Float) -> Float {
  case float.logarithm(x) {
    Ok(l) -> l /. 2.302585092994046
    Error(Nil) -> 0.0
  }
}

fn ten(e: Int) -> Float {
  float.power(10.0, int.to_float(e)) |> result.unwrap(1.0)
}

/// `x` to `digits` significant digits, as JavaScript's `toPrecision` does.
pub fn significant(x: Float, digits: Int) -> Float {
  case x == 0.0 {
    True -> 0.0
    False -> {
      let e = float.truncate(float.floor(log10(float.absolute_value(x))))
      let shift = digits - 1 - e
      case shift >= 0 {
        True -> int.to_float(float.round(x *. ten(shift))) /. ten(shift)
        False -> int.to_float(float.round(x /. ten(-shift))) *. ten(-shift)
      }
    }
  }
}

/// A number as JavaScript prints it: `50`, `0.1`, `2.5`.
pub fn label(v: Float) -> String {
  let whole = float.round(v)
  case int.to_float(whole) == v && float.absolute_value(v) <. 1.0e15 {
    True -> int.to_string(whole)
    False -> float.to_string(v)
  }
}

/// `1.5K`, `2M`, or the number itself below a thousand.
pub fn compact(v: Float) -> String {
  case v >=. 1.0e6, v >=. 1.0e3 {
    True, _ -> label(significant(v /. 1.0e6, 12)) <> "M"
    _, True -> label(significant(v /. 1.0e3, 12)) <> "K"
    _, _ -> label(v)
  }
}

/// A number for the SVG, to two decimals.
fn n(x: Float) -> String {
  label(int.to_float(float.round(x *. 100.0)) /. 100.0)
}

fn extent(values: List(Float), log: Bool) -> #(Float, Float) {
  let values = case log {
    True -> list.filter(values, fn(v) { v >. 0.0 })
    False -> values
  }
  case values {
    [] -> #(1.0, 10.0)
    [first, ..] -> #(
      list.fold(values, first, float.min),
      list.fold(values, first, float.max),
    )
  }
}

// Drawing -----------------------------------------------------------------------

/// The chart in a box of `width` by `height` design pixels. `group` names its
/// radio buttons, and must differ between the drawn copies of a chart.
pub fn view(
  chart: Chart,
  width: Int,
  height: Int,
  group: String,
) -> Element(msg) {
  case chart {
    Bars(log:, groups:) -> bars_view(log, groups)
    _ -> panels_view(chart, int.to_float(width), int.to_float(height), group)
  }
}

/// One row of panels: its y label and its panels.
type Row(msg) {
  Row(label: String, panels: List(Element(msg)))
}

fn panels_view(
  chart: Chart,
  width: Float,
  height: Float,
  group: String,
) -> Element(msg) {
  let #(kind, rows_of_panels, labels, legend, x_label, y_label) = case chart {
    Lines(x:, y:, panels:, grid:, ..) -> {
      let rows = case grid {
        Some(Grid(rows:, cols:)) ->
          list.map(rows, fn(row) {
            #(
              row,
              list.filter_map(cols, fn(col) {
                list.find(panels, fn(p) {
                  p.row == Some(row) && p.col == Some(col)
                })
              }),
            )
          })
        None -> [#(y.label, panels)]
      }
      #(
        "lines",
        rows,
        grid |> option.map(fn(g) { g.rows }) |> option.unwrap([]),
        line_legend(panels),
        x.label,
        y.label,
      )
    }
    Dots(x:, ..) -> #("dots", [], [], [], x.label, "")
    Stacked(x:, y:, order:, ..) -> #(
      "stacked",
      [],
      [],
      list.index_map(order, fn(part, k) {
        html.span([class("key")], [
          html.i([class("swatch " <> part_class(part, k))], []),
          html.span([], [text(part)]),
        ])
      }),
      x.label,
      y.label,
    )
    Bars(..) -> #("bars", [], [], [], "", "")
  }
  let count = case chart {
    Lines(..) ->
      rows_of_panels
      |> list.first
      |> result.map(fn(r) { list.length(r.1) })
      |> result.unwrap(0)
    Dots(panels:, ..) -> list.length(panels)
    Stacked(panels:, ..) -> list.length(panels)
    Bars(..) -> 0
  }
  let cols = case kind, count {
    "lines", 1 -> 1
    _, _ -> int.max(1, int.min(3, count))
  }
  let rows = { count + cols - 1 } / cols
  let switch = labels != []
  // The panels' box, from the chart's box less the legend row, the x label
  // and the y label, which the base styles give fixed sizes (`frame_*`), so
  // that the panels' viewBox has their box's shape whatever the theme's fonts.
  let has_y = case chart {
    Lines(..) -> list.any(rows_of_panels, fn(row) { row.0 != "" })
    Stacked(y:, ..) -> y.label != ""
    Dots(..) | Bars(..) -> False
  }
  let top = case switch, legend != [] {
    True, _ -> frame_top_switch
    False, True -> frame_top
    False, False -> 0.0
  }
  let panels_w =
    width
    -. frame_column_gap
    -. case has_y {
      True -> frame_label
      False -> 0.0
    }
  let panels_h = height -. top -. frame_label -. 2.0 *. frame_row_gap
  let pw = { panels_w -. int.to_float(cols - 1) *. 34.0 } /. int.to_float(cols)
  let ph =
    { panels_h -. int.to_float(rows - 1) *. 10.0 }
    /. int.to_float(int.max(rows, 1))
    -. 30.0
  let w = float.max(60.0, int.to_float(float.round(pw /. per_unit)))
  let h = float.max(40.0, int.to_float(float.round(ph /. per_unit)))
  let drawn_rows = case chart {
    Lines(..) ->
      list.map(rows_of_panels, fn(row) {
        Row(
          row.0,
          list.map(row.1, fn(p) { panel(p.title, lines_panel(p, chart, w, h)) }),
        )
      })
    Dots(panels:, ..) -> {
      let values =
        list.flat_map(panels, fn(p) { list.map(p.items, fn(i) { i.value }) })
      let lo = list.fold(values, 1.0, float.min) /. 1.6
      let hi = list.fold(values, 0.0, float.max) *. 1.5
      let wd =
        int.to_float(float.round(
          { w *. int.to_float(cols) -. labels_width } /. int.to_float(cols),
        ))
      [
        Row(
          "",
          list.index_map(panels, fn(p, i) {
            let first = i % cols == 0
            let pw = case first {
              True -> wd +. labels_width
              False -> wd
            }
            panel(p.title, dots_panel(p, pw, h, first, lo, hi))
          }),
        ),
      ]
    }
    Stacked(order:, panels:, ..) -> [
      Row(
        y_label,
        list.map(panels, fn(p) { panel(p.title, stacked_panel(p, order, w, h)) }),
      ),
    ]
    Bars(..) -> []
  }
  let columns = case chart {
    Dots(..) -> {
      let wd =
        float.round(
          { w *. int.to_float(cols) -. labels_width } /. int.to_float(cols),
        )
      [
        attribute.style(
          "grid-template-columns",
          int.to_string(wd + float.round(labels_width))
            <> "fr repeat("
            <> int.to_string(cols - 1)
            <> ", "
            <> int.to_string(wd)
            <> "fr)",
        ),
      ]
    }
    _ -> [
      attribute.style(
        "grid-template-columns",
        "repeat(" <> int.to_string(cols) <> ", minmax(0, 1fr))",
      ),
    ]
  }
  html.div([class("zeno-chart"), attribute.data("kind", kind)], [
    html.div([class("zeno-chart-top")], [
      html.p([class("zeno-chart-legend")], legend),
      ..case switch {
        True -> [switch_view(labels, group)]
        False -> []
      }
    ]),
    html.div(
      [class("zeno-chart-plots")],
      list.map(drawn_rows, fn(row) {
        html.div([class("zeno-chart-row")], [
          html.span([class("zeno-chart-ylabel")], [text(row.label)]),
          html.div([class("zeno-chart-panels"), ..columns], row.panels),
        ])
      }),
    ),
    html.p([class("zeno-chart-xlabel")], [text(x_label)]),
  ])
}

/// Radio buttons in labels, the first checked. The base styles show the row
/// of the checked one.
fn switch_view(labels: List(String), group: String) -> Element(msg) {
  html.div([class("zeno-chart-switch"), attribute.role("radiogroup")], [
    html.span([class("zeno-chart-switch-label")], [text("show")]),
    ..list.index_map(labels, fn(label, i) {
      html.label([], [
        html.input([
          attribute.type_("radio"),
          attribute.name(group),
          attribute.checked(i == 0),
        ]),
        html.span([], [text(label)]),
      ])
    })
  ])
}

fn panel(title: String, body: Element(msg)) -> Element(msg) {
  html.div([class("zeno-chart-panel")], [html.h4([], [text(title)]), body])
}

fn line_legend(panels: List(LinePanel)) -> List(Element(msg)) {
  panels
  |> list.flat_map(fn(p) { p.series })
  |> list.fold([], fn(seen: List(#(String, Look)), s) {
    case list.key_find(seen, s.label) {
      Ok(_) -> seen
      Error(Nil) -> [#(s.label, s.look), ..seen]
    }
  })
  |> list.reverse
  |> list.map(fn(pair) {
    let #(label, look) = pair
    html.span([class("key")], [
      svg.svg([attribute("viewBox", "0 0 40 14")], [
        svg.path([
          attribute("d", "M1,7 H39"),
          class("line " <> look.shade <> " " <> look.dash),
        ]),
        marker(look.shape, 20.0, 7.0, "mark " <> look.shade),
      ]),
      html.span([], [text(label)]),
    ])
  })
}

/// A marker in a series' shape; `circle` for any shape it does not know.
fn marker(shape: String, x: Float, y: Float, cls: String) -> Element(msg) {
  let r = 2.4
  let path = fn(d) { svg.path([attribute("d", d), class(cls)]) }
  case shape {
    "square" ->
      path(
        "M"
        <> n(x -. r)
        <> ","
        <> n(y -. r)
        <> " h"
        <> n(2.0 *. r)
        <> " v"
        <> n(2.0 *. r)
        <> " h"
        <> n(-2.0 *. r)
        <> " z",
      )
    "diamond" ->
      path(
        "M"
        <> n(x)
        <> ","
        <> n(y -. r *. 1.3)
        <> " L"
        <> n(x +. r *. 1.3)
        <> ","
        <> n(y)
        <> " L"
        <> n(x)
        <> ","
        <> n(y +. r *. 1.3)
        <> " L"
        <> n(x -. r *. 1.3)
        <> ","
        <> n(y)
        <> " z",
      )
    "triangle" ->
      path(
        "M"
        <> n(x)
        <> ","
        <> n(y -. r *. 1.35)
        <> " L"
        <> n(x +. r *. 1.25)
        <> ","
        <> n(y +. r *. 0.9)
        <> " L"
        <> n(x -. r *. 1.25)
        <> ","
        <> n(y +. r *. 0.9)
        <> " z",
      )
    _ ->
      svg.circle([
        attribute("cx", n(x)),
        attribute("cy", n(y)),
        attribute("r", n(r)),
        class(cls),
      ])
  }
}

fn svg_text(
  x: Float,
  y: Float,
  anchor: String,
  cls: String,
  content: String,
) -> Element(msg) {
  svg.text(
    [
      attribute("x", n(x)),
      attribute("y", n(y)),
      attribute("text-anchor", anchor),
      class(cls),
    ],
    content,
  )
}

fn line(d: String, cls: String) -> Element(msg) {
  svg.path([attribute("d", d), class(cls)])
}

fn box(w: Float, h: Float, children: List(Element(msg))) -> Element(msg) {
  svg.svg([attribute("viewBox", "0 0 " <> n(w) <> " " <> n(h))], children)
}

fn frame(w: Float, h: Float, xs: Scale, ys: Scale) -> List(Element(msg)) {
  let x_ticks = xs.ticks
  let room = list.length(x_ticks) * 18 <= float.round(w -. pad_l -. pad_r)
  list.flatten([
    list.map(ys.ticks, fn(v) {
      line(
        "M" <> n(pad_l) <> "," <> n(at(ys, v)) <> " H" <> n(w -. pad_r),
        "grid",
      )
    }),
    [
      line(
        "M" <> n(pad_l) <> "," <> n(h -. pad_b) <> " H" <> n(w -. pad_r),
        "baseline",
      ),
    ],
    list.map(ys.ticks, fn(v) {
      svg_text(pad_l -. 4.0, at(ys, v) +. 3.0, "end", "tick", compact(v))
    }),
    x_ticks
      |> list.index_map(fn(v, i) { #(v, i) })
      |> list.filter(fn(pair) { room || pair.1 % 2 == 0 })
      |> list.map(fn(pair) {
        let v = pair.0
        svg_text(at(xs, v), h -. pad_b +. 11.0, "middle", "tick", case xs.log {
          True -> compact(v)
          False -> label(v)
        })
      }),
  ])
}

fn lines_panel(p: LinePanel, chart: Chart, w: Float, h: Float) -> Element(msg) {
  let assert Lines(x:, y:, wall:, ..) = chart
  let points = list.flat_map(p.series, fn(s) { s.points })
  let xs =
    scale(
      extent(list.map(points, fn(q) { q.x }), x.log),
      pad_l,
      w -. pad_r,
      x.log,
    )
  let ys =
    scale(
      extent(
        list.append(list.map(points, fn(q) { q.y }), option.values([wall])),
        y.log,
      ),
      h -. pad_b,
      pad_t,
      y.log,
    )
  let wall_line = case wall {
    Some(v) -> [
      line(
        "M" <> n(pad_l) <> "," <> n(at(ys, v)) <> " H" <> n(w -. pad_r),
        "wall",
      ),
    ]
    None -> []
  }
  let series =
    list.flat_map(p.series, fn(s) {
      let on =
        list.filter(s.points, fn(q) {
          { !x.log || q.x >. 0.0 } && { !y.log || q.y >. 0.0 }
        })
      let count = list.length(on)
      let d =
        list.index_map(on, fn(q, i) {
          case i {
            0 -> "M"
            _ -> "L"
          }
          <> n(at(xs, q.x))
          <> ","
          <> n(at(ys, q.y))
        })
        |> string.join(" ")
      let every =
        int.max(
          1,
          float.truncate(float.ceiling(
            int.to_float(count) /. { { w -. pad_l -. pad_r } /. 16.0 },
          )),
        )
      let marked =
        list.index_map(on, fn(q, i) { #(q, i) })
        |> list.filter(fn(pair) {
          pair.1 % every == 0 || pair.1 == count - 1 || { pair.0 }.censored
        })
      [
        line(d, "line " <> s.look.shade <> " " <> s.look.dash),
        ..list.map(marked, fn(pair) {
          let q = pair.0
          marker(
            s.look.shape,
            at(xs, q.x),
            at(ys, q.y),
            "mark "
              <> s.look.shade
              <> case q.censored {
              True -> " open"
              False -> ""
            },
          )
        })
      ]
    })
  box(w, h, list.flatten([frame(w, h, xs, ys), wall_line, series]))
}

fn dots_panel(
  p: DotPanel,
  w: Float,
  h: Float,
  labels: Bool,
  lo: Float,
  hi: Float,
) -> Element(msg) {
  let count = list.length(p.items)
  let left = case labels {
    True -> labels_width +. 10.0
    False -> 10.0
  }
  let y = fn(i) {
    pad_t
    +. 8.0
    +. int.to_float(i)
    *. { h -. pad_b -. pad_t -. 12.0 }
    /. int.to_float(int.max(1, count - 1))
  }
  let x = fn(v) {
    left
    +. { log10(v) -. log10(lo) }
    /. { log10(hi) -. log10(lo) }
    *. { w -. left -. pad_r }
  }
  let ticks =
    [0.1, 0.3, 1.0, 3.0, 10.0, 30.0, 100.0]
    |> list.filter(fn(v) { v >=. lo && v <=. hi })
  box(
    w,
    h,
    list.flatten([
      list.map(ticks, fn(v) {
        line(
          "M" <> n(x(v)) <> "," <> n(pad_t) <> " V" <> n(h -. pad_b),
          case v == 1.0 {
            True -> "baseline"
            False -> "grid"
          },
        )
      }),
      list.map(ticks, fn(v) {
        svg_text(x(v), h -. pad_b +. 11.0, "middle", "tick", label(v))
      }),
      list.index_map(p.items, fn(it, i) {
        list.flatten([
          [
            line(
              "M" <> n(x(1.0)) <> "," <> n(y(i)) <> " H" <> n(x(it.value)),
              "stem",
            ),
            svg.circle([
              attribute("cx", n(x(it.value))),
              attribute("cy", n(y(i))),
              attribute("r", "3"),
              class(case it.best {
                True -> "dot best"
                False -> "dot"
              }),
            ]),
          ],
          case labels {
            True -> [
              svg_text(
                left -. 8.0,
                y(i) +. 3.0,
                "end",
                case it.best {
                  True -> "name"
                  False -> "tick"
                },
                it.label,
              ),
            ]
            False -> []
          },
        ])
      })
        |> list.flatten,
    ]),
  )
}

fn stacked_panel(
  p: BarPanel,
  order: List(String),
  w: Float,
  h: Float,
) -> Element(msg) {
  let totals =
    list.map(p.bars, fn(b) { dict.values(b.parts) |> list.fold(0.0, float.add) })
  let ys =
    scale(#(0.0, list.fold(totals, 0.0, float.max)), h -. pad_b, pad_t, False)
  let count = list.length(p.bars)
  let band = { w -. pad_l -. pad_r } /. int.to_float(int.max(1, count))
  let bw = band *. 0.66
  box(
    w,
    h,
    list.flatten([
      list.map(ys.ticks, fn(v) {
        line(
          "M" <> n(pad_l) <> "," <> n(at(ys, v)) <> " H" <> n(w -. pad_r),
          "grid",
        )
      }),
      list.map(ys.ticks, fn(v) {
        svg_text(pad_l -. 4.0, at(ys, v) +. 3.0, "end", "tick", label(v))
      }),
      list.index_map(p.bars, fn(b, i) {
        let x0 = pad_l +. band *. int.to_float(i) +. { band -. bw } /. 2.0
        let #(rects, _) =
          list.index_fold(order, #([], 0.0), fn(acc, part, k) {
            let #(rects, below) = acc
            case dict.get(b.parts, part) {
              Ok(v) if v >. 0.0 -> {
                let y1 = at(ys, below)
                let y0 = at(ys, below +. v)
                #(
                  [
                    svg.rect([
                      attribute("x", n(x0)),
                      attribute("y", n(y0)),
                      attribute("width", n(bw)),
                      attribute("height", n(y1 -. y0)),
                      class(part_class(part, k)),
                    ]),
                    ..rects
                  ],
                  below +. v,
                )
              }
              _ -> acc
            }
          })
        list.append(list.reverse(rects), [
          svg_text(
            x0 +. bw /. 2.0,
            h -. pad_b +. 11.0,
            "middle",
            "tick",
            label(b.x),
          ),
        ])
      })
        |> list.flatten,
    ]),
  )
}

/// A part's classes: its place in the order, which the base look shades,
/// and its name, which a theme can colour.
fn part_class(part: String, k: Int) -> String {
  "bar part-" <> int.to_string(k + 1) <> " " <> string.replace(part, " ", "-")
}

/// Horizontal bars in groups: the group's label on its first row and its
/// note on the second, then each row's label, a bar and its value. On a log
/// scale a bar's length is the log of its value against the log of the
/// largest, at least 2 %.
fn bars_view(log: Bool, groups: List(Group)) -> Element(msg) {
  let largest =
    groups
    |> list.flat_map(fn(g) { list.map(g.rows, fn(r) { r.value }) })
    |> list.fold(0.0, float.max)
  let share = fn(v) {
    let s = case log, largest >. 1.0 {
      True, True -> log10(float.max(v, 1.0)) /. log10(largest)
      False, _ ->
        case largest >. 0.0 {
          True -> v /. largest
          False -> 0.0
        }
      True, False -> 0.0
    }
    float.max(2.0, int.to_float(float.round(s *. 100.0)))
  }
  html.div(
    [class("zeno-chart"), attribute.data("kind", "bars")],
    list.index_map(groups, fn(g, gi) {
      let gap = case gi {
        0 -> []
        _ -> [html.span([class("gap")], [])]
      }
      list.append(
        gap,
        list.index_map(g.rows, fn(r, i) {
          let head = case i {
            0 -> html.span([class("group")], [text(g.label)])
            1 -> html.span([class("group note")], [text(g.note)])
            _ -> html.span([class("group")], [])
          }
          [
            head,
            html.span([class("which")], [text(r.label)]),
            html.span(
              [
                class(case r.now {
                  True -> "bar now"
                  False -> "bar"
                }),
                attribute.style("--w", label(share(r.value)) <> "%"),
              ],
              [html.i([], []), html.b([], [text(thousands(r.value))])],
            ),
          ]
        })
          |> list.flatten,
      )
    })
      |> list.flatten,
  )
}

/// `2,040`: a whole number with commas, other numbers as they are.
pub fn thousands(v: Float) -> String {
  let whole = float.round(v)
  case int.to_float(whole) == v {
    False -> label(v)
    True -> {
      let digits =
        int.to_string(int.absolute_value(whole)) |> string.to_graphemes
      let grouped =
        digits
        |> list.reverse
        |> list.sized_chunk(3)
        |> list.map(fn(chunk) { chunk |> list.reverse |> string.concat })
        |> list.reverse
        |> string.join(",")
      case whole < 0 {
        True -> "-" <> grouped
        False -> grouped
      }
    }
  }
}

/// A quiet stand-in for a chart that cannot be drawn, with the reason.
pub fn missing(alt: String, why: String) -> Element(msg) {
  html.div([class("zeno-chart zeno-chart-missing")], [
    html.p([], [text(alt)]),
    html.p([class("why")], [text(why)]),
  ])
}
