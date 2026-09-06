# SwiftMIDIcurator

An iOS/macOS **AUv3 MIDI processor** (`aumi MdCr`) that holds a library of MIDI
clips, plays one at a time, and records what you thought of it — in passes, not
scores.

The fifth plug-in on [`enkerli-swift`](https://github.com/Enkerli/enkerli-swift),
and the one where the foundation pays off hardest. It is worth being specific
about that rather than claiming it, because [PORTING.md
§6](https://github.com/Enkerli/MelGen/blob/main/PORTING.md) rated this plug-in
**"engine cheap, UI is the plug-in. Wrong shape for a SwiftUI rewrite"** — and
that verdict was correct when it was written. What changed is that MelGen needed
a curation panel, the panel was built as foundation, and the interface this
plug-in would have had to write is now a shared target.

So it exists as about **a thousand lines**, of which none is a disposition
vocabulary, a tag folksonomy, a MIDI file reader, a piano roll or a review row.

It is **not** the JUCE [MIDIcurator](https://github.com/Enkerli/MIDIcurator).
That one is `aumi Mcur`. This one has a different four-character code *and* a
different bundle identifier, so both can be installed at once — see
`Scripts/tests/component-identity.py` for why the second of those is the one
that bites.

## The model, which is not this plug-in's

Curation here is **passes, not scores**, and every part of that comes from
`Carrier`:

- A judgement is a **disposition**, not a rating. Seven of them — *keep, tweak,
  again, elsewhere, partly, later, skip* — and none is terminal. `keep` and
  `tweak` are different next actions, not better and worse.
- A judgement belongs to a **pass**. Marks from different passes coexist, so a
  clip you skipped on the first sweep and kept on the third records a
  *disagreement* rather than a correction. That disagreement is the most
  interesting thing in the record and collapsing it into an average would throw
  it away.
- Nothing is deleted. A skip means "last, this pass", not "gone".
- **Facets are derived, tags are typed.** Density, placement, register, colour
  and motion are measured off the notes; everything else is free text, and the
  vocabulary that emerges is offered back to you.

None of that is implemented here. It is `Carrier`'s `TakeDisposition`,
`CurationMark`, `TakeFacetting` and `TagVocabulary`, and it is checked in the
foundation's own suite.

## What it does

**Imports `.mid` files.** `Carrier`'s reader finds the notes, and finds harmony
four ways — the file's own leadsheet payload, chord markers, a chord track, or
not at all. Which of the four it was is kept and shown, because *"we read the
changes"* and *"we guessed the changes"* are different claims about the same
clip.

**Plays one clip at a time**, through the same kernel MelGen schedules with, with
**play and host sync on screen** — the first plug-in in the suite to surface
those at all.

**Puts a clip in front of you and asks.** Three answers by default, seven behind
a disclosure. Answering advances to the next clip this pass has not reached, so
a sweep drains rather than loops.

**Orders the queue by what you deferred, not by what you liked.** Deferred first,
then unheard, then settled, then skipped — `TakeDisposition.reviewPriority`,
which is the foundation's order and not this plug-in's. A second sweep over the
discards is where the surprises are.

**Recognises a file it already has**, on pitch and start beat rather than on the
name, and refuses to import it twice — because the marks are the valuable half
and the notes are the cheap half.

## Where the library lives, and why that is a decision

Everything else persists through the audio unit's `fullState`, which belongs to
one project in one host. The **clips do not**: they are in the extension's own
defaults, and the session holds a cursor into them.

Reopening a project puts you back where you were. Opening a different project
still has your clips. A library that vanished with the project would not be a
library.

The consequence, stated rather than discovered: two instances in the same host
share one library, and the sharing is not transactional. That is in
[GAPS.md](https://github.com/Enkerli/enkerli-swift/blob/main/GAPS.md).

## Verifying

```bash
Scripts/verify.sh            # all suites
Scripts/verify.sh curate     # one suite
```

| Suite | Checks |
|---|---|
| `identity` | The component triple **and the bundle identifier** are unique across every sibling checkout, JUCE and Swift alike. First, because both are forever and this project was scaffolded from SwiftPitchFold's |
| `curate` | How a file becomes a clip, what counts as the same clip twice, what order the queue is in, and that a pass-1 skip survives a pass-2 keep |
| `kernel` | The foundation package's own check, run from here — what the render thread does with a committed sequence |
| `gaps` | Likewise: this plug-in has to have a section in the shared register or the run fails |

The import tests go through the real writer and the real reader —
`MIDIExport.write` then `MIDIImport.read` — rather than through a hand-built
clip. A duplicate check that only ever saw clips the test constructed would pass
happily while the reader put a different start beat on every import.

## Building

```bash
git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift
```

Then open `SwiftMIDIcurator.xcodeproj` (Xcode 27+, iOS/macOS 26.0+).
`SwiftMIDIcuratorExtension` is the plug-in; `SwiftMIDIcurator` is a host app that
loads it.

## What this plug-in is, in files

| File | Lines | What it is |
|---|---:|---|
| `Library/Clip.swift` | ~180 | A file you kept, and what you have said about it |
| `Library/CuratorState.swift` | ~230 | The library, the pass, and the queue |
| `Library/ClipImport.swift` | ~100 | Which files, and what to do with one that is already here |
| `UI/SwiftMIDIcuratorMainView.swift` | ~320 | One screen, almost none of which draws anything |
| `AudioUnit/` (3 files) | ~200 | The session half of the audio unit, three overrides, two parameters |

## What has not been done

- **None of this has been heard on a device**, and for this plug-in that matters
  more than usual: the thing being tested is whether a sweep feels like a sweep,
  which no suite can answer.
- **Harmony is only ever read, never detected.** A file with no changes gets no
  analysis at all, and the interface says so rather than inventing numbers.
- **No export.** `Carrier` has had `MIDIExport.write` the whole time and this
  plug-in does not call it outside its own tests.
- **No search, no folders, no filters.** The library is one flat list, which is
  fine for twenty clips and not for two hundred.
- **`TakeAspect` has no control.** *Which part* of a clip works is in the
  vocabulary, and `partial` is currently the one disposition of seven that
  records less than it could.

## The full register

The list above is this plug-in's. The shared gaps and the **strategy** for which
get built back — including what we have decided *not* to build — live in
[GAPS.md](https://github.com/Enkerli/enkerli-swift/blob/main/GAPS.md) in the
foundation. `Scripts/verify.sh` runs its staleness check.

**Two AU parameters, and the third left out on purpose.** `playMelody` and
`hostSync` both do something here. `playbackDirection` also works — the kernel
acts on it — and is deliberately not declared: a mark records what you heard, and
hearing a clip backwards while marking the forward one would record a judgement
of music that is not in the library. A missing control is a gap; a control that
lies is a bug.

## Licence

Public domain, all the way down. See [LICENSE](LICENSE).
