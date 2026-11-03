//// Slides as Lustre elements (04-layout.md, Theme contract), on both targets:
//// the editor draws them in the browser and export writes them on the server.
//// `document` is the exported page (04-layout.md, Export).

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import jot
import lustre/attribute.{type Attribute, attribute, class}
import lustre/element.{type Element, text}
import lustre/element/html
import zeno/deck.{type Cell, type Deck, type Slide}
import zeno/dialect
import zeno/layout.{type Area, type CellRecord, type Layout}
import zeno/protocol.{type CodeBlock, type Token, CodeBlock}
import zeno/render/styles

/// The whole deck as one static page, without any script. Each slide is the
/// theme contract's structure in a frame whose ID is the slide's number. The
/// deck's settings follow the base styles as `settings.css`, and the theme
/// comes last, as `theme.css` beside the page, so that it wins.
pub fn document(
  deck deck: Deck,
  layout layout: Layout,
  highlights highlights: Highlights,
  title title: String,
  has_settings has_settings: Bool,
  has_theme has_theme: Bool,
) -> String {
  let total = list.length(deck.slides)
  let sheet = fn(present, href) {
    case present {
      True -> [html.link([attribute.rel("stylesheet"), attribute.href(href)])]
      False -> []
    }
  }
  let theme =
    list.append(
      sheet(has_settings, "settings.css"),
      sheet(has_theme, "theme.css"),
    )
  html.html([], [
    html.head(
      [],
      list.append(
        [
          html.meta([attribute("charset", "utf-8")]),
          html.meta([
            attribute.name("viewport"),
            attribute("content", "width=device-width, initial-scale=1"),
          ]),
          html.title([], title),
          html.style([], styles.base_css),
          html.style([], styles.page_css),
        ],
        theme,
      ),
    ),
    html.body(
      [],
      list.index_map(deck.slides, fn(slide, index) {
        frame(slide, index, total, layout, highlights)
      }),
    ),
  ])
  |> element.to_document_string
}

