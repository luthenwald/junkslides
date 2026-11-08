import junkslides_client/keymap.{Key}

fn key(name: String) -> keymap.Key {
  Key(
    key: name,
    code: "",
    ctrl: False,
    alt: False,
    shift: False,
    meta: False,
    composing: False,
  )
}

pub fn command_keys_test() {
  assert keymap.command(key("j")) == Ok(keymap.Next)
  assert keymap.command(key("J")) == Ok(keymap.MoveDown)
  assert keymap.command(key("}")) == Ok(keymap.NextSlide)
  assert keymap.command(key("Enter")) == Ok(keymap.Edit)
  assert keymap.command(key("U")) == Ok(keymap.Redo)
  assert keymap.command(Key(..key("["), ctrl: True)) == Ok(keymap.ToggleCells)
  assert keymap.command(Key(..key("]"), ctrl: True)) == Ok(keymap.ToggleSlide)
  assert keymap.command(key("Tab")) == Ok(keymap.ToCanvas)
}

pub fn browser_keys_are_left_alone_test() {
  assert keymap.command(Key(..key("r"), meta: True)) == Error(Nil)
  assert keymap.command(Key(..key("j"), ctrl: True)) == Error(Nil)
  assert keymap.command(key("x")) == Error(Nil)
  assert keymap.command(Key(..key("j"), composing: True)) == Error(Nil)
}

pub fn edit_keys_test() {
  assert keymap.edit(key("Escape")) == Ok(keymap.Commit)
  assert keymap.edit(Key(..key("Enter"), alt: True)) == Ok(keymap.SplitHere)
  assert keymap.edit(key("Enter")) == Error(Nil)
  // Esc that ends an input method composition is not a commit.
  assert keymap.edit(Key(..key("Escape"), composing: True)) == Error(Nil)
}

pub fn canvas_keys_test() {
  assert keymap.canvas(key("j")) == Ok(keymap.NextDrawn)
  assert keymap.canvas(key("Enter")) == Ok(keymap.PlaceHere)
  assert keymap.canvas(key("ArrowLeft")) == Ok(keymap.Nudge(-1, 0))
  assert keymap.canvas(Key(..key("ArrowLeft"), shift: True))
    == Ok(keymap.Resize(-1, 0))
  assert keymap.canvas(key("J")) == Ok(keymap.Resize(0, 1))
  assert keymap.canvas(key("g")) == Ok(keymap.SnapFiner)
  assert keymap.canvas(key("G")) == Ok(keymap.SnapCoarser)
  assert keymap.canvas(key("Tab")) == Ok(keymap.ToCells)
  assert keymap.canvas(key("Escape")) == Ok(keymap.ToCells)
  assert keymap.canvas(key("x")) == Error(Nil)
}

pub fn alt_keys_match_the_physical_key_test() {
  // Option-l on macOS types `¬`.
  let alt_l = Key(..key("¬"), code: "KeyL", alt: True)
  assert keymap.canvas(alt_l) == Ok(keymap.Nudge(1, 0))
  assert keymap.canvas(Key(..key("j"), code: "KeyJ", ctrl: True)) == Error(Nil)
}

pub fn export_key_test() {
  assert keymap.command(key("E")) == Ok(keymap.Export)
}

pub fn purge_key_test() {
  assert keymap.command(key("X")) == Ok(keymap.PurgeOrphans)
  assert keymap.command(Key(..key("x"), meta: True)) == Error(Nil)
}

pub fn delete_slide_key_test() {
  // Control on every system, Cmd stays with the browser.
  let ctrl_shift_d = Key(..key("D"), code: "KeyD", ctrl: True, shift: True)
  assert keymap.command(ctrl_shift_d) == Ok(keymap.DeleteSlide)
  assert keymap.command(Key(..ctrl_shift_d, key: "d")) == Ok(keymap.DeleteSlide)
  assert keymap.command(Key(..ctrl_shift_d, meta: True)) == Error(Nil)
  assert keymap.command(Key(..ctrl_shift_d, alt: True)) == Error(Nil)
  assert keymap.command(Key(..ctrl_shift_d, shift: False, key: "d"))
    == Error(Nil)
  assert keymap.command(key("d")) == Ok(keymap.Cut)
}
