# 03/10 Data model

Everything in this document lives in the `core` package: pure, target-agnostic
Gleam, used by both the server and the client.

The type sketches below are a specification written in Gleam notation. They
fix names and shapes; the implementation may refine details (for example
adding fields) but must keep the guarantees described here.

## Identity

```gleam
pub type CellTag
pub type SlideTag

/// Opaque: only the ids module can create or parse an Id.
/// The phantom tag keeps cell IDs and slide IDs apart.
pub opaque type Id(tag) {
  Id(uuid: String)
}

/// A source of fresh IDs, passed in so the core stays pure.
/// Production: backed by UUIDv7 generation. Tests: deterministic.
pub opaque type IdSupply
```

Guarantees from the types:

- IDs cannot be forged or typed by hand (opaque type).
- A slide ID can never be used where a cell ID is expected (phantom tag).

Guarantees that the types cannot give, enforced by laws instead (see below):
uniqueness of IDs, and honesty of the effects an operation reports.

## Deck

```gleam
pub type Kind {
  Content
  Notes
}

pub type Cell {
  Cell(id: Id(CellTag), kind: Kind, source: String)
}

pub type Slide {
  Slide(id: Id(SlideTag), cells: List(Cell))
}

pub type Deck {
  Deck(slides: List(Slide))
}

pub type Position {
  /// Index among the slide's cells, 0 to length inclusive.
  Position(slide: Id(SlideTag), index: Int)
}
```

Invariants of every deck:

1. At least one slide.
2. All IDs (cell and slide) are distinct.
3. No cell source contains a structural line (02-file-format.md).
4. Cell sources have no leading or trailing blank lines.

Empty slides and empty cells are allowed.

## Operations

```gleam
pub type Op {
  EditText(cell: Id(CellTag), source: String)
  Insert(at: Position, kind: Kind)
  Delete(cell: Id(CellTag))
  Split(cell: Id(CellTag), at: Int)
  MergeWithNext(cell: Id(CellTag))
  Move(cell: Id(CellTag), to: Position)
  Duplicate(cell: Id(CellTag))
  CycleKind(cell: Id(CellTag))
  Paste(cell: Cell, at: Position)
  InsertBreak(at: Position)
  RemoveBreak(slide: Id(SlideTag))
  MoveSlide(slide: Id(SlideTag), to_index: Int)
  DeleteSlide(slide: Id(SlideTag))
}
```

| Op | Meaning and preconditions |
|---|---|
| `EditText` | Replace the source. Must already be normalised (see below) |
| `Insert` | New empty cell of the given kind at the position |
| `Delete` | Remove the cell. Cut in the editor is `Delete` plus a client-side clipboard copy |
| `Split` | Split the source at grapheme index `at`. The first part keeps the cell; the second part becomes a new cell right after it, same kind. Blank lines at the cut are trimmed |
| `MergeWithNext` | Append the next cell of the same slide to this one, joined by a blank line. Error if it is the last cell of its slide (crossing slides is `RemoveBreak`) |
| `Move` | Move the cell to a position, in the same or another slide. The index is interpreted after removal |
| `Duplicate` | Insert a copy right after the cell |
| `CycleKind` | Content to notes, notes to content |
| `Paste` | Insert a cell carried by the clipboard. See paste rule below |
| `InsertBreak` | Start a new slide at the position: cells at index and after move to a new slide that follows |
| `RemoveBreak` | Append the slide's cells to the previous slide and retire the slide. Error for the first slide |
| `MoveSlide` | Reorder slides |
| `DeleteSlide` | Remove the slide and all its cells. Error if it is the only slide |

### The paste rule

A paste reuses the cell's ID if and only if that ID is not live in the deck.

- Cut then paste: the ID was retired by the cut, so it is reused. The cell's
  layout record comes back from the orphans. This is a move.
- Copy then paste: the ID is still live, so the pasted cell gets a fresh ID and
  inherits the original's style. This is a copy.
- Pasting the same cut twice: the first paste revives the ID, the second sees
  it live and gets a fresh one.

The same rule covers cut and paste in an outside text editor: a marker that
disappears and later reappears revives its ID.

### Normalising edits

```gleam
pub fn normalize_edit(cell: Cell, new_source: String)
  -> Result(List(Op), EditProblem)
```

The client calls this before sending a text edit.

- A line that is exactly `---` becomes `EditText` for the part before it,
  `Split`, and `InsertBreak` before the second part. Several such lines produce
  several breaks.
- A line that is exactly a marker gives `Error(MarkerLine(line_number))`. The
  edit stays local and the cell shows the problem.
- Leading and trailing blank lines are trimmed.

## Effects

```gleam
pub type Effect {
  Fresh(cell: Id(CellTag), inherit_style: Option(Id(CellTag)))
  Retired(cell: Id(CellTag))
  Revived(cell: Id(CellTag))
  SlideFresh(slide: Id(SlideTag))
  SlideRetired(slide: Id(SlideTag))
}

pub fn apply(deck: Deck, op: Op, supply: IdSupply)
  -> Result(#(Deck, List(Effect), IdSupply), OpError)
```