fn frame(
  slide: Slide,
  index: Int,
  total: Int,
  layout: Layout,
  highlights: Highlights,
) -> Element(msg) {
  let drawn =
    drawn_cells(slide)
    |> list.map(fn(cell) { #(cell, layout.record(layout, cell.id)) })
  let box = fn(pair: #(Cell, CellRecord), area) {
    cell_box(pair.0, pair.1, area, [], highlights)
  }
  let #(placed, unplaced) =
    list.partition(drawn, fn(pair) { option.is_some({ pair.1 }.place) })
  html.section([class("zeno-frame"), attribute.id(int.to_string(index + 1))], [
    html.div(
      [class("zeno-slide")],
      list.flatten([
        [html.div([class("zeno-body")], list.map(unplaced, box(_, None)))],
        list.map(placed, fn(pair) { box(pair, { pair.1 }.place) }),
        [page_number(index, total)],
      ]),
    ),
  ])
}

/// The cells a slide draws: notes are never on the slide.
pub fn drawn_cells(slide: Slide) -> List(Cell) {
  list.filter(slide.cells, fn(cell) { cell.kind == deck.Content })
}

/// Slide numbers as the editor shows them: `01/12`, zero-padded to the
/// width of the total and at least two digits.
pub fn number(index: Int, total: Int) -> String {
  // Digits are single bytes, and byte sizes avoid grapheme segmentation,
  // which is slow on JavaScript and runs for every slide on every render.
  let width = int.max(2, string.byte_size(int.to_string(total)))
  let pad = fn(n) {
    let digits = int.to_string(n)
    string.repeat("0", width - string.byte_size(digits)) <> digits
  }
  pad(index + 1) <> "/" <> pad(total)
}

/// The slide's number for the theme to place or hide (04-layout.md, Theme
/// contract), in two parts, `01` and `/12`, so that a stylesheet can hide the
/// total. Not a cell, so it is not in the overflow probes.
pub fn page_number(index: Int, total: Int) -> Element(msg) {
  let #(own, of) = case string.split_once(number(index, total), "/") {
    Ok(#(own, of)) -> #(own, "/" <> of)
    Error(Nil) -> #(number(index, total), "")
  }
  html.div([class("zeno-page")], [
    html.span([class("zeno-page-index")], [text(own)]),
    html.span([class("zeno-page-total")], [text(of)]),
  ])
}

/// A drawn cell, as the theme contract describes it, with the caller's
/// attributes after the theme's.
pub fn cell_box(
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

// Cell bodies -------------------------------------------------------------------

/// A cell body from its jot AST, never through `jot.to_html`. Constructs the
/// dialect forbids still render harmlessly: no attributes are passed on, raw
/// blocks show as text, and URLs go through `dialect.safe_url`.
///
/// The source's lines are kept (04-layout.md, Line structure): every soft
/// or hard break is a line break, followed by the indentation its line had
/// in the source, from `dialect.top_level`.
pub fn body(source: String, highlights: Highlights) -> List(Element(msg)) {
  list.map(dialect.top_level(source), fn(block) {
    case block {
      dialect.Contained(container: c, lines:) ->
        container(c, lines, highlights).0
      dialect.Tabular(table:) -> table_view(table)
    }
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
    jot.Codeblock(language:, content:, attributes:) -> #(
      html.pre([], [
        html.code(
          option.values([option.map(language, attribute.data("language", _))]),
          code(
            language,
            content,
            dialect.code_marks_or_none(attributes),
            highlights,
          ),
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

/// A table (02-file-format.md, Tables). Its look is in the base styles
/// (04-layout.md, Theme contract). A column's alignment is on its cells, for
/// the theme to see.
fn table_view(table: dialect.Table) -> Element(msg) {
  let aligns = list.map(table.columns, column_align)
  let cells = fn(cells, make) {
    list.map2(cells, aligns, fn(content, align) {
      make(align, inlines(content, []).0)
    })
  }
  html.table([], [
    html.thead([], [
      html.tr(
        [],
        cells(table.head, fn(align, children) {
          html.th([attribute("scope", "col"), ..align], children)
        }),
      ),
    ]),
    html.tbody(
      [],
      list.map(table.rows, fn(row) { html.tr([], cells(row, html.td)) }),
    ),
  ])
}

fn column_align(align: dialect.ColumnAlign) -> List(Attribute(msg)) {
  case align {
    dialect.AlignDefault -> []
    dialect.AlignStart -> [attribute.data("align", "start")]
    dialect.AlignCenter -> [attribute.data("align", "center")]
    dialect.AlignEnd -> [attribute.data("align", "end")]
  }
}

/// A code block's text, with the tokens the server sent for it, if any. With
/// an attribute line (D28) it is drawn line by line: lit lines inside
/// `span.zeno-lit`, marks as `span.<mark>` around their tokens, and the
/// delimiters left out. The server highlights the text without them.
fn code(
  language: Option(String),
  content: String,
  marks: dialect.CodeMarks,
  highlights: Highlights,
) -> List(Element(msg)) {
  let #(text, pieces) = dialect.marked_code(content, marks)
  let tokens =
    option.then(language, fn(language) {
      dict.get(highlights, CodeBlock(language, text))
      |> option.from_result
    })
  case marks, tokens {
    dialect.CodeMarks(lit: [], marks: []), None -> [element.text(text)]
    dialect.CodeMarks(lit: [], marks: []), Some(tokens) ->
      list.map(tokens, token_element)
    _, _ -> {
      let tokens = option.unwrap(tokens, [protocol.Token(None, text)])
      code_lines(merge(tokens, pieces), marks.lit)
    }
  }
}

fn token_element(token: Token) -> Element(msg) {
  case token.kind {
    Some(kind) -> html.span([class(token_classes(kind))], [text(token.text)])
    None -> text(token.text)
  }
}

/// A piece of code with its token kind and its mark.
type Piece {
  Piece(kind: Option(String), mark: Option(String), text: String)
}

/// Tokens and marked pieces cut at each other's edges. Both cover the same
/// text; if they do not (tokens of an older text), the tokens are dropped.
fn merge(tokens: List(Token), pieces: List(dialect.Marked)) -> List(Piece) {
  let same =
    string.concat(list.map(tokens, fn(t) { t.text }))
    == string.concat(list.map(pieces, fn(p) { p.text }))
  case same {
    True -> merge_loop(tokens, pieces, [])
    False -> list.map(pieces, fn(p) { Piece(None, p.mark, p.text) })
  }
}

fn merge_loop(
  tokens: List(Token),
  pieces: List(dialect.Marked),
  done: List(Piece),
) -> List(Piece) {
  case tokens, pieces {
    [protocol.Token(text: "", ..), ..tokens], _ ->
      merge_loop(tokens, pieces, done)
    _, [dialect.Marked(text: "", ..), ..pieces] ->
      merge_loop(tokens, pieces, done)
    [t, ..ts], [p, ..ps] -> {
      let lt = string.length(t.text)
      let lp = string.length(p.text)
      case int.compare(lt, lp) {
        order.Eq -> merge_loop(ts, ps, [Piece(t.kind, p.mark, t.text), ..done])
        order.Lt ->
          merge_loop(
            ts,
            [dialect.Marked(p.mark, string.drop_start(p.text, lt)), ..ps],
            [Piece(t.kind, p.mark, t.text), ..done],
          )
        order.Gt ->
          merge_loop(
            [protocol.Token(t.kind, string.drop_start(t.text, lp)), ..ts],
            ps,
            [Piece(t.kind, p.mark, p.text), ..done],
          )
      }
    }
    _, _ -> list.reverse(done)
  }
}

/// Pieces as lines: each line's pieces grouped by mark, a lit line wrapped,
/// the line breaks between them as text.
fn code_lines(pieces: List(Piece), lit: List(Int)) -> List(Element(msg)) {
  let lines =
    list.fold(pieces, [[]], fn(lines, piece) {
      string.split(piece.text, "\n")
      |> list.index_fold(lines, fn(lines, part, i) {
        let lines = case i, lines {
          0, _ -> lines
          _, _ -> [[], ..lines]
        }
        case part, lines {
          "", _ -> lines
          _, [line, ..rest] -> [[Piece(..piece, text: part), ..line], ..rest]
          _, [] -> lines
        }
      })
    })
    |> list.reverse
    |> list.map(list.reverse)
  list.index_map(lines, fn(line, i) {
    let children =
      list.chunk(line, fn(piece) { piece.mark })
      |> list.flat_map(fn(group) {
        let tokens =
          list.map(group, fn(piece) {
            token_element(protocol.Token(piece.kind, piece.text))
          })
        case group {
          [Piece(mark: Some(mark), ..), ..] -> [
            html.span([class(mark)], tokens),
          ]
          _ -> tokens
        }
      })
    let line = case list.contains(lit, i + 1) {
      True -> [html.span([class("zeno-lit")], children)]
      False -> children
    }
    case i {
      0 -> line
      _ -> [text("\n"), ..line]
    }
  })
  |> list.flatten
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
    jot.Span(attributes:, content:) ->
      wrap(content, html.span(span_class(attributes), _))
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

/// A span's classes are marks the theme names (D28); nothing else of its
/// attributes reaches the page.
fn span_class(attributes: Dict(String, String)) -> List(Attribute(msg)) {
  case dialect.span_classes(attributes) {
    [] -> []
    classes -> [class(string.join(classes, " "))]
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
