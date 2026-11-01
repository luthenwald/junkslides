import gleam/option.{None, Some}
import simplifile
import support/fixture.{cell, slide}
import zeno/deck.{Notes, Position}
import zeno/dialect
import zeno/file
import zeno/id
import zeno/layout.{Area, Center}
import zeno/op
import zeno/protocol.{
  Apply, ApplyLayout, Diagnostic, Export, Hello, Notice, Redo, Rejected,
  ReloadTheme, SaveView, State, Undo, View,
}

pub fn client_messages_round_trip_test() {
  let #(deck, _) = fixture.deck()
  let a = cell(deck, 0, 0)
  let s = slide(deck, 1)
  let at = Position(s.id, 1)
  let ops = [
    op.EditText(a.id, "new \"text\"\nwith ü"),
    op.Insert(at, Notes),
    op.Delete(a.id),
    op.Split(a.id, 3),
    op.MergeWithNext(a.id),
    op.Move(a.id, at),
    op.Duplicate(a.id),
    op.CycleKind(a.id),
    op.Paste(a, at),
    op.InsertBreak(at),
    op.RemoveBreak(s.id),
    op.MoveSlide(s.id, 0),
    op.DeleteSlide(s.id),
  ]
  let messages = [
    Hello,
    Apply(7, ops),
    ApplyLayout(8, layout.Place(a.id, Area(-40, 0, 1920, 1080))),
    ApplyLayout(9, layout.Unplace(a.id)),
    ApplyLayout(10, layout.SetVariant(a.id, Some("large"))),
    ApplyLayout(11, layout.SetVariant(a.id, None)),
    ApplyLayout(12, layout.SetAlign(a.id, Some(Center))),
    ApplyLayout(13, layout.PurgeOrphans),
    Undo,
    Redo,
    Export,
    SaveView(View(55, True, False, 0)),
  ]
  check_client(messages)
}

fn check_client(messages) {
  case messages {
    [] -> Nil
    [msg, ..rest] -> {
      assert protocol.decode_client(protocol.encode_client(msg)) == Ok(msg)
      check_client(rest)
    }
  }
}

pub fn server_messages_round_trip_test() {
  let assert Ok(text) = simplifile.read("../examples/talk/deck.md")
  let assert Ok(#(deck, _)) = file.parse(text, id.test_supply(1))
  let assert Ok(json) = simplifile.read("../examples/talk/layout.json")
  let assert Ok(layout) = file.parse_layout(json)
  let a = cell(deck, 0, 0)
  let state =
    State(
      3,
      deck,
      layout,
      [
        Diagnostic(a.id, [
          dialect.ExtraUsed,
          dialect.BulletSpelling,
          dialect.TableShape,
        ]),
      ],
      ["large", "small"],
      protocol.default_view,
    )
  let messages = [
    state,
    Rejected(4, "unknown cell"),
    Notice("line 3"),
    ReloadTheme,
    protocol.Highlights([
      protocol.Highlight(protocol.CodeBlock("hs", "main = \"<\"\n"), [
        protocol.Token(option.None, "main "),
        protocol.Token(option.Some("punctuation.bracket"), "="),
      ]),
    ]),
  ]
  check_server(messages)
}

fn check_server(messages) {
  case messages {
    [] -> Nil
    [msg, ..rest] -> {
      assert protocol.decode_server(protocol.encode_server(msg)) == Ok(msg)
      check_server(rest)
    }
  }
}

pub fn diagnostics_test() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  let assert Ok(#(deck, _, _)) =
    op.apply(deck, op.EditText(a.id, "* star"), supply)
  assert protocol.diagnostics(deck)
    == [Diagnostic(a.id, [dialect.BulletSpelling])]
}

pub fn unknown_messages_are_errors_test() {
  let assert Error(_) = protocol.decode_client("{\"type\": \"nope\"}")
  let assert Error(_) =
    protocol.decode_client(
      "{\"type\": \"apply\", \"seq\": 1, \"ops\": [{\"op\": \"nope\"}]}",
    )
  let assert Error(_) = protocol.decode_server("{\"type\": \"nope\"}")
}
