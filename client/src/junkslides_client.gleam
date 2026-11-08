//// The junkslides editor in the browser (05-editor.md). It is served by
//// `junkslides serve` as /.js/junkslides_client.js and mounted on `#app`.

import junkslides_client/app
import junkslides_client/ui
import lustre

pub fn main() -> Nil {
  let assert Ok(_) =
    lustre.application(app.init, app.update, ui.view)
    |> lustre.start("#app", Nil)
  Nil
}
