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
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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
import zeno/protocol.{type CodeBlock, type Token, CodeBlock}
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
      cell_box(
        cell,
        layout.record(shared.layout, cell.id),
        area,
        decorations,
        model.highlights,
      ),
    )
  }
  html.div([class("ze-fit")], [
    keyed.div(
      [class("zeno-slide")],
      list.flatten([
        [
          #(
            "body",
            keyed.div(
              [class("zeno-body")],
              list.map(unplaced, fn(cell) { drawn_cell(cell, None) }),
            ),
          ),
        ],
        list.map(placed, fn(pair) { drawn_cell(pair.0, Some(pair.1)) }),
        [#("page", page_number(shared, slide))],
      ]),
    ),
    editor_layer(model, placed),
  ])
}

/// The slide's number, `01/26`, for the theme to place or hide (04-layout.md,
/// Theme contract). Not a cell, so it is not in the probes.
fn page_number(shared: Shared, slide: Slide) -> Element(msg) {
  let total = list.length(shared.deck.slides)
  let index =
    nav.slide_index(shared.deck, nav.OnSlide(slide.id)) |> result.unwrap(0)
  html.div([class("zeno-page")], [text(nav.number(index, total))])
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
  highlights: Highlights,
) -> Element(msg) {
  let placement = case area {
    Some(area) -> [attribute("data-placed", ""), ..position(area)]
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
    body(cell.source, highlights),
  )
}

