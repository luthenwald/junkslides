//// The editor's screen (05-editor.md, Screen and Cells pane). Classes start
//// with `ze-` so they never meet the theme's `zeno-` classes; the styles are
//// in client/assets/zeno.css.
////
//// Keyboard focus follows the model without JavaScript of our own: the
//// element that should have focus carries an `autofocus` attribute whose
//// value is `model.focus`. Lustre calls `focus()` whenever that attribute
//// is added to an element or its value changes, and focusing also scrolls
//// the element into view.

import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lustre/attribute.{type Attribute, attribute, class}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import zeno/deck.{type Cell, type Slide}
import zeno/dialect
import zeno/id.{type CellTag, type Id}
import zeno/protocol.{type Diagnostic}
import zeno_client/app.{
  type Model, type Shared, Canvas, Closed, Command, Connecting, Drag, Editing,
  Open,
}
import zeno_client/canvas
import zeno_client/edit
import zeno_client/keymap
import zeno_client/nav.{OnCell, OnSlide}
import zeno_client/slide

pub fn view(model: Model) -> Element(app.Msg) {
  case model.deck {
    None ->
      html.main([class("ze-editor")], [
        theme(model),
        html.div([class("ze-panes")], []),
        status(model, []),
      ])
    Some(shared) -> {
      let keys = case model.mode {
        Command -> [command_keys()]
        Editing(..) | Canvas -> []
      }
      html.main([class("ze-editor"), ..keys], [
        theme(model),
        panes(model, shared),
        status(model, status_parts(model, shared)),
        case model.dragging_divider {
          True -> divider_overlay()
          False -> element.none()
        },
        // Memoised per slide inside; a memo around this one would lose the
        // inner memos' cache whenever it is kept.
        slide.probes(shared),
      ])
    }
  }
}

/// The deck's theme. A reload changes its URL, and the browser fetches it
/// again.
/// The theme, and while a reload is on its way, the previous one too. The
/// browser drops a stylesheet as soon as its link changes, so the new one
/// gets a link of its own. A theme that fails to load counts as arrived.
fn theme(model: Model) -> Element(app.Msg) {
  let link = fn(n) {
    let loaded = app.ThemeLoaded(n)
    #(
      int.to_string(n),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/theme.css?v=" <> int.to_string(n)),
        event.on("load", decode.success(loaded)),
        event.on("error", decode.success(loaded)),
      ]),
    )
  }
  keyed.fragment(case model.theme_loaded == model.theme {
    True -> [link(model.theme)]
    False -> [link(model.theme_loaded), link(model.theme)]
  })
}

fn focus(model: Model) -> Attribute(msg) {
  attribute("autofocus", int.to_string(model.focus))
}

// Panes ----------------------------------------------------------------------

fn panes(model: Model, shared: Shared) -> Element(app.Msg) {
  let view = model.view
  let both = !view.cells_hidden && !view.slide_hidden
  let cells_width = case both {
    True ->
      attribute.style("flex-basis", int.to_string(view.cells_width) <> "%")
    False -> class("ze-alone")
  }
  html.div([class("ze-panes")], [
    case view.cells_hidden {
      True -> element.none()
      False ->
        html.div([class("ze-cells-pane"), cells_width], [
          cells(model, shared),
        ])
    },
    case both {
      True ->
        html.div(
          [
            class("ze-divider"),
            event.on("pointerdown", decode.success(app.DividerGrab))
              |> event.prevent_default,
          ],
          [],
        )
      False -> element.none()
    },
    case view.slide_hidden {
      True -> element.none()
      False -> slide_pane(model, shared)
    },
  ])
}

/// While the divider is dragged, one strip per percent of the window's
/// width reports where the pointer is (the hit-cell approach of S1).
fn divider_overlay() -> Element(app.Msg) {
  let release = decode.success(app.DividerRelease)
  html.div(
    [
      class("ze-divider-overlay"),
      event.on("pointerup", release),
      event.on("pointercancel", release),
      event.on("pointerleave", release),
    ],
    int.range(from: 0, to: 100, with: [], run: list.prepend)
      |> list.reverse
      |> list.map(fn(percent) {
        html.div(
          [
            class("ze-strip"),
            event.on("pointerenter", decode.success(app.DividerAt(percent))),
          ],
          [],
        )
      }),
  )
}

