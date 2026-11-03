import gleam/list
import zeno_server/figures

pub fn drawings_start_at_their_svg_test() {
  assert figures.drawing(
      "<?xml version=\"1.0\"?>\n<!-- made by hand -->\n<svg viewBox=\"0 0 10 10\"><path class=\"edge\" d=\"M0,0 H10\"/><use href=\"#a\"/></svg>\n",
    )
    == Ok(
      "<svg viewBox=\"0 0 10 10\"><path class=\"edge\" d=\"M0,0 H10\"/><use href=\"#a\"/></svg>\n",
    )
  // Text that only mentions such words is fine.
  let assert Ok(_) =
    figures.drawing("<svg><text>the condition on x, once = 1</text></svg>")
  let assert Ok(_) =
    figures.drawing(
      "<svg><style>.a { fill: url(#g) }</style><rect style=\"fill: url('#g')\"/></svg>",
    )
}

pub fn drawings_that_could_run_or_load_are_refused_test() {
  list.each(
    [
      "<svg><script>alert(1)</script></svg>",
      "<svg onload=\"alert(1)\"></svg>",
      "<svg>\n<rect\n  onclick = 'x()'/></svg>",
      "<svg><a href=\"javascript:x()\">a</a></svg>",
      "<svg><image href=\"https://example.com/a.png\"/></svg>",
      "<svg><use xlink:href='other.svg#a'/></svg>",
      "<svg><foreignObject><div/></foreignObject></svg>",
      "<svg><style>@import 'x.css';</style></svg>",
      "<svg><rect style=\"fill: url(http://x/y)\"/></svg>",
      "<!DOCTYPE svg [<!ENTITY x \"y\">]><svg/>",
      "<svg><style>.a { fill: url(http://x/y) }</style></svg>",
      "<p>not a drawing</p>",
    ],
    fn(svg) {
      let assert Error(_) = figures.drawing(svg)
    },
  )
}
