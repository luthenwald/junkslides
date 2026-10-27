import zeno_client/keymap.{Key}

fn key(name: String) -> keymap.Key {
  Key(key: name, ctrl: False, alt: False, meta: False, composing: False)
}

pub fn command_keys_test() {
  assert keymap.command(key("j")) == Ok(keymap.Next)
  assert keymap.command(key("J")) == Ok(keymap.MoveDown)
  assert keymap.command(key("}")) == Ok(keymap.NextSlide)
  assert keymap.command(key("Enter")) == Ok(keymap.Edit)
  assert keymap.command(key("U")) == Ok(keymap.Redo)
  assert keymap.command(Key(..key("["), ctrl: True)) == Ok(keymap.ToggleCells)
  assert keymap.command(Key(..key("]"), ctrl: True)) == Ok(keymap.ToggleSlide)
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
