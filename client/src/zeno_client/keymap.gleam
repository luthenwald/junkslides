//// The keymap, in one place (05-editor.md, Keymap). Keys are matched on the
//// browser's `key` value, so `J` is a shifted `j`. Keys held with Cmd are
//// left to the browser.

import gleam/dynamic/decode.{type Decoder}

pub type Key {
  Key(key: String, ctrl: Bool, alt: Bool, meta: Bool, composing: Bool)
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
  Undo
  Redo
  ToggleCells
  ToggleSlide
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
        _ -> Error(Nil)
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
  use ctrl <- decode.field("ctrlKey", decode.bool)
  use alt <- decode.field("altKey", decode.bool)
  use meta <- decode.field("metaKey", decode.bool)
  use composing <- decode.optional_field("isComposing", False, decode.bool)
  decode.success(Key(key:, ctrl:, alt:, meta:, composing:))
}
