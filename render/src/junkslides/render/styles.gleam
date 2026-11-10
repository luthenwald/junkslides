//// The stylesheets of a drawn slide. `base_css` is the slide's structure and
//// quiet looks, for the editor (served as `/.js/base.css`) and for export.
//// `page_css` is what an exported page adds to it.

/// Zero specificity, so that any rule in theme.css wins.
pub const base_css =
  "/* The slide's structure (04-layout.md, Theme contract). Zero specificity,
   so that any rule in theme.css wins. Fonts are the theme's own (D25). */
:where(.js-slide) {
  position: relative;
  box-sizing: border-box;
  width: 1920px;
  height: 1080px;
  display: grid;
  grid-template: repeat(18, 60px) / repeat(32, 60px);
  background: #fff;
  overflow: visible;
}

:where(.js-body) {
  grid-area: 2 / 2 / 18 / 32;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

:where(.js-cell) {
  min-width: 0;
}

/* The indentation of a continued line, kept from the source. */
:where(.js-indent) {
  white-space: pre;
}

/* Code tokens by weight, slant and shade. The shades are of the text's own
   colour, so they read on a theme's background, light or dark. */
:where(.js-tok-keyword, .js-tok-function) {
  font-weight: 600;
}

:where(.js-tok-comment) {
  color: color-mix(in srgb, currentColor 55%, transparent);
  font-style: italic;
}

:where(.js-tok-string) {
  color: color-mix(in srgb, currentColor 75%, transparent);
}

:where(.js-tok-number, .js-tok-constant) {
  color: color-mix(in srgb, currentColor 85%, transparent);
}

:where(.js-tok-type, .js-tok-constructor, .js-tok-module) {
  color: color-mix(in srgb, currentColor 70%, transparent);
}

:where(.js-tok-operator, .js-tok-punctuation) {
  color: color-mix(in srgb, currentColor 50%, transparent);
}

/* A figure alone in its paragraph (D29): a block as wide as the cell. A
   drawing scales to that width; the theme styles its marks by class. */
:where(.js-figure) {
  display: block;
}

:where(.js-figure > svg) {
  display: block;
  max-width: 100%;
  height: auto;
}

/* An embedded page (D29): 16:9 in the flow, the cell's box when placed. */
:where(.js-figure[data-figure=\"page\"]) {
  aspect-ratio: 16 / 9;
}

:where(.js-cell[data-placed] > .js-figure[data-figure=\"page\"]) {
  aspect-ratio: auto;
  height: 100%;
}

:where(.js-figure > iframe) {
  display: block;
  width: 100%;
  height: 100%;
  border: 0;
}

/* Charts (D29): the frame in HTML, one SVG per panel. The legend row, the x
   label and the y label have fixed sizes, the ones the renderer computes the
   panels' boxes with (`frame_*` in chart.gleam); a theme that changes them
   makes the panels scale a little. Marks are in shades of the text's own
   colour. */
:where(.js-cell[data-placed] > .js-figure[data-figure=\"chart\"]) {
  height: 100%;
}

:where(.js-chart) {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr) auto;
  row-gap: 12px;
  height: 100%;
  min-height: 0;
}

:where(.js-chart-top) {
  height: 31px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 40px;
}

:where(.js-chart-top:has(.js-chart-switch)) {
  height: 39px;
}

:where(.js-chart-top:not(:has(.js-chart-switch)):has(.js-chart-legend:empty)) {
  height: 0;
}

:where(.js-chart-legend) {
  display: flex;
  flex-wrap: wrap;
  gap: 36px;
  margin: 0;
  font-size: 22px;
}

:where(.js-chart-legend .key) {
  display: inline-flex;
  align-items: center;
  gap: 10px;
}

:where(.js-chart-legend svg) {
  width: 56px;
  height: 20px;
}

:where(.js-chart .swatch) {
  display: inline-block;
  width: 18px;
  height: 18px;
  background: color-mix(in srgb, currentColor 50%, transparent);
}

:where(.js-chart-switch) {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 19px;
}

:where(.js-chart-switch-label) {
  margin-right: 14px;
  color: color-mix(in srgb, currentColor 55%, transparent);
}

:where(.js-chart-switch input) {
  position: absolute;
  opacity: 0;
  pointer-events: none;
}

:where(.js-chart-switch label) {
  padding: 5px 16px;
  border-radius: 999px;
  cursor: pointer;
}

:where(.js-chart-switch label:has(input:checked)) {
  background: color-mix(in srgb, currentColor 12%, transparent);
}

:where(.js-chart-plots) {
  display: grid;
  min-height: 0;
}

:where(.js-chart-row) {
  display: none;
  grid-template-columns: auto minmax(0, 1fr);
  column-gap: 14px;
  min-height: 0;
}

:where(.js-chart:not(:has(.js-chart-switch)) .js-chart-row) {
  display: grid;
}

:where(.js-chart:has(.js-chart-switch > label:nth-of-type(1) > input:checked) .js-chart-row:nth-child(1)) {
  display: grid;
}

:where(.js-chart:has(.js-chart-switch > label:nth-of-type(2) > input:checked) .js-chart-row:nth-child(2)) {
  display: grid;
}

:where(.js-chart:has(.js-chart-switch > label:nth-of-type(3) > input:checked) .js-chart-row:nth-child(3)) {
  display: grid;
}

:where(.js-chart:has(.js-chart-switch > label:nth-of-type(4) > input:checked) .js-chart-row:nth-child(4)) {
  display: grid;
}

:where(.js-chart:has(.js-chart-switch > label:nth-of-type(5) > input:checked) .js-chart-row:nth-child(5)) {
  display: grid;
}

:where(.js-chart:has(.js-chart-switch > label:nth-of-type(6) > input:checked) .js-chart-row:nth-child(6)) {
  display: grid;
}

:where(.js-chart:has(.js-chart-switch > label:nth-of-type(7) > input:checked) .js-chart-row:nth-child(7)) {
  display: grid;
}

:where(.js-chart:has(.js-chart-switch > label:nth-of-type(8) > input:checked) .js-chart-row:nth-child(8)) {
  display: grid;
}

:where(.js-chart-ylabel) {
  width: 28px;
  line-height: 28px;
  font-size: 23px;
  overflow: visible;
  white-space: nowrap;
  writing-mode: vertical-rl;
  rotate: 180deg;
  text-align: center;
  align-self: center;
  font-style: italic;
}

:where(.js-chart-ylabel:empty) {
  width: 0;
}

:where(.js-chart-xlabel) {
  height: 28px;
  line-height: 28px;
  font-size: 23px;
  margin: 0;
  text-align: center;
  font-style: italic;
}

:where(.js-chart-panels) {
  display: grid;
  gap: 10px 34px;
  min-height: 0;
}

:where(.js-chart-panel) {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr);
  min-height: 0;
}

:where(.js-chart-panel h4) {
  margin: 0 0 2px;
  font-size: 25px;
  font-weight: normal;
}

:where(.js-chart-panel svg) {
  width: 100%;
  height: 100%;
}

:where(.js-chart svg text) {
  font-size: 9.5px;
  fill: color-mix(in srgb, currentColor 60%, transparent);
}

:where(.js-chart svg .tick) {
  font-size: 9px;
  fill: color-mix(in srgb, currentColor 40%, transparent);
}

:where(.js-chart .grid) {
  stroke: color-mix(in srgb, currentColor 10%, transparent);
  stroke-width: 0.8;
}

:where(.js-chart .baseline) {
  stroke: color-mix(in srgb, currentColor 22%, transparent);
  stroke-width: 0.8;
}

:where(.js-chart .wall) {
  stroke: color-mix(in srgb, currentColor 22%, transparent);
  stroke-width: 0.8;
  stroke-dasharray: 3 3;
}

:where(.js-chart .line) {
  fill: none;
  stroke: currentColor;
  stroke-width: 1.3;
  stroke-linejoin: round;
}

:where(.js-chart .dotted) {
  stroke-dasharray: 1.2 2.6;
  stroke-linecap: round;
}

:where(.js-chart .dashed) {
  stroke-dasharray: 4.5 2.5;
}

:where(.js-chart .gray) {
  --js-shade: color-mix(in srgb, currentColor 40%, transparent);
}

:where(.js-chart .mid) {
  --js-shade: color-mix(in srgb, currentColor 60%, transparent);
}

:where(.js-chart .dark) {
  --js-shade: color-mix(in srgb, currentColor 80%, transparent);
}

:where(.js-chart .line[class]) {
  stroke: var(--js-shade, currentColor);
}

:where(.js-chart .mark) {
  fill: var(--js-shade, currentColor);
  stroke: var(--js-background, #fff);
  stroke-width: 0.8;
}

:where(.js-chart .mark.open) {
  fill: var(--js-background, #fff);
  stroke: var(--js-shade, currentColor);
  stroke-width: 1;
}

:where(.js-chart .stem) {
  stroke: color-mix(in srgb, currentColor 12%, transparent);
  stroke-width: 1.6;
}

:where(.js-chart .dot) {
  fill: color-mix(in srgb, currentColor 40%, transparent);
}

:where(.js-chart .dot.best) {
  fill: currentColor;
}

:where(.js-chart .bar) {
  fill: color-mix(in srgb, currentColor 50%, transparent);
  stroke: var(--js-background, #fff);
  stroke-width: 0.5;
}

:where(.js-chart .part-1) {
  fill: color-mix(in srgb, currentColor 100%, transparent);
  background: color-mix(in srgb, currentColor 100%, transparent);
}

:where(.js-chart .part-2) {
  fill: color-mix(in srgb, currentColor 70%, transparent);
  background: color-mix(in srgb, currentColor 70%, transparent);
}

:where(.js-chart .part-3) {
  fill: color-mix(in srgb, currentColor 45%, transparent);
  background: color-mix(in srgb, currentColor 45%, transparent);
}

:where(.js-chart .part-4) {
  fill: color-mix(in srgb, currentColor 15%, transparent);
  background: color-mix(in srgb, currentColor 15%, transparent);
}

:where(.js-chart .part-5) {
  fill: color-mix(in srgb, currentColor 85%, transparent);
  background: color-mix(in srgb, currentColor 85%, transparent);
}

:where(.js-chart .part-6) {
  fill: color-mix(in srgb, currentColor 30%, transparent);
  background: color-mix(in srgb, currentColor 30%, transparent);
}

:where(.js-chart[data-kind=\"bars\"]) {
  grid-template-columns: max-content max-content 1fr;
  grid-template-rows: none;
  column-gap: 36px;
  row-gap: 14px;
  align-items: center;
  align-content: start;
  height: auto;
}

:where(.js-chart[data-kind=\"bars\"] .note) {
  color: color-mix(in srgb, currentColor 60%, transparent);
}

:where(.js-chart[data-kind=\"bars\"] .which) {
  font-style: italic;
}

:where(.js-chart[data-kind=\"bars\"] .bar) {
  display: grid;
  grid-template-columns: var(--w) auto;
  align-items: center;
  column-gap: 14px;
}

:where(.js-chart[data-kind=\"bars\"] .bar i) {
  display: block;
  height: 16px;
  background: color-mix(in srgb, currentColor 20%, transparent);
}

:where(.js-chart[data-kind=\"bars\"] .bar.now i) {
  background: currentColor;
}

:where(.js-chart[data-kind=\"bars\"] .bar b) {
  font-weight: normal;
}

:where(.js-chart[data-kind=\"bars\"] .gap) {
  grid-column: 1 / -1;
  height: 10px;
}

:where(.js-chart-missing) {
  display: grid;
  place-content: center;
  border: 0.05em dashed color-mix(in srgb, currentColor 30%, transparent);
  color: color-mix(in srgb, currentColor 60%, transparent);
}

/* A lit line of code (D28): a faint band across the block, with a rule at its
   left edge. */
:where(.js-lit) {
  display: inline-block;
  min-width: 100%;
  background: color-mix(in srgb, currentColor 7%, transparent);
  box-shadow: -0.4em 0 0 color-mix(in srgb, currentColor 7%, transparent),
    -0.55em 0 0 currentColor;
}

:where(.js-page) {
  position: absolute;
  right: 60px;
  bottom: 36px;
  font-size: 20px;
  line-height: 1;
  color: #999;
  font-variant-numeric: tabular-nums;
}

:where(.js-slide[data-number=\"off\"]) > :where(.js-page) {
  display: none;
}

:where(.js-cell) > :first-child {
  margin-top: 0;
}

:where(.js-cell) > :last-child {
  margin-bottom: 0;
}

:where(.js-cell img) {
  max-width: 100%;
}

:where(.js-cell a) {
  color: inherit;
}

:where(.js-cell[data-align=\"start\"]) {
  text-align: start;
}

:where(.js-cell[data-align=\"center\"]) {
  text-align: center;
}

:where(.js-cell[data-align=\"end\"]) {
  text-align: end;
}

/* Tables: a semibold header over one firm rule, faint hairlines between rows.
   In `em` and shades of the text's own colour, so they follow variants and
   read on a theme's background, light or dark. A table is as wide as its
   content and its outer columns sit flush with the cell's text. */
:where(.js-cell table) {
  border-collapse: collapse;
  max-width: 100%;
  font-variant-numeric: tabular-nums lining-nums;
}

:where(.js-cell th, .js-cell td) {
  padding: 0.4em 1.2em;
  text-align: start;
  vertical-align: baseline;
}

:where(.js-cell th:first-child, .js-cell td:first-child) {
  padding-inline-start: 0;
}

:where(.js-cell th:last-child, .js-cell td:last-child) {
  padding-inline-end: 0;
}

:where(.js-cell th) {
  font-weight: 600;
  border-bottom: 0.07em solid color-mix(in srgb, currentColor 80%, transparent);
}

:where(.js-cell tbody tr + tr td) {
  border-top: 0.03em solid color-mix(in srgb, currentColor 15%, transparent);
}

:where(.js-cell th[data-align=\"center\"], .js-cell td[data-align=\"center\"]) {
  text-align: center;
}

:where(.js-cell th[data-align=\"end\"], .js-cell td[data-align=\"end\"]) {
  text-align: end;
}

/* A cell's own alignment places the table; its columns keep their own. */
:where(.js-cell[data-align=\"center\"] table) {
  margin-inline: auto;
}

:where(.js-cell[data-align=\"end\"] table) {
  margin-inline-start: auto;
}
"

/// An exported page without any script (04-layout.md, Export): every slide fills
/// a frame the height of the window, scaled to fit and clipped at its edges.
/// Frames snap, so keys that scroll step from slide to slide, and the frame
/// snapped to marks its slide with `--js-here: 1`. Printed, each
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

.js-frame {
  position: relative;
  height: 100vh;
  overflow: hidden;
  container-type: size scroll-state;
  scroll-snap-align: start;
  scroll-snap-stop: always;
}

/* The slide in view, for the theme's `@container style(--js-here: 1)`. */
@container scroll-state(snapped: block) {
  .js-slide {
    --js-here: 1;
  }
}

.js-frame > .js-slide {
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

  .js-frame {
    width: 1920px;
    height: 1080px;
    container-type: normal;
    break-after: page;
  }

  .js-frame:last-child {
    break-after: auto;
  }

  .js-frame > .js-slide {
    position: relative;
    left: 0;
    top: 0;
    translate: none;
    scale: none;
    print-color-adjust: exact;
  }
}
"
