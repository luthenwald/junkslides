# 01/10 Overview

## Problem

Markdown slide tools (Marp, Slidev, reveal.js) put layout directives inside
the markdown, so content and layout are tangled. Visual tools (Keynote,
PowerPoint) keep layout well but store content in an opaque format.

Zeno keeps content as plain text and layout as a separate, remembered layer.
The hard part of that split is identity: the layout layer must keep pointing
at the right piece of content while the content changes. Inferring identity
from text diffs is fragile. Zeno avoids inference: content is edited as cells
in Zeno's own editor, every cell has a stable ID, and every operation states
what it does to IDs.

## Goals for the prototype

- Write slide content as cells in a single text file in a strict dialect.
- See each slide rendered next to the cells, and arrange cells on a grid by
  mouse or keyboard.
- Remember every layout edit across sessions, robust to content edits.
- Survive edits made to the files outside Zeno, in any text editor.
- Never lose or corrupt the user's files.

## Non-goals for the prototype

- Presenting, exporting to HTML or PDF (planned later).
- Groups of cells, free-form CSS per cell, shrink-to-fit text.
- Aspect ratios other than 16:9.
- Collaboration or multiple simultaneous users.
- A TUI client (possible later, as a second client of the same server).

## Principles

1. Content and layout have separate owners and separate files.
2. Identity is carried by operations, never inferred from text.
3. Layout follows identity: a surviving ID keeps its layout.
4. Unambiguous syntax: each construct has exactly one way to be written, and
   every cell parses on its own.
5. Markers are optional on read and always written.
6. Visible decisions: anything Zeno cannot do cleanly (overflow, invalid
   content, a failed external edit) is shown, never silently patched.
7. The files on disk are always valid. A bad external edit never causes Zeno
   to overwrite the file.
8. A pure core. All rules live in one target-agnostic package, tested by
   properties, shared by server and client.

## Glossary

| Term | Meaning |
|---|---|
| Deck | A folder holding deck.md, layout.json, theme.css and assets/ |
| Slide | A break followed by zero or more cells |
| Break | The `---` line that starts a slide; it carries the slide ID |
| Cell | A piece of dialect text with an ID and a kind; one component on a slide |
| Kind | `content` (shown on the slide) or `notes` (speaker notes, not shown) |
| Marker | An HTML comment line carrying a kind and an ID, written by Zeno |
| Op | A typed edit to the deck (insert, split, move, and so on) |
| Effect | What an op did to IDs: fresh, retired, revived |
| Layout record | The layout data stored for one cell or slide |
| Placement | A cell's explicit grid area; unplaced cells flow in the body area |
| Variant | A named style defined by the theme, such as `large` or `quiet` |
| Orphan | A layout record whose cell or slide is no longer live |
| Grid unit | One cell of the 32x18 slide grid, 60x60 px in the 1920x1080 design space |
