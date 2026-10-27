//// The slide pane's canvas (04-layout.md): the slide drawn from deck, layout
//// and theme, the editor layer above it, and the hidden overflow probes.
////
//// The slide follows the theme contract: `.zeno-slide`, `.zeno-body` with
//// the unplaced content cells in source order, and placed cells as
//// `.zeno-cell[data-placed]` with an inline `grid-area`. Editor classes on
//// drawn cells (`ze-selected`, `ze-overflow`) only draw outlines, so the
//// theme's layout is never changed by the editor.
////
//// Overflow reaches the model through CSS (spike S2): behind every drawn box
//// a hidden copy is a scroll-state container, and its `::after` flag starts
//// the animation `ze-fits` or `ze-overflows`. An unplaced cell's box is the
//// body as a whole, so its probe is a copy of the body holding the cells up
//// to and including it: the cell overflows when that copy does.

import gleam/bool
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import jot
import lustre/attribute.{type Attribute, attribute, class}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import zeno/deck.{type Cell, type Slide}
import zeno/dialect
import zeno/id
import zeno/layout.{type Area, type CellRecord}
import zeno_client/app.{type Drag, type Model, type Shared, Canvas, Drag}
import zeno_client/canvas.{type Box, Box}
import zeno_client/nav.{OnCell}

/// The slide of the selection, scaled to fit the pane, with the editor
/// layer (resize handle, drag targets) above it.
pub fn view(
  model: Model,
  shared: Shared,
  slide: Slide,
  focus: Attribute(app.Msg),
) -> Element(app.Msg) {
  let drawn = drawn_cells(slide)
  let place = fn(cell: Cell) { preview(model.drag, cell, shared) }
  let unplaced = list.filter(drawn, fn(cell) { place(cell) == None })
  let placed =
    list.filter_map(drawn, fn(cell) {
      case place(cell) {
        Some(area) -> Ok(#(cell, area))
        None -> Error(Nil)
      }
    })
  let overflowing = app.overflowing(model, shared)
  let drawn_cell = fn(cell: Cell, area: Option(Area)) {
    let selected = model.selection == OnCell(cell.id)
    let decorations = [
      attribute.classes([
        #("ze-selected", selected),
        #("ze-overflow", list.contains(overflowing, cell.id)),
      ]),
      attribute.data("cell", id.to_string(cell.id)),
      attribute.tabindex(-1),
      grab(cell),
      ..case selected && model.mode == Canvas {
        True -> [focus]
        False -> []
      }
    ]
    #(
      id.to_string(cell.id),
      cell_box(cell, layout.record(shared.layout, cell.id), area, decorations),
    )
  }
  html.div([class("ze-fit")], [
    keyed.div([class("zeno-slide")], [
      #(
        "body",
        keyed.div(
          [class("zeno-body")],
          list.map(unplaced, fn(cell) { drawn_cell(cell, None) }),
        ),
      ),
      ..list.map(placed, fn(pair) { drawn_cell(pair.0, Some(pair.1)) })
    ]),
    editor_layer(model, placed),
  ])
}

/// Where a cell is drawn: a drag in progress shows its preview.
fn preview(drag: Option(Drag), cell: Cell, shared: Shared) -> Option(Area) {
  let placed = canvas.placed(shared.layout, cell.id)
  case drag {
    Some(Drag(cell: dragged, start:, area:, ..)) if dragged == cell.id ->
      case placed, area == start {
        None, True -> None
        _, _ -> Some(area)
      }
    _ -> placed
  }
}

fn drawn_cells(slide: Slide) -> List(Cell) {
  list.filter(slide.cells, fn(cell) { cell.kind == deck.Content })
}

/// A drawn cell, as the theme contract describes it, with the editor's
/// attributes after the theme's.
fn cell_box(
  cell: Cell,
  record: CellRecord,
  area: Option(Area),
  extra: List(Attribute(msg)),
) -> Element(msg) {
  let placement = case area {
    Some(area) -> [attribute("data-placed", ""), grid_area(area)]
    None -> []
  }
  let style =
    [
      option.map(record.variant, attribute.data("variant", _)),
      option.map(record.align, fn(align) {
        attribute.data("align", case align {
          layout.Start -> "start"
          layout.Center -> "center"
          layout.End -> "end"
        })
      }),
    ]
    |> option.values
  html.div(
    [class("zeno-cell"), ..list.flatten([placement, style, extra])],
    body(cell.source),
  )
}

fn grid_area(area: Area) -> Attribute(msg) {
  attribute.style(
    "grid-area",
    int.to_string(area.row + 1)
      <> " / "
      <> int.to_string(area.col + 1)
      <> " / span "
      <> int.to_string(area.h)
      <> " / span "
      <> int.to_string(area.w),
  )
}

