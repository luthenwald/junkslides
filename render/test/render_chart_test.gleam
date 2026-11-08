import gleam/dict
import gleam/list
import gleam/option
import gleam/string
import junkslides/render
import junkslides/render/chart
import lustre/element
import simplifile

const fixtures = "test/fixtures/charts/"

fn fixture(name: String) -> String {
  let assert Ok(text) = simplifile.read(fixtures <> name)
  text
}

fn render(source: String, figures: List(#(String, String))) -> String {
  render.body(source, render.context(dict.new(), dict.from_list(figures), "s"))
  |> list.map(element.to_string)
  |> string.concat
}

fn count(haystack: String, needle: String) -> Int {
  list.length(string.split(haystack, needle)) - 1
}

pub fn the_talks_charts_decode_test() {
  let assert Ok(names) = simplifile.read_directory(fixtures)
  let kinds =
    names
    |> list.sort(string.compare)
    |> list.map(fn(name) {
      case chart.decode(fixture(name)) {
        Ok(chart.Lines(..)) -> #(name, "lines")
        Ok(chart.Dots(..)) -> #(name, "dots")
        Ok(chart.Stacked(..)) -> #(name, "stacked")
        Ok(chart.Bars(..)) -> #(name, "bars")
        Error(why) -> #(name, why)
      }
    })
  assert list.length(kinds) == 11
  assert list.filter(kinds, fn(pair) { pair.1 == "lines" }) |> list.length == 9
  assert list.key_find(kinds, "speedup.json") == Ok("dots")
  assert list.key_find(kinds, "kill-rate.json") == Ok("stacked")
  let assert Ok(chart.Lines(grid:, ..)) =
    chart.decode(fixture("heuristics-stats.json"))
  let assert option.Some(chart.Grid(rows:, ..)) = grid
  assert rows == ["inspected paths", "formula size", "z3 queries"]
}

pub fn bars_and_bad_specs_test() {
  let bars =
    "{\"kind\": \"bars\", \"log\": true, \"groups\": [{\"label\": \"memberOf\", \"note\": \"n = 4\", \"rows\": [{\"label\": \"paths\", \"value\": 2040, \"now\": true}, {\"label\": \"after\", \"value\": 1}]}]}"
  let assert Ok(chart.Bars(log: True, groups: [group])) = chart.decode(bars)
  assert list.length(group.rows) == 2
  let assert Error(_) = chart.decode("{\"kind\": \"pie\"}")
  let assert Error(_) = chart.decode("not json")
}

/// The values the hand-made deck's charts.js gives for the same ranges.
pub fn ticks_match_the_talks_script_test() {
  assert chart.log_ticks(0.0123, 4567.0) == [0.1, 1.0, 10.0, 100.0, 1000.0]
  assert chart.log_ticks(0.3, 40.0) == [0.5, 1.0, 2.0, 5.0, 10.0, 20.0]
  assert chart.log_ticks(2.0, 9.0) == [2.0, 5.0]
  assert chart.log_ticks(0.0001, 0.07) == [0.0001, 0.001, 0.01]
  assert chart.linear_ticks(0.0, 1.0) == [0.0, 0.25, 0.5, 0.75, 1.0]
  assert chart.linear_ticks(0.0, 37.0) == [0.0, 10.0, 20.0, 30.0]
  assert chart.linear_ticks(3.0, 1234.0) == [500.0, 1000.0]
  assert chart.linear_ticks(0.1, 0.73) == [0.2, 0.4, 0.6]
  assert chart.compact(1500.0) == "1.5K"
  assert chart.compact(2_000_000.0) == "2M"
  assert chart.compact(0.5) == "0.5"
  assert chart.thousands(2040.0) == "2,040"
  assert chart.thousands(1_234_567.0) == "1,234,567"
  assert chart.thousands(2.5) == "2.5"
}

pub fn charts_are_drawn_from_their_spec_test() {
  let source = "![Time per program](data/micro-loops.json)"
  let html =
    render(source, [#("data/micro-loops.json", fixture("micro-loops.json"))])
  assert string.starts_with(
    html,
    "<div aria-label=\"Time per program\" class=\"js-figure\" data-figure=\"chart\" role=\"img\"",
  )
  assert string.contains(html, "<div class=\"js-chart\" data-kind=\"lines\">")
  assert string.contains(html, "<svg")
  assert string.contains(html, "viewBox=\"0 0 ")
  // Without a grid there is no switch, and one row of panels.
  assert !string.contains(html, "js-chart-switch")
  assert count(html, "class=\"js-chart-row\"") == 1
  // The spec is not there yet: a quiet stand-in, not an image.
  let waiting = render(source, [])
  assert string.contains(waiting, "js-chart-missing")
  assert !string.contains(waiting, "<img")
  let broken = render(source, [#("data/micro-loops.json", "{")])
  assert string.contains(broken, "js-chart-missing")
}

pub fn the_switch_names_its_group_per_copy_test() {
  let source = "![Statistics](data/heuristics-stats.json)"
  let figures = [
    #("data/heuristics-stats.json", fixture("heuristics-stats.json")),
  ]
  let html = render(source, figures)
  assert count(html, "type=\"radio\"") == 3
  assert count(html, "checked") == 1
  assert count(html, "class=\"js-chart-row\"") == 3
  assert string.contains(html, "name=\"js-chart-s-data/heuristics-stats.json\"")
  // The probes' copy has a group of its own, so checking a button in one
  // does not uncheck it in the other.
  let probe =
    render.body(
      source,
      render.context(dict.new(), dict.from_list(figures), "p"),
    )
    |> list.map(element.to_string)
    |> string.concat
  assert string.contains(
    probe,
    "name=\"js-chart-p-data/heuristics-stats.json\"",
  )
}

pub fn a_placed_chart_fills_its_box_test() {
  let spec = fixture("speedup.json")
  let flowing =
    render.body(
      "![s](s.json)",
      render.context(dict.new(), dict.from_list([#("s.json", spec)]), "s"),
    )
    |> list.map(element.to_string)
    |> string.concat
  let placed =
    render.body(
      "![s](s.json)",
      render.Context(
        ..render.context(dict.new(), dict.from_list([#("s.json", spec)]), "s"),
        box: option.Some(#(800, 400)),
      ),
    )
    |> list.map(element.to_string)
    |> string.concat
  assert string.contains(flowing, "height:800px")
  assert !string.contains(placed, "height:800px")
  assert flowing != placed
}
