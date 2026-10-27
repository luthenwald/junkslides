# 10/10 References

Related work and reading that informed the design, grouped by theme. Links are
given only where the address is known to be stable; otherwise search by name.

## Markup

- Djot, John MacFarlane's redesign of markdown, and its design goals:
  https://github.com/jgm/djot (see also the quickstart for markdown users in
  its doc folder).
- John MacFarlane, "Beyond Markdown": the essay that motivated djot.
- CommonMark, for the ambiguities Zeno's dialect avoids (setext headings,
  thematic breaks, indented code).

## Identity and anchoring

- W3C Web Annotation Data Model: text quote and text position selectors, the
  standard way to anchor annotations to changing documents.
- Hypothesis (web annotation tool): fuzzy re-anchoring in practice.
- Patience diff (Bram Cohen) and git's similarity-based rename detection.
- Jupyter notebook format: cell IDs were added in nbformat 4.5.
- RFC 9562, Universally Unique IDentifiers (UUIDv7):
  https://www.rfc-editor.org/rfc/rfc9562

## Structure editing

- Projectional editing, JetBrains MPS.
- The Cornell Program Synthesizer (Teitelbaum and Reps, 1981).
- Hazel (Cyrus Omar and others): structure editing with holes.
- ProseMirror's document model: steps with position mapping.
- CRDTs such as Automerge and Yjs: per-element identity, moves and splits.
- Operational transformation, for rebasing operations onto changed documents.

## Bidirectional programming

- Lenses and the Boomerang language (Foster, Pierce and others): a view, a
  source and a complement. The layout file is Zeno's complement.
- Sketch-n-Sketch (Ravi Chugh and others): direct manipulation of output
  reflected back into the program.

## Layout

- CSS Grid Layout, especially the auto-placement algorithm.
- CSS Cascade Layers (`@layer`), for theme and override ordering at export.
- Cassowary constraint solver (Badros, Borning, Stuckey), behind Apple's Auto
  Layout: relevant if layouts ever become relative.

## Slide tools

- iA Presenter: text first, design separate; closest in spirit.
- Marp, Slidev, reveal.js: layout directives inside markdown, the counterpoint.

## Files and durability

- Dan Luu, "Files are hard", and writing on POSIX `rename` atomicity and
  `fsync`.

## Types

- Linear and uniqueness types (Clean, Linear Haskell, Austral): the type-level
  way to forbid duplicating an ID, which Zeno checks by laws instead.

## Gleam ecosystem

- Lustre: https://hexdocs.pm/lustre/
- jot: https://hexdocs.pm/jot/
- youid: https://hexdocs.pm/youid/
- qcheck: https://hexdocs.pm/qcheck/
- polly: https://hexdocs.pm/polly/