// Pointer --------------------------------------------------------------------

/// A press on a drawn cell. `offsetX` and `offsetY` are in the cell's own,
/// unscaled coordinates (its children take no pointer events, so the cell
/// is always the target), and the cell's box is read from the target.
fn grab(cell: Cell) -> Attribute(app.Msg) {
  event.on("pointerdown", {
    use button <- decode.field("button", decode.int)
    use x <- decode.field("offsetX", decode.float)
    use y <- decode.field("offsetY", decode.float)
    use box <- decode.field("target", box_decoder())
    case button {
      0 ->
        decode.success(app.Grab(
          cell.id,
          box.left + float.truncate(x),
          box.top + float.truncate(y),
          box,
        ))
      _ -> decode.failure(app.DragEnd, "the primary button")
    }
  })
}

/// A drawn cell's box relative to the slide, in design pixels. Layout
/// offsets ignore the scale, so no measurement of our own is needed.
pub fn box_decoder() -> Decoder(Box) {
  use class <- decode.field("className", decode.string)
  use <- bool.guard(
    !string.contains(class, "zeno-cell"),
    decode.failure(Box(0, 0, 0, 0), "a drawn cell"),
  )
  use width <- decode.field("offsetWidth", decode.int)
  use height <- decode.field("offsetHeight", decode.int)
  use #(left, top) <- decode.then(offset_in_slide())
  decode.success(Box(left:, top:, width:, height:))
}

