//// The junkslides editor on a deck kept in the page: no server, no files,
//// edits that last as long as the page. `just site` builds it with the
//// showcase deck into `docs/`. The deck comes from `junkslides_demo/deck`,
//// a module `junkslides demo-module` writes before the build.

import gleam/list
import gleam/result
import junkslides/protocol
import junkslides/shade
import junkslides_client/app
import junkslides_client/local
import junkslides_client/ui
import junkslides_demo/deck
import lustre

pub fn main() -> Nil {
  let greeting =
    list.filter_map(deck.greeting, fn(text) {
      protocol.decode_server(text) |> result.replace_error(Nil)
    })
  let rules = shade.Rules(deck.keywords, deck.comments, deck.simple)
  let assert Ok(#(page, greeting)) = local.start(greeting, deck.marks, rules)
  let assert Ok(_) =
    lustre.application(app.init, app.update, ui.view)
    |> lustre.start("#app", app.Standalone(page, greeting))
  Nil
}
