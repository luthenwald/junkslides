//// The stylesheets of a drawn slide. `base_css` is the slide's structure and
//// quiet looks, for the editor (served as `/.zeno/base.css`) and for export.
//// `page_css` is what an exported page adds to it.

/// Zero specificity, so that any rule in theme.css wins.
pub const base_css =
  "/* The slide's structure (04-layout.md, Theme contract). Zero specificity,
   so that any rule in theme.css wins. Fonts are the theme's own (D25). */
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

/* A figure alone in its paragraph (D29): a block as wide as the cell. A
   drawing scales to that width; the theme styles its marks by class. */
:where(.zeno-figure) {
  display: block;
}

:where(.zeno-figure > svg) {
  display: block;
  max-width: 100%;
  height: auto;
}

/* An embedded page (D29): 16:9 in the flow, the cell's box when placed. */
:where(.zeno-figure[data-figure=\"page\"]) {
  aspect-ratio: 16 / 9;
}

:where(.zeno-cell[data-placed] > .zeno-figure[data-figure=\"page\"]) {
  aspect-ratio: auto;
  height: 100%;
}

:where(.zeno-figure > iframe) {
  display: block;
  width: 100%;
  height: 100%;
  border: 0;
}

/* Charts (D29): the frame in HTML, one SVG per panel. The sizes of the
   legend row, the x label and the y label are the ones the panels' boxes are
   computed with, so a theme that changes them makes the panels scale a
   little. Marks are in shades of the text's own colour. */
:where(.zeno-cell[data-placed] > .zeno-figure[data-figure=\"chart\"]) {
  height: 100%;
}

:where(.zeno-chart) {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr) auto;
  row-gap: 12px;
  height: 100%;
  min-height: 0;
}

:where(.zeno-chart-top) {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 40px;
}

:where(.zeno-chart-legend) {
  display: flex;
  flex-wrap: wrap;
  gap: 36px;
  margin: 0;
  font-size: 22px;
}

:where(.zeno-chart-legend .key) {
  display: inline-flex;
  align-items: center;
  gap: 10px;
}

:where(.zeno-chart-legend svg) {
  width: 56px;
  height: 20px;
}

:where(.zeno-chart .swatch) {
  display: inline-block;
  width: 18px;
  height: 18px;
  background: color-mix(in srgb, currentColor 50%, transparent);
}

:where(.zeno-chart-switch) {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 19px;
}

:where(.zeno-chart-switch-label) {
  margin-right: 14px;
  color: color-mix(in srgb, currentColor 55%, transparent);
}

:where(.zeno-chart-switch input) {
  position: absolute;
  opacity: 0;
  pointer-events: none;
}

:where(.zeno-chart-switch label) {
  padding: 5px 16px;
  border-radius: 999px;
  cursor: pointer;
}

:where(.zeno-chart-switch label:has(input:checked)) {
  background: color-mix(in srgb, currentColor 12%, transparent);
}

:where(.zeno-chart-plots) {
  display: grid;
  min-height: 0;
}

:where(.zeno-chart-row) {
  display: none;
  grid-template-columns: auto minmax(0, 1fr);
  column-gap: 14px;
  min-height: 0;
}

:where(.zeno-chart:not(:has(.zeno-chart-switch)) .zeno-chart-row) {
  display: grid;
}

:where(.zeno-chart:has(.zeno-chart-switch > label:nth-of-type(1) > input:checked) .zeno-chart-row:nth-child(1)) {
  display: grid;
}

:where(.zeno-chart:has(.zeno-chart-switch > label:nth-of-type(2) > input:checked) .zeno-chart-row:nth-child(2)) {
  display: grid;
}

:where(.zeno-chart:has(.zeno-chart-switch > label:nth-of-type(3) > input:checked) .zeno-chart-row:nth-child(3)) {
  display: grid;
}

:where(.zeno-chart:has(.zeno-chart-switch > label:nth-of-type(4) > input:checked) .zeno-chart-row:nth-child(4)) {
  display: grid;
}

:where(.zeno-chart:has(.zeno-chart-switch > label:nth-of-type(5) > input:checked) .zeno-chart-row:nth-child(5)) {
  display: grid;
}

:where(.zeno-chart:has(.zeno-chart-switch > label:nth-of-type(6) > input:checked) .zeno-chart-row:nth-child(6)) {
  display: grid;
}

:where(.zeno-chart:has(.zeno-chart-switch > label:nth-of-type(7) > input:checked) .zeno-chart-row:nth-child(7)) {
  display: grid;
}

:where(.zeno-chart:has(.zeno-chart-switch > label:nth-of-type(8) > input:checked) .zeno-chart-row:nth-child(8)) {
  display: grid;
}

:where(.zeno-chart-ylabel) {
  writing-mode: vertical-rl;
  rotate: 180deg;
  text-align: center;
  align-self: center;
  font-style: italic;
}

:where(.zeno-chart-xlabel) {
  margin: 0;
  text-align: center;
  font-style: italic;
}

:where(.zeno-chart-panels) {
  display: grid;
  gap: 10px 34px;
  min-height: 0;
}

:where(.zeno-chart-panel) {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr);
  min-height: 0;
}

:where(.zeno-chart-panel h4) {
  margin: 0 0 2px;
  font-size: 25px;
  font-weight: normal;
}

:where(.zeno-chart-panel svg) {
  width: 100%;
  height: 100%;
}

:where(.zeno-chart svg text) {
  font-size: 9.5px;
  fill: color-mix(in srgb, currentColor 60%, transparent);
}

:where(.zeno-chart svg .tick) {
  font-size: 9px;
  fill: color-mix(in srgb, currentColor 40%, transparent);
}

:where(.zeno-chart .grid) {
  stroke: color-mix(in srgb, currentColor 10%, transparent);
  stroke-width: 0.8;
}

:where(.zeno-chart .baseline) {
  stroke: color-mix(in srgb, currentColor 22%, transparent);
  stroke-width: 0.8;
}

:where(.zeno-chart .wall) {
  stroke: color-mix(in srgb, currentColor 22%, transparent);
  stroke-width: 0.8;
  stroke-dasharray: 3 3;
}

:where(.zeno-chart .line) {
  fill: none;
  stroke: currentColor;
  stroke-width: 1.3;
  stroke-linejoin: round;
}

:where(.zeno-chart .dotted) {
  stroke-dasharray: 1.2 2.6;
  stroke-linecap: round;
}

:where(.zeno-chart .dashed) {
  stroke-dasharray: 4.5 2.5;
}

:where(.zeno-chart .gray) {
  --zeno-shade: color-mix(in srgb, currentColor 40%, transparent);
}

:where(.zeno-chart .mid) {
  --zeno-shade: color-mix(in srgb, currentColor 60%, transparent);
}

:where(.zeno-chart .dark) {
  --zeno-shade: color-mix(in srgb, currentColor 80%, transparent);
}

:where(.zeno-chart .line[class]) {
  stroke: var(--zeno-shade, currentColor);
}

:where(.zeno-chart .mark) {
  fill: var(--zeno-shade, currentColor);
  stroke: var(--zeno-background, #fff);
  stroke-width: 0.8;
}

:where(.zeno-chart .mark.open) {
  fill: var(--zeno-background, #fff);
  stroke: var(--zeno-shade, currentColor);
  stroke-width: 1;
}

:where(.zeno-chart .stem) {
  stroke: color-mix(in srgb, currentColor 12%, transparent);
  stroke-width: 1.6;
}

:where(.zeno-chart .dot) {
  fill: color-mix(in srgb, currentColor 40%, transparent);
}

:where(.zeno-chart .dot.best) {
  fill: currentColor;
}

:where(.zeno-chart .bar) {
  fill: color-mix(in srgb, currentColor 50%, transparent);
  stroke: var(--zeno-background, #fff);
  stroke-width: 0.5;
}

:where(.zeno-chart .part-1) {
  fill: color-mix(in srgb, currentColor 100%, transparent);
  background: color-mix(in srgb, currentColor 100%, transparent);
}

:where(.zeno-chart .part-2) {
  fill: color-mix(in srgb, currentColor 70%, transparent);
  background: color-mix(in srgb, currentColor 70%, transparent);
}

:where(.zeno-chart .part-3) {
  fill: color-mix(in srgb, currentColor 45%, transparent);
  background: color-mix(in srgb, currentColor 45%, transparent);
}

:where(.zeno-chart .part-4) {
  fill: color-mix(in srgb, currentColor 15%, transparent);
  background: color-mix(in srgb, currentColor 15%, transparent);
}

:where(.zeno-chart .part-5) {
  fill: color-mix(in srgb, currentColor 85%, transparent);
  background: color-mix(in srgb, currentColor 85%, transparent);
}

:where(.zeno-chart .part-6) {
  fill: color-mix(in srgb, currentColor 30%, transparent);
  background: color-mix(in srgb, currentColor 30%, transparent);
}

:where(.zeno-chart[data-kind=\"bars\"]) {
  grid-template-columns: max-content max-content 1fr;
  grid-template-rows: none;
  column-gap: 36px;
  row-gap: 14px;
  align-items: center;
  align-content: start;
  height: auto;
}

:where(.zeno-chart[data-kind=\"bars\"] .note) {
  color: color-mix(in srgb, currentColor 60%, transparent);
}

:where(.zeno-chart[data-kind=\"bars\"] .which) {
  font-style: italic;
}

:where(.zeno-chart[data-kind=\"bars\"] .bar) {
  display: grid;
  grid-template-columns: var(--w) auto;
  align-items: center;
  column-gap: 14px;
}

:where(.zeno-chart[data-kind=\"bars\"] .bar i) {
  display: block;
  height: 16px;
  background: color-mix(in srgb, currentColor 20%, transparent);
}

:where(.zeno-chart[data-kind=\"bars\"] .bar.now i) {
  background: currentColor;
}

:where(.zeno-chart[data-kind=\"bars\"] .bar b) {
  font-weight: normal;
}

:where(.zeno-chart[data-kind=\"bars\"] .gap) {
  grid-column: 1 / -1;
  height: 10px;
}

:where(.zeno-chart-missing) {
  display: grid;
  place-content: center;
  border: 0.05em dashed color-mix(in srgb, currentColor 30%, transparent);
  color: color-mix(in srgb, currentColor 60%, transparent);
}

/* A lit line of code (D28): a faint band across the block, with a rule at its
   left edge. */
:where(.zeno-lit) {
  display: inline-block;
  min-width: 100%;
  background: color-mix(in srgb, currentColor 7%, transparent);
  box-shadow: -0.4em 0 0 color-mix(in srgb, currentColor 7%, transparent),
    -0.55em 0 0 currentColor;
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
  scrollbar-width: none;
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
