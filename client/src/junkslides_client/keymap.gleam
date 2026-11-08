//// The keymap, in one place (05-editor.md, Keymap). Keys are matched on the
//// browser's `key` value, so `J` is a shifted `j`, except with Alt, which
//// changes `key` on macOS (Option-h types `˙`), so Alt keys are matched on
//// `code`. Keys held with Cmd are left to the browser; Ctrl means the
//// Control key on every system, also on macOS.

import gleam/dynamic/decode.{type Decoder}

pub type Key {
  Key(
    key: String,
    code: String,
    ctrl: Bool,
    alt: Bool,
    shift: Bool,
    meta: Bool,
    composing: Bool,
  )
}

pub type Command {
  Next
  Previous
  NextSlide
  PreviousSlide
  MoveDown
  MoveUp
  NewBelow
  NewAbove
  Edit
  CycleKind
  Cut
  Copy
  PasteBelow
  PasteAbove
  Duplicate
  Merge
  BreakHere
  RemoveBreak
  DeleteSlide
  Undo
  Redo
  PurgeOrphans
  Export
  ExportPdf
  ToggleCells
  ToggleSlide
  ToCanvas
}

pub type CanvasCommand {
  NextDrawn
  PreviousDrawn
  PlaceHere
  Nudge(dx: Int, dy: Int)
  Resize(dw: Int, dh: Int)
  ReturnToFlow
  CycleVariant
  CycleAlign
  SnapFiner
  SnapCoarser
  CanvasUndo
  CanvasRedo
  ToCells
}

pub type EditCommand {
  Commit
  SplitHere
}

pub fn command(key: Key) -> Result(Command, Nil) {
  case key {
    Key(meta: True, ..) | Key(composing: True, ..) -> Error(Nil)
    Key(ctrl: True, key: "[", ..) -> Ok(ToggleCells)
    Key(ctrl: True, key: "]", ..) -> Ok(ToggleSlide)
    Key(ctrl: True, shift: True, alt: False, key: "D", ..)
    | Key(ctrl: True, shift: True, alt: False, key: "d", ..) -> Ok(DeleteSlide)
    Key(ctrl: True, ..) | Key(alt: True, ..) -> Error(Nil)
    Key(key:, ..) ->
      case key {
        "j" | "ArrowDown" -> Ok(Next)
        "k" | "ArrowUp" -> Ok(Previous)
        "}" -> Ok(NextSlide)
        "{" -> Ok(PreviousSlide)
        "J" -> Ok(MoveDown)
        "K" -> Ok(MoveUp)
        "o" -> Ok(NewBelow)
        "O" -> Ok(NewAbove)
        "Enter" | "i" -> Ok(Edit)
        "t" -> Ok(CycleKind)
        "d" -> Ok(Cut)
        "y" -> Ok(Copy)
        "p" -> Ok(PasteBelow)
        "P" -> Ok(PasteAbove)
        "D" -> Ok(Duplicate)
        "m" -> Ok(Merge)
        "b" -> Ok(BreakHere)
        "B" -> Ok(RemoveBreak)
        "u" -> Ok(Undo)
        "U" -> Ok(Redo)
        "X" -> Ok(PurgeOrphans)
        "E" -> Ok(Export)
        "F" -> Ok(ExportPdf)
        "Tab" -> Ok(ToCanvas)
        _ -> Error(Nil)
      }
  }
}

pub fn canvas(key: Key) -> Result(CanvasCommand, Nil) {
  case key {
    Key(meta: True, ..) | Key(composing: True, ..) | Key(ctrl: True, ..) ->
      Error(Nil)
    Key(alt: True, code:, ..) ->
      case code {
        "KeyH" -> Ok(Nudge(-1, 0))
        "KeyJ" -> Ok(Nudge(0, 1))
        "KeyK" -> Ok(Nudge(0, -1))
        "KeyL" -> Ok(Nudge(1, 0))
        _ -> Error(Nil)
      }
    Key(key:, shift:, ..) ->
      case key, shift {
        "ArrowLeft", False -> Ok(Nudge(-1, 0))
        "ArrowDown", False -> Ok(Nudge(0, 1))
        "ArrowUp", False -> Ok(Nudge(0, -1))
        "ArrowRight", False -> Ok(Nudge(1, 0))
        "H", _ | "ArrowLeft", True -> Ok(Resize(-1, 0))
        "J", _ | "ArrowDown", True -> Ok(Resize(0, 1))
        "K", _ | "ArrowUp", True -> Ok(Resize(0, -1))
        "L", _ | "ArrowRight", True -> Ok(Resize(1, 0))
        "j", _ -> Ok(NextDrawn)
        "k", _ -> Ok(PreviousDrawn)
        "Enter", _ -> Ok(PlaceHere)
        "f", _ -> Ok(ReturnToFlow)
        "v", _ -> Ok(CycleVariant)
        "a", _ -> Ok(CycleAlign)
        "g", _ -> Ok(SnapFiner)
        "G", _ -> Ok(SnapCoarser)
        "u", _ -> Ok(CanvasUndo)
        "U", _ -> Ok(CanvasRedo)
        "Tab", _ | "Escape", _ -> Ok(ToCells)
        _, _ -> Error(Nil)
      }
  }
}

pub fn edit(key: Key) -> Result(EditCommand, Nil) {
  case key {
    Key(composing: True, ..) | Key(meta: True, ..) -> Error(Nil)
    Key(key: "Escape", ..) -> Ok(Commit)
    Key(key: "Enter", alt: True, ..) -> Ok(SplitHere)
    _ -> Error(Nil)
  }
}

/// Decodes a `keydown` event.
pub fn decoder() -> Decoder(Key) {
  use key <- decode.field("key", decode.string)
  use code <- decode.optional_field("code", "", decode.string)
  use ctrl <- decode.field("ctrlKey", decode.bool)
  use alt <- decode.field("altKey", decode.bool)
  use shift <- decode.optional_field("shiftKey", False, decode.bool)
  use meta <- decode.field("metaKey", decode.bool)
  use composing <- decode.optional_field("isComposing", False, decode.bool)
  decode.success(Key(key:, code:, ctrl:, alt:, shift:, meta:, composing:))
}