/// The slide of the selection. In canvas mode the selected drawn cell has
/// focus, or the pane itself when the selection is not drawn.
fn slide_pane(model: Model, shared: Shared) -> Element(app.Msg) {
  let shown =
    nav.slide_of(shared.deck, model.selection)
    |> result.try(deck.find_slide(shared.deck, _))
  let pane_focus = case model.mode {
    Canvas -> !canvas.is_drawn(shared.deck, model.selection)
    Command | Editing(..) -> model.view.cells_hidden
  }
  let keys = case model.mode {
    Canvas -> [canvas_keys()]
    Command | Editing(..) -> []
  }
  let release = case model.drag {
    Some(Drag(released: None, ..)) -> {
      let end = decode.success(app.DragEnd)
      [
        event.on("pointerup", end),
        event.on("pointercancel", end),
        event.on("pointerleave", end),
      ]
    }
    _ -> []
  }
  html.div(
    [
      class("ze-slide-pane"),
      attribute.classes([#("ze-canvas", model.mode == Canvas)]),
      attribute.tabindex(-1),
      ..list.flatten([
        case pane_focus {
          True -> [focus(model)]
          False -> []
        },
        keys,
        release,
      ])
    ],
    [
      html.div([class("ze-stage")], [
        case shown {
          Ok(shown) -> slide.view(model, shared, shown, focus(model))
          Error(Nil) -> element.none()
        },
      ]),
    ],
  )
}

// Cells pane -------------------------------------------------------------------

fn cells(model: Model, shared: Shared) -> Element(app.Msg) {
  let total = list.length(shared.deck.slides)
  let overflowing = app.overflowing(model, shared)
  keyed.div(
    [class("ze-cells")],
    list.index_map(shared.deck.slides, fn(slide, index) {
      #(
        id.to_string(slide.id),
        section(model, shared, overflowing, slide, nav.number(index, total)),
      )
    }),
  )
}

fn section(
  model: Model,
  shared: Shared,
  overflowing: List(Id(CellTag)),
  slide: Slide,
  number: String,
) -> Element(app.Msg) {
  let items = case slide.cells {
    [] -> [#(id.to_string(slide.id), empty_slide(model, slide))]
    cells ->
      list.map(cells, fn(c) {
        let overflows = list.contains(overflowing, c.id)
        #(id.to_string(c.id), cell(model, shared.diagnostics, overflows, c))
      })
  }
  html.section([class("ze-slide")], [
    html.div([class("ze-rule")], [html.span([], [text(number)])]),
    keyed.div([class("ze-slide-cells")], items),
  ])
}

fn empty_slide(model: Model, slide: Slide) -> Element(app.Msg) {
  let selected = model.selection == OnSlide(slide.id)
  html.div(
    [
      class("ze-cell ze-empty"),
      attribute.classes([#("ze-selected", selected)]),
      attribute.tabindex(-1),
      event.on_click(app.Select(OnSlide(slide.id))),
      ..case selected, model.mode {
        True, Command | True, Canvas -> [focus(model)]
        _, _ -> []
      }
    ],
    [text("empty slide")],
  )
}

fn cell(
  model: Model,
  diagnostics: List(Diagnostic),
  overflows: Bool,
  c: Cell,
) -> Element(app.Msg) {
  let selected = model.selection == OnCell(c.id)
  let #(source, editing, edit_problem) = case model.mode {
    Editing(cell:, text:, problem:, ..) if cell == c.id -> #(text, True, problem)
    _ -> #(c.source, False, None)
  }
  let wrapper_focus = case selected && !editing {
    True -> [focus(model)]
    False -> []
  }
  let area_focus = case editing {
    True -> [focus(model)]
    False -> []
  }
  let notes = c.kind == deck.Notes
  html.div(
    [
      class("ze-cell"),
      attribute.classes([
        #("ze-notes", notes),
        #("ze-selected", selected),
        #("ze-editing", editing),
      ]),
      attribute.tabindex(-1),
      attribute.data("cell", id.to_string(c.id)),
      event.on_click(app.Select(OnCell(c.id))),
      ..wrapper_focus
    ],
    [
      case notes {
        True -> html.span([class("ze-label")], [text("notes")])
        False -> element.none()
      },
      // The mirror technique of S2: the text is shown again, hidden, in the
      // same grid cell, so the text area grows with it.
      html.div([class("ze-grow"), attribute.data("value", source)], [
        html.textarea(
          [
            class("ze-source"),
            attribute.rows(1),
            attribute.spellcheck(False),
            event.on_focus(app.StartEdit(c.id)),
            event.on_blur(app.Blurred(c.id)),
            event.on_input(fn(text) { app.Typed(c.id, text) }),
            edit_keys(),
            ..area_focus
          ],
          source,
        ),
      ]),
      problems(c, diagnostics, overflows, edit_problem),
    ],
  )
}

fn problems(
  c: Cell,
  diagnostics: List(Diagnostic),
  overflows: Bool,
  edit_problem: option.Option(_),
) -> Element(app.Msg) {
  let dialect_problems =
    list.find(diagnostics, fn(d) { d.cell == c.id })
    |> option.from_result
    |> option.map(fn(d) {
      "Not in the dialect: "
      <> string.join(list.map(d.problems, dialect.describe), ", ")
      <> "."
    })
  let overflow = case overflows {
    True -> Some("Does not fit its box on the slide.")
    False -> None
  }
  let lines =
    [option.map(edit_problem, edit.describe), dialect_problems, overflow]
    |> option.values
  case lines {
    [] -> element.none()
    lines ->
      html.div(
        [class("ze-problem")],
        list.map(lines, fn(line) { html.div([], [text(line)]) }),
      )
  }
}

// Keys -----------------------------------------------------------------------

/// Command-mode keys, caught on the editor as they bubble up from the
/// selected cell. Keys not in the keymap are left to the browser.
fn command_keys() -> Attribute(app.Msg) {
  event.advanced("keydown", {
    use key <- decode.then(keymap.decoder())
    case keymap.command(key) {
      Ok(command) ->
        decode.success(event.handler(
          app.CommandKey(command),
          prevent_default: True,
          stop_propagation: False,
        ))
      Error(Nil) -> decode.failure(not_a_key(), "a key in the keymap")
    }
  })
}

/// Canvas-mode keys, caught on the slide pane. The focused drawn cell's box
/// comes along, so that an unplaced cell can be placed where it is drawn.
fn canvas_keys() -> Attribute(app.Msg) {
  event.advanced("keydown", {
    use key <- decode.then(keymap.decoder())
    use box <- decode.then(
      decode.one_of(
        decode.at(["target"], slide.box_decoder()) |> decode.map(Some),
        [
          decode.success(None),
        ],
      ),
    )
    case keymap.canvas(key) {
      Ok(command) ->
        decode.success(event.handler(
          app.CanvasKey(command, box),
          prevent_default: True,
          stop_propagation: False,
        ))
      Error(Nil) -> decode.failure(not_a_key(), "a key in the keymap")
    }
  })
}

/// Edit-mode keys on a text area, with the cursor position for a split.
fn edit_keys() -> Attribute(app.Msg) {
  event.advanced("keydown", {
    use key <- decode.then(keymap.decoder())
    use cursor <- decode.subfield(["target", "selectionStart"], decode.int)
    case keymap.edit(key) {
      Ok(command) ->
        decode.success(event.handler(
          app.EditKey(command, cursor),
          prevent_default: True,
          stop_propagation: True,
        ))
      Error(Nil) -> decode.failure(not_a_key(), "a key in the keymap")
    }
  })
}

/// The zero value a failing decoder needs; it is never dispatched.
fn not_a_key() -> event.Handler(app.Msg) {
  event.handler(
    app.TypingPaused(-1),
    prevent_default: False,
    stop_propagation: False,
  )
}

// Status line -----------------------------------------------------------------

fn status_parts(model: Model, shared: Shared) -> List(String) {
  let total = list.length(shared.deck.slides)
  let slide = case nav.slide_index(shared.deck, model.selection) {
    Ok(index) -> [nav.number(index, total)]
    Error(Nil) -> []
  }
  let count = fn(n, one, many) {
    case n {
      0 -> []
      1 -> ["1 " <> one]
      n -> [int.to_string(n) <> " " <> many]
    }
  }
  list.flatten([
    slide,
    count(
      list.length(shared.diagnostics),
      "cell with problems",
      "cells with problems",
    ),
    count(
      list.length(app.overflowing(model, shared)),
      "cell overflows",
      "cells overflow",
    ),
    count(list.length(shared.layout.orphans), "orphan", "orphans"),
  ])
}

fn status(model: Model, parts: List(String)) -> Element(app.Msg) {
  let mode = case model.mode {
    Command -> "command"
    Editing(..) -> "edit"
    Canvas -> "canvas"
  }
  let connection = case model.connection {
    Open(_) -> []
    Connecting -> ["connecting"]
    Closed -> ["offline, reconnecting"]
  }
  let notice = case model.notice {
    Some(notice) -> [html.span([class("ze-notice")], [text(notice)])]
    None -> []
  }
  html.footer(
    [class("ze-status")],
    list.flatten([
      list.map([mode, ..list.append(parts, connection)], fn(part) {
        html.span([], [text(part)])
      }),
      notice,
    ]),
  )
}
