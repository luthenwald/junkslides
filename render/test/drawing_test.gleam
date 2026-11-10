import gleam/list
import junkslides/drawing
import simplifile

pub fn drawings_start_at_their_svg_test() {
  assert drawing.safe(
      "<?xml version=\"1.0\"?>\n<!-- made by hand -->\n<svg viewBox=\"0 0 10 10\"><path class=\"edge\" d=\"M0,0 H10\"/><use href=\"#a\"/></svg>\n",
    )
    == Ok(
      "<svg viewBox=\"0 0 10 10\"><path class=\"edge\" d=\"M0,0 H10\"/><use href=\"#a\"/></svg>\n",
    )
  // Text that only mentions such words is fine.
  let assert Ok(_) =
    drawing.safe("<svg><text>the condition on x, once = 1</text></svg>")
  let assert Ok(_) =
    drawing.safe(
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
      let assert Error(_) = drawing.safe(svg)
    },
  )
}

/// A browser ends an attribute at a `/`, at any of its five spaces, or at
/// the quote before it, so a handler is one whatever comes before its name.
pub fn a_handler_is_found_whatever_separates_it_test() {
  list.each(
    [
      "<svg/onload=alert(1)>",
      "<svg><rect width=\"1\"onclick=\"x()\"/></svg>",
      "<svg><rect width='1'onclick=x() /></svg>",
      "<svg><set attributeName=\"x\"onbegin=\"x()\"/></svg>",
      "<svg\ronload=alert(1)></svg>",
      "<svg\u{c}onload=alert(1)></svg>",
      "<svg><image href=\"#\"/onerror=x()></svg>",
      "<svg><g ONLOAD=x()></g></svg>",
      "<svg><g title=\">\" onclick=x()></g></svg>",
      "<svg></g onclick=x()></svg>",
    ],
    fn(svg) {
      assert drawing.safe(svg) == Error("it has event handler attributes")
    },
  )
}

/// Only what a drawing is made of gets through, read as a page reads it.
pub fn markup_that_is_not_a_drawings_is_refused_test() {
  list.each(
    [
      // Elements of a page end the drawing and are read by its rules.
      "<svg><img src=\"#\"></svg>",
      "<svg><meta http-equiv=\"refresh\" content=\"0; url=//x\"></svg>",
      "<svg><p>text</p></svg>",
      "<svg></p><form></form></svg>",
      "<svg><embed></svg>",
      "<svgx></svgx>",
      // A link that is animated into being, also with its name as entities.
      "<svg><a href=\"#a\"><set attributeName=\"href\" to=\"&#106;avascript:x()\"/></a></svg>",
      "<svg><a><animate attributeName=\"xlink:href\" values=\"x\"/></a></svg>",
      "<svg><a href=\"&#106;avascript:x()\">a</a></svg>",
      "<svg><image src=\"a.png\"/></svg>",
      "<svg><rect style=\"fill: image-set('//x/y' 1x)\"/></svg>",
      // A title or description is read as a page, so it holds text only.
      "<svg><title><style><a title=\"</style><img src onerror=x()>\"></style></title></svg>",
      "<svg><desc><b>bold</b></desc></svg>",
      // Where a browser and this check could disagree on what is text.
      "<svg><desc><![CDATA[ > <img src onerror=x()> ]]></desc></svg>",
      "<svg><style><![CDATA[ a > b { fill: red } ]]></style></svg>",
      "<svg><!--> <img src onerror=x()> --></svg>",
      "<svg><!-- a --!> <img src onerror=x()> --></svg>",
      "<svg><?php x ?></svg>",
      "<svg><!DOCTYPE x></svg>",
      "<svg><rect width=\"1></svg>",
      "<svg><rect =x /></svg>",
      "<svg><text>a\u{0}b</text></svg>",
    ],
    fn(svg) {
      let assert Error(_) = drawing.safe(svg)
    },
  )
}

/// Drawings as people and programs write them still go in.
pub fn ordinary_drawings_pass_test() {
  list.each(
    [
      "<SVG viewBox=\"0 0 1 1\"><Path D=\"M0,0\"/></SVG>",
      "<svg><rect x=\"1\"y=\"2\"/><circle r=1 /></svg>",
      "<svg><title id=\"t\">a < b, once</title><desc>plain</desc><title/></svg>",
      "<svg><!-- a note, with <b> and onload= in it --><g/></svg>",
      "<svg><style><![CDATA[ .cls-1 { fill: none; stroke: url(#g); } ]]></style></svg>",
      "<svg><text>1 < 2 and on = off</text></svg>",
      "<svg xmlns:sodipodi=\"x\"><sodipodi:namedview pagecolor=\"#fff\"/><metadata><rdf:RDF><cc:Work rdf:about=\"\"/></rdf:RDF></metadata></svg>",
      "<svg><defs><filter id=\"f\"><feGaussianBlur stdDeviation=\"2\"/></filter><linearGradient id=\"g\"><stop offset=\"0\"/></linearGradient></defs><rect filter=\"url(#f)\"/></svg>",
      "<svg><circle r=\"1\"><animate attributeName=\"opacity\" values=\"0;1\" dur=\"2s\" repeatCount=\"indefinite\"/></circle></svg>",
      "<svg><a href=\"#top\"><text>up</text></a><use xlink:href=\"#a\"/></svg>",
      "<svg><path style=\"--i: 2; stroke-dasharray: 1\" pathLength=\"1\" data-once=\"x\"/></svg>",
    ],
    fn(svg) {
      assert drawing.safe(svg) == Ok(svg)
    },
  )
  // The showcase's own drawings.
  list.each(["folder.svg", "rebase.svg"], fn(name) {
    let assert Ok(svg) = simplifile.read("../examples/showcase/assets/" <> name)
    let assert Ok(_) = drawing.safe(svg)
  })
}