Effects list only changes. A cell that keeps its ID produces no effect, even
if it moved or its text changed: its layout simply follows it.

## Identity rules

| Operation | IDs | Effects | Layout consequence |
|---|---|---|---|
| Edit text | kept | none | unchanged; overflow is re-checked |
| Cycle kind | kept | none | record kept; a notes cell is not drawn, so its record is inactive until cycled back |
| Insert | new | `Fresh(id, None)` | none; the cell flows in the body area |
| Delete / cut | retired | `Retired(id)` | record moves to orphans |
| Split | first kept, second new | `Fresh(second, Some(first))` | second inherits variant and align, not placement |
| Merge | first kept, second retired | `Retired(second)` | second's record moves to orphans |
| Move (any slide) | kept | none | record follows, placement included |
| Duplicate | original kept, copy new | `Fresh(copy, Some(original))` | copy inherits variant and align, not placement |
| Paste, ID not live | revived | `Revived(id)` | record returns from orphans |
| Paste, ID live | new | `Fresh(new, Some(id))` | inherits variant and align |
| Insert break | new slide; moved cells kept | `SlideFresh(slide)` | moved cells keep their records |
| Remove break | slide retired; its cells kept | `SlideRetired(slide)` | slide record to orphans |
| Move slide | kept | none | follows |
| Delete slide | slide and its cells retired | `SlideRetired`, `Retired` per cell | all records to orphans |
| External edit | per reading rules | computed by diffing ID sets | as above |

## Layout

```gleam
pub type Area {
  Area(col: Int, row: Int, w: Int, h: Int)
}

pub type Align {
  Start
  Center
  End
}

pub type CellRecord {
  CellRecord(place: Option(Area), variant: Option(String), align: Option(Align))
}

pub type Orphan {
  CellOrphan(id: Id(CellTag), record: CellRecord, retired_at: Timestamp)
  SlideOrphan(id: Id(SlideTag), record: SlideRecord, retired_at: Timestamp)
}

pub type Layout {
  Layout(
    cells: Dict(Id(CellTag), CellRecord),
    slides: Dict(Id(SlideTag), SlideRecord),
    orphans: List(Orphan),
  )
}

pub type LayoutOp {
  Place(cell: Id(CellTag), area: Area)
  Unplace(cell: Id(CellTag))
  SetVariant(cell: Id(CellTag), variant: Option(String))
  SetAlign(cell: Id(CellTag), align: Option(Align))
  PurgeOrphans
}

pub fn fold_effects(layout: Layout, effects: List(Effect), now: Timestamp)
  -> Layout
```

`SlideRecord` is empty in the prototype and reserved for per-slide settings.
The current time is passed in, so the core stays pure.

`fold_effects` is an exhaustive match over `Effect`:

| Effect | Layout change |
|---|---|
| `Fresh(id, None)` | nothing |
| `Fresh(id, Some(src))` | copy variant and align from `src`'s record, if any |
| `Retired(id)` | move the record, if any, to orphans with `now` |
| `Revived(id)` | move the orphan record, if any, back to `cells` |
| `SlideFresh(id)` | nothing |
| `SlideRetired(id)` | move the slide record, if any, to orphans |

`Place` validates the area against the 32x18 grid. Layout ops on a notes cell
are allowed (the record is simply inactive).

## History

```gleam
pub type History  // bounded stack of (Deck, Layout) snapshots plus redo stack

pub fn record(history: History, deck: Deck, layout: Layout) -> History
pub fn undo(history: History) -> Option(#(Deck, Layout, History))
pub fn redo(history: History) -> Option(#(Deck, Layout, History))
```

Snapshots, not inverse operations: decks are kilobytes, and snapshots are
obviously correct. Bound: 500 steps. Consecutive `EditText` ops on the same
cell within one second coalesce into one step. External edits are steps too.
A new step clears the redo stack.

## Errors

`OpError` covers: unknown cell or slide ID, position out of range, no next cell
to merge, removing the first break, deleting the only slide, an area outside
the grid, an unnormalised `EditText`. Errors never change the deck.

## Laws

These are property tests (qcheck) over random decks and random sequences of
operations. The prototype is not considered working until all of them pass.

1. Honest effects. For every op, the live cell IDs after equal the live cell
   IDs before, minus `Retired`, plus `Fresh` and `Revived`. The same for slide
   IDs with `SlideRetired` and `SlideFresh`.
2. Unique IDs. Every reachable deck has distinct IDs.
3. Invariants. Every reachable deck satisfies the four deck invariants.
4. Round trip. `parse(print(d)) == d` for every reachable deck, and
   `print(parse(print(d))) == print(d)`.
5. Undo. Undo after any op restores the previous deck and layout exactly;
   redo after undo restores the later state exactly.
6. Layout coherence. Keys of `layout.cells` are live cell IDs, keys of
   `layout.slides` are live slide IDs, and no ID is both live and orphaned.
7. Valid placement. Every stored area lies within the grid.
8. Errors are pure. An op that returns an error leaves deck and layout
   unchanged.
9. Normalisation. `normalize_edit` never produces an `EditText` whose source
   contains a structural line.
10. Paste. Cut then paste of a cell restores its ID and its layout record.
