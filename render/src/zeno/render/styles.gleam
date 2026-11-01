//// The stylesheets of a drawn slide. `base_css` is the slide's structure and
//// quiet looks, for the editor (served as `/.zeno/base.css`) and for export.
//// `page_css` is what an exported page adds to it.

/// Zero specificity, so that any rule in theme.css wins.
pub const base_css =
  "/* The slide's structure (04-layout.md, Theme contract). Zero specificity,
   so that any rule in theme.css wins. */
:where(.zeno-slide) {
  position: relative;
  box-sizing: border-box;
  width: 1920px;
  height: 1080px;
  display: grid;
  grid-template: repeat(18, 60px) / repeat(32, 60px);
  background: #fff;
  overflow: visible;
}

:where(.zeno-body) {
  grid-area: 2 / 2 / 18 / 32;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

:where(.zeno-cell) {
  min-width: 0;
}

/* The indentation of a continued line, kept from the source. */
:where(.zeno-indent) {
  white-space: pre;
}

/* Code tokens by weight, slant and shade. The shades are of the text's own
   colour, so they read on a theme's background, light or dark. */
:where(.zeno-tok-keyword, .zeno-tok-function) {
  font-weight: 600;
}

:where(.zeno-tok-comment) {
  color: color-mix(in srgb, currentColor 55%, transparent);
  font-style: italic;
}

:where(.zeno-tok-string) {
  color: color-mix(in srgb, currentColor 75%, transparent);
}

:where(.zeno-tok-number, .zeno-tok-constant) {
  color: color-mix(in srgb, currentColor 85%, transparent);
}

:where(.zeno-tok-type, .zeno-tok-constructor, .zeno-tok-module) {
  color: color-mix(in srgb, currentColor 70%, transparent);
}

:where(.zeno-tok-operator, .zeno-tok-punctuation) {
  color: color-mix(in srgb, currentColor 50%, transparent);
}

:where(.zeno-page) {
  position: absolute;
  right: 60px;
  bottom: 36px;
  font-size: 20px;
  line-height: 1;
  color: #999;
  font-variant-numeric: tabular-nums;
}

:where(.zeno-cell) > :first-child {
  margin-top: 0;
}

:where(.zeno-cell) > :last-child {
  margin-bottom: 0;
}

:where(.zeno-cell img) {
  max-width: 100%;
}

:where(.zeno-cell a) {
  color: inherit;
}

:where(.zeno-cell[data-align=\"start\"]) {
  text-align: start;
}

:where(.zeno-cell[data-align=\"center\"]) {
  text-align: center;
}

:where(.zeno-cell[data-align=\"end\"]) {
  text-align: end;
}

/* Tables: a semibold header over one firm rule, faint hairlines between rows.
   In `em` and shades of the text's own colour, so they follow variants and
   read on a theme's background, light or dark. A table is as wide as its
   content and its outer columns sit flush with the cell's text. */
:where(.zeno-cell table) {
  border-collapse: collapse;
  max-width: 100%;
  font-variant-numeric: tabular-nums lining-nums;
}

:where(.zeno-cell th, .zeno-cell td) {
  padding: 0.4em 1.2em;
  text-align: start;
  vertical-align: baseline;
}

:where(.zeno-cell th:first-child, .zeno-cell td:first-child) {
  padding-inline-start: 0;
}

:where(.zeno-cell th:last-child, .zeno-cell td:last-child) {
  padding-inline-end: 0;
}

:where(.zeno-cell th) {
  font-weight: 600;
  border-bottom: 0.07em solid color-mix(in srgb, currentColor 80%, transparent);
}

:where(.zeno-cell tbody tr + tr td) {
  border-top: 0.03em solid color-mix(in srgb, currentColor 15%, transparent);
}

:where(.zeno-cell th[data-align=\"center\"], .zeno-cell td[data-align=\"center\"]) {
  text-align: center;
}

:where(.zeno-cell th[data-align=\"end\"], .zeno-cell td[data-align=\"end\"]) {
  text-align: end;
}

/* A cell's own alignment places the table; its columns keep their own. */
:where(.zeno-cell[data-align=\"center\"] table) {
  margin-inline: auto;
}

:where(.zeno-cell[data-align=\"end\"] table) {
  margin-inline-start: auto;
}
"

/// An exported page without any script (04-layout.md, Export): every slide fills
/// a frame the height of the window, scaled to fit and clipped at its edges.
/// Frames snap, so keys that scroll step from slide to slide. Printed, each
/// slide is a page of its own at its full size.
pub const page_css =
  "html, body {
  margin: 0;
  padding: 0;
}

html {
  background: #000;
  scroll-snap-type: y mandatory;
}

.zeno-frame {
  position: relative;
  height: 100vh;
  overflow: hidden;
  container-type: size;
  scroll-snap-align: start;
  scroll-snap-stop: always;
}

.zeno-frame > .zeno-slide {
  position: absolute;
  left: 50%;
  top: 50%;
  translate: -50% -50%;
  scale: min(100cqw / 1920px, 100cqh / 1080px);
  overflow: hidden;
}

@page {
  size: 1920px 1080px;
  margin: 0;
}

@media print {
  html {
    background: none;
    scroll-snap-type: none;
  }

  .zeno-frame {
    width: 1920px;
    height: 1080px;
    container-type: normal;
    break-after: page;
  }

  .zeno-frame:last-child {
    break-after: auto;
  }

  .zeno-frame > .zeno-slide {
    position: relative;
    left: 0;
    top: 0;
    translate: none;
    scale: none;
    print-color-adjust: exact;
  }
}
"