/// A placed cell's box on the slide, in design pixels. Inline styles win
/// over any stylesheet, the theme's and the probes' alike.
fn position(area: Area) -> List(Attribute(msg)) {
  let px = fn(n) { int.to_string(n) <> "px" }
  [
    attribute.style("position", "absolute"),
    attribute.style("left", px(area.x)),
    attribute.style("top", px(area.y)),
    attribute.style("width", px(area.w)),
    attribute.style("height", px(area.h)),
  ]
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

/// The editor's own layer over the slide: the resize handle of the
/// selected placed cell, and during a drag the surface that reports the
/// pointer.
fn editor_layer(model: Model, placed: List(#(Cell, Area))) -> Element(app.Msg) {
  let handle =
    list.filter_map(placed, fn(pair) {
      let #(cell, area) = pair
      let dragging = model.drag != None
      case
        model.mode == Canvas && model.selection == OnCell(cell.id) && !dragging
      {
        True ->
          Ok(html.div(
            [
              class("ze-handle"),
              // On the bottom-right corner; its size and offset are in zeno.css.
              attribute.style("left", int.to_string(area.x + area.w) <> "px"),
              attribute.style("top", int.to_string(area.y + area.h) <> "px"),
              event.on("pointerdown", decode.success(app.GrabHandle(cell.id))),
            ],
            [],
          ))
        False -> Error(Nil)
      }
    })
  let surface = case model.drag {
    Some(Drag(released: None, ..)) -> [drag_surface()]
    _ -> []
  }
  html.div([class("ze-layer")], list.append(handle, surface))
}

/// How far the drag surface reaches past the slide on each side, in design
/// pixels: twice the slide, so it covers the pane down to a fifth of the
/// slide's size.
const reach_x = 3840

const reach_y = 2160

/// One transparent surface over the slide and the pane's margin while a
/// drag lasts. `offsetX` and `offsetY` are in its own unscaled pixels
/// (spike S1), so the pointer is known in design pixels anywhere in the
/// pane, also off the slide.
fn drag_surface() -> Element(app.Msg) {
  html.div(
    [
      class("ze-drag"),
      event.on("pointermove", {
        use x <- decode.field("offsetX", decode.float)
        use y <- decode.field("offsetY", decode.float)
        decode.success(app.DragTo(
          float.truncate(x) - reach_x,
          float.truncate(y) - reach_y,
        ))
      }),
    ],
    [],
  )
}

// Probes ---------------------------------------------------------------------

/// Hidden copies of every slide, one probe per drawn cell. Kept out of the
/// panes so that overflow is known for every slide, also with the slide
/// pane hidden.
pub fn probes(shared: Shared) -> Element(app.Msg) {
  keyed.div(
    [class("ze-probes"), attribute.aria_hidden(True)],
    list.map(shared.deck.slides, fn(slide) {
      // A new state brings new values for every slide, but most slides are
      // as they were. Strings compare by value, so a slide's probes render
      // again only when its drawn cells or their records change.
      let key =
        drawn_cells(slide)
        |> list.map(fn(cell) {
          id.to_string(cell.id)
          <> string.inspect(layout.record(shared.layout, cell.id))
          <> cell.source
        })
        |> string.join("\u{0}")
      #(
        id.to_string(slide.id),
        element.memo([element.ref(key)], fn() { probe_slide(shared, slide) }),
      )
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
        |> list.map(fn(c) { cell_box(c, record(c), None, [], dict.new()) })
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
            cell_box(cell, record(cell), Some(area), probe, dict.new()),
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
///
/// The source's lines are kept (04-layout.md, Line structure): every soft
/// or hard break is a line break, followed by the indentation its line had
/// in the source, from `dialect.continuation_indents`. Should the blocks not
/// match up, breaks are kept without indentation.
pub fn body(source: String, highlights: Highlights) -> List(Element(msg)) {
  let doc = dialect.parse(source)
  let indents = dialect.continuation_indents(source)
  let indents = case list.length(indents) == list.length(doc.content) {
    True -> indents
    False -> list.map(doc.content, fn(_) { [] })
  }
  list.map2(doc.content, indents, fn(c, lines) {
    container(c, lines, highlights).0
  })
}

/// `lines` are the indents of the continuation lines still ahead in this
/// block; each break takes the first one.
type Lines =
  List(Int)

pub type Highlights =
  Dict(CodeBlock, List(Token))

fn container(
  c: jot.Container,
  lines: Lines,
  highlights: Highlights,
) -> #(Element(msg), Lines) {
  let contained = fn(c, lines) { container(c, lines, highlights) }
  let each_item = fn(items, list_layout, lines) {
    each(items, lines, fn(blocks, lines) {
      item(list_layout, blocks, lines, highlights)
    })
  }
  case c {
    jot.Paragraph(content:, ..) -> {
      let #(children, lines) = inlines(content, lines)
      #(html.p([], children), lines)
    }
    jot.Heading(level:, content:, ..) -> {
      let #(children, lines) = inlines(content, lines)
      #(element.element("h" <> int.to_string(level), [], children), lines)
    }
    jot.Codeblock(language:, content:, ..) -> #(
      html.pre([], [
        html.code(
          option.values([option.map(language, attribute.data("language", _))]),
          code(language, content, highlights),
        ),
      ]),
      lines,
    )
    jot.BulletList(layout:, items:, ..) -> {
      let #(items, lines) = each_item(items, layout, lines)
      #(html.ul([], items), lines)
    }
    jot.OrderedList(layout:, start:, items:, ..) -> {
      let start = case start {
        1 -> []
        n -> [attribute("start", int.to_string(n))]
      }
      let #(items, lines) = each_item(items, layout, lines)
      #(html.ol(start, items), lines)
    }
    jot.BlockQuote(items:, ..) -> {
      let #(children, lines) = each(items, lines, contained)
      #(html.blockquote([], children), lines)
    }
    jot.ThematicBreak -> #(html.hr([]), lines)
    jot.RawBlock(content:) -> #(html.pre([], [text(content)]), lines)
    jot.Div(items:, ..) -> {
      let #(children, lines) = each(items, lines, contained)
      #(html.div([], children), lines)
    }
  }
}

/// A code block's text, with the tokens the server sent for it, if any.
fn code(
  language: Option(String),
  content: String,
  highlights: Highlights,
) -> List(Element(msg)) {
  let tokens =
    option.then(language, fn(language) {
      dict.get(highlights, CodeBlock(language, content))
      |> option.from_result
    })
  case tokens {
    None -> [text(content)]
    Some(tokens) ->
      list.map(tokens, fn(token) {
        case token.kind {
          Some(kind) ->
            html.span([class(token_classes(kind))], [text(token.text)])
          None -> text(token.text)
        }
      })
  }
}

/// `punctuation.bracket` gives `zeno-tok-punctuation` and
/// `zeno-tok-punctuation-bracket`, so a theme can style either.
pub fn token_classes(kind: String) -> String {
  let parts = string.split(kind, ".")
  list.index_map(parts, fn(_, index) {
    "zeno-tok-" <> string.join(list.take(parts, index + 1), "-")
  })
  |> string.join(" ")
}

/// Renders each of `xs` in order, passing the remaining lines along.
fn each(
  xs: List(a),
  lines: Lines,
  render: fn(a, Lines) -> #(b, Lines),
) -> #(List(b), Lines) {
  let #(done, lines) =
    list.fold(xs, #([], lines), fn(acc, x) {
      let #(done, lines) = acc
      let #(one, lines) = render(x, lines)
      #([one, ..done], lines)
    })
  #(list.reverse(done), lines)
}

/// Items of a tight list hold their text without a paragraph around it.
fn item(
  list_layout: jot.ListLayout,
  blocks: List(jot.Container),
  lines: Lines,
  highlights: Highlights,
) -> #(Element(msg), Lines) {
  let contained = fn(c, lines) { container(c, lines, highlights) }
  case list_layout {
    jot.Tight -> {
      let #(children, lines) =
        each(blocks, lines, fn(block, lines) {
          case block {
            jot.Paragraph(content:, ..) -> inlines(content, lines)
            other -> {
              let #(element, lines) = contained(other, lines)
              #([element], lines)
            }
          }
        })
      #(html.li([], list.flatten(children)), lines)
    }
    jot.Loose -> {
      let #(children, lines) = each(blocks, lines, contained)
      #(html.li([], children), lines)
    }
  }
}

