import junkslides_client/app

fn model() -> app.Model {
  let #(model, _) = app.init(Nil)
  app.Model(..model, theme: 2)
}

pub fn a_reload_shows_once_both_sheets_have_arrived_test() {
  let one = app.sheet_loaded(model(), 2)
  assert one.theme_loaded == 0
  let both = app.sheet_loaded(one, 2)
  assert both.theme_loaded == 2
}

pub fn an_older_reload_never_replaces_a_newer_one_test() {
  let shown = model() |> app.sheet_loaded(2) |> app.sheet_loaded(2)
  let late = shown |> app.sheet_loaded(1) |> app.sheet_loaded(1)
  assert late.theme_loaded == 2
}