/// Offsets summed up the chain of offset parents until the slide.
fn offset_in_slide() -> Decoder(#(Int, Int)) {
  use left <- decode.field("offsetLeft", decode.int)
  use top <- decode.field("offsetTop", decode.int)
  use parent <- decode.field("offsetParent", {
    use class <- decode.field("className", decode.string)
    case string.contains(class, "zeno-slide") {
      True -> decode.success(#(0, 0))
      False -> decode.recursive(offset_in_slide)
    }
  })
  decode.success(#(left + parent.0, top + parent.1))
}

/// The editor's own layer, the same grid as the slide: the resize handle of
/// the selected placed cell, and during a drag one target per grid cell
/// that reports the pointer (spike S1).
fn editor_layer(model: Model, placed: List(#(Cell, Area))) -> Element(app.Msg) {
  let handle =
    list.filter_map(placed, fn(pair) {
      let #(cell, area) = pair
      let dragging = model.drag != None
      case
        model.mode == Canvas && model.selection == OnCell(cell.id) && !dragging
      {
        True ->
          Ok(
            html.div(
              [
                class("ze-handle"),
                grid_area(area),
                event.on("pointerdown", decode.success(app.GrabHandle(cell.id))),
              ],
              [],
            ),
          )
        False -> Error(Nil)
      }
    })
  let targets = case model.drag {
    Some(Drag(released: False, ..)) ->
      list.flat_map(range(0, layout.rows), fn(row) {
        list.map(range(0, layout.columns), fn(col) {
          // Placed explicitly, so that nothing else in the grid moves them.
          html.div(
            [
              class("ze-target"),
              grid_area(layout.Area(col:, row:, w: 1, h: 1)),
              event.on("pointerenter", decode.success(app.DragAt(col, row))),
            ],
            [],
          )
        })
      })
    _ -> []
  }
  html.div([class("ze-layer")], list.append(handle, targets))
}

fn range(from: Int, to: Int) -> List(Int) {
  int.range(from:, to:, with: [], run: list.prepend) |> list.reverse
}

// Probes ---------------------------------------------------------------------

/// Hidden copies of every slide, one probe per drawn cell. Kept out of the
/// panes so that overflow is known for every slide, also with the slide
/// pane hidden.
pub fn probes(shared: Shared) -> Element(app.Msg) {
  keyed.div(
    [class("ze-probes"), attribute.aria_hidden(True)],
    list.map(shared.deck.slides, fn(slide) {
      #(id.to_string(slide.id), probe_slide(shared, slide))
    }),
  )
}

fn probe_slide(shared: Shared, slide: Slide) -> Element(app.Msg) {
  let record = fn(cell: Cell) { layout.record(shared.layout, cell.id) }
  let unplaced =
    list.filter(drawn_cells(slide), fn(cell) { record(cell).place == None })
  let bodies =
    list.index_map(unplaced, fn(cell, index) {
      let flow =
        list.take(unplaced, index + 1)
        |> list.map(fn(c) { cell_box(c, record(c), None, []) })
      #(
        "b" <> id.to_string(cell.id),
        html.div([class("zeno-body ze-probe"), on_probe(cell)], flow),
      )
    })
  let placed =
    list.filter_map(drawn_cells(slide), fn(cell) {
      case record(cell).place {
        Some(area) -> {
          let probe = [class("ze-probe"), on_probe(cell)]
          Ok(#(
            "p" <> id.to_string(cell.id),
            cell_box(cell, record(cell), Some(area), probe),
          ))
        }
        None -> Error(Nil)
      }
    })
  keyed.div([class("zeno-slide ze-probe-slide")], list.append(bodies, placed))
}

fn on_probe(cell: Cell) -> Attribute(app.Msg) {
  event.on("animationstart", {
    use name <- decode.field("animationName", decode.string)
    case name {
      "ze-fits" -> decode.success(app.Probe(cell.id, False))
      "ze-overflows" -> decode.success(app.Probe(cell.id, True))
      _ -> decode.failure(app.DragEnd, "a probe animation")
    }
  })
}

// Cell bodies -------------------------------------------------------------------

/// A cell body from its jot AST, never through `jot.to_html`. Constructs the
/// dialect forbids still render harmlessly: no attributes are passed on, raw
/// blocks show as text, and URLs go through `dialect.safe_url`.
pub fn body(source: String) -> List(Element(msg)) {
  list.map(dialect.parse(source).content, container)
}

fn container(c: jot.Container) -> Element(msg) {
  case c {
    jot.Paragraph(content:, ..) -> html.p([], inlines(content))
    jot.Heading(level:, content:, ..) ->
      element.element("h" <> int.to_string(level), [], inlines(content))
    jot.Codeblock(language:, content:, ..) ->
      html.pre([], [
        html.code(
          option.values([option.map(language, attribute.data("language", _))]),
          [
            text(content),
          ],
        ),
      ])
    jot.BulletList(layout:, items:, ..) ->
      html.ul([], list.map(items, item(layout, _)))
    jot.OrderedList(layout:, start:, items:, ..) -> {
      let start = case start {
        1 -> []
        n -> [attribute("start", int.to_string(n))]
      }
      html.ol(start, list.map(items, item(layout, _)))
    }
    jot.BlockQuote(items:, ..) ->
      html.blockquote([], list.map(items, container))
    jot.ThematicBreak -> html.hr([])
    jot.RawBlock(content:) -> html.pre([], [text(content)])
    jot.Div(items:, ..) -> html.div([], list.map(items, container))
  }
}

/// Items of a tight list hold their text without a paragraph around it.
fn item(
  list_layout: jot.ListLayout,
  blocks: List(jot.Container),
) -> Element(msg) {
  case list_layout {
    jot.Tight ->
      html.li(
        [],
        list.flat_map(blocks, fn(block) {
          case block {
            jot.Paragraph(content:, ..) -> inlines(content)
            other -> [container(other)]
          }
        }),
      )
    jot.Loose -> html.li([], list.map(blocks, container))
  }
}

fn inlines(content: List(jot.Inline)) -> List(Element(msg)) {
  list.map(content, inline)
}

fn inline(i: jot.Inline) -> Element(msg) {
  case i {
    jot.Text(t) -> text(t)
    jot.Linebreak -> html.br([])
    jot.NonBreakingSpace -> text("\u{a0}")
    jot.Emphasis(content) -> html.em([], inlines(content))
    jot.Strong(content) -> html.strong([], inlines(content))
    jot.Code(content) -> html.code([], [text(content)])
    jot.Link(content:, destination:, ..) ->
      case url(destination) {
        Some(href) -> html.a([attribute.href(href)], inlines(content))
        None -> html.span([], inlines(content))
      }
    jot.Image(content:, destination:, ..) ->
      case url(destination) {
        Some(src) ->
          html.img([attribute.src(src), attribute.alt(plain(content))])
        None -> html.span([], [text(plain(content))])
      }
    jot.Span(content:, ..) -> html.span([], inlines(content))
    jot.Delete(content) -> html.del([], inlines(content))
    jot.Insert(content) -> html.ins([], inlines(content))
    jot.Mark(content) -> html.mark([], inlines(content))
    jot.Superscript(content) -> html.sup([], inlines(content))
    jot.Subscript(content) -> html.sub([], inlines(content))
    jot.Footnote(reference) -> html.sup([], [text(reference)])
    jot.MathInline(content) | jot.MathDisplay(content) ->
      html.code([], [text(content)])
    jot.Symbol(content) -> text(":" <> content <> ":")
  }
}

/// Reference links are outside the dialect, so only inline URLs are used.
fn url(destination: jot.Destination) -> Option(String) {
  case destination {
    jot.Url(url) -> dialect.safe_url(url)
    jot.Reference(_) -> None
  }
}

fn plain(content: List(jot.Inline)) -> String {
  list.map(content, fn(i) {
    case i {
      jot.Text(t) | jot.Code(t) -> t
      jot.Emphasis(c) | jot.Strong(c) | jot.Link(content: c, ..) -> plain(c)
      _ -> ""
    }
  })
  |> string.concat
}