fn inlines(
  content: List(jot.Inline),
  lines: Lines,
) -> #(List(Element(msg)), Lines) {
  let #(children, lines) = each(content, lines, inline)
  #(list.flatten(children), lines)
}

fn inline(i: jot.Inline, lines: Lines) -> #(List(Element(msg)), Lines) {
  let wrap = fn(content, make) {
    let #(children, lines) = inlines(content, lines)
    #([make(children)], lines)
  }
  case i {
    jot.Text(t) -> soft_breaks(t, lines)
    jot.Linebreak -> line_break(lines)
    jot.NonBreakingSpace -> #([text("\u{a0}")], lines)
    jot.Emphasis(content) -> wrap(content, html.em([], _))
    jot.Strong(content) -> wrap(content, html.strong([], _))
    jot.Code(content) -> #([html.code([], [text(content)])], lines)
    jot.Link(content:, destination:, ..) ->
      case url(destination) {
        Some(href) -> wrap(content, html.a([attribute.href(href)], _))
        None -> wrap(content, html.span([], _))
      }
    jot.Image(content:, destination:, ..) ->
      case url(destination) {
        Some(src) -> #(
          [html.img([attribute.src(src), attribute.alt(plain(content))])],
          lines,
        )
        None -> #([html.span([], [text(plain(content))])], lines)
      }
    jot.Span(content:, ..) -> wrap(content, html.span([], _))
    jot.Delete(content) -> wrap(content, html.del([], _))
    jot.Insert(content) -> wrap(content, html.ins([], _))
    jot.Mark(content) -> wrap(content, html.mark([], _))
    jot.Superscript(content) -> wrap(content, html.sup([], _))
    jot.Subscript(content) -> wrap(content, html.sub([], _))
    jot.Footnote(reference) -> #([html.sup([], [text(reference)])], lines)
    jot.MathInline(content) | jot.MathDisplay(content) -> #(
      [html.code([], [text(content)])],
      lines,
    )
    jot.Symbol(content) -> #([text(":" <> content <> ":")], lines)
  }
}

/// jot keeps a soft break as a newline in the text.
fn soft_breaks(t: String, lines: Lines) -> #(List(Element(msg)), Lines) {
  case string.split(t, "\n") {
    [first, ..rest] ->
      list.fold(rest, #([text(first)], lines), fn(acc, part) {
        let #(done, lines) = acc
        let #(break, lines) = line_break(lines)
        #(list.flatten([done, break, [text(part)]]), lines)
      })
    [] -> #([], lines)
  }
}

/// A line break, then the next line's indentation.
fn line_break(lines: Lines) -> #(List(Element(msg)), Lines) {
  case lines {
    [0, ..rest] | [] as rest -> #([html.br([])], rest)
    [n, ..rest] -> #(
      [
        html.br([]),
        html.span([class("zeno-indent")], [text(string.repeat(" ", n))]),
      ],
      rest,
    )
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
