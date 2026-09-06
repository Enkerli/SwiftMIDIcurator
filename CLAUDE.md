# Working on SwiftMIDIcurator

*Short on purpose. This is the fifth plug-in on a shared foundation, and it is
the one with the least code of its own — so most of what you need to know is
about where the rest of it lives.*

---

## The two things that surprise everybody

**Nothing builds without the foundation checked out beside this repo.**

```bash
git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift
```

`Scripts/verify.sh` and `SwiftMIDIcurator.xcodeproj` both look in
`$REPO/../enkerli-swift`; override with `ENKERLI_SWIFT=...`. Without it every
suite fails with that line printed, which is deliberate — a suite that quietly
passed without the foundation would be checking nothing.

**Almost nothing in this repo is this plug-in.** The disposition vocabulary, the
pass model, the tag folksonomy, the facet derivation, the MIDI file reader, the
piano roll, the review row and the disposition bar are all in `enkerli-swift`.
What is here is a library, an importer, and one screen that arranges parts it did
not write. If you are about to implement curation, stop: it exists.

```bash
Scripts/verify.sh            # all suites
Scripts/verify.sh curate     # one
```

If you cannot run a terminal, say so plainly and ask for it to be run rather than
reporting a change as verified. Building both schemes is necessary and is not
sufficient.

---

## Where a change belongs

The question to ask about any new type is *would a third plug-in want this?*

| It is | Put it |
|---|---|
| Chords, scales, voice leading, progressions, rhythm algorithms | `enkerli-swift` → `Sources/Theory` |
| A pattern, a note, measurement, **anything about judging material** | → `Sources/Carrier` |
| A control any plug-in could use | → `Sources/UI` |
| AU plumbing | → `Sources/Shell` |
| A render-thread capability | `Sources/Kernel` **and** its harness in `Tests/Kernel` |
| About *a library of files* as this product sees it | here |

That second row is where this plug-in is unusual. Its whole subject — curation —
is already foundation, because MelGen needed it first. A new disposition, a new
facet, a change to how a pass works: none of those belong here, and putting one
here would fork the model MelGen and this plug-in are deliberately sharing.

Changing the foundation means changing another repo. Run *its* checks and
MelGen's `Scripts/verify.sh` too — MelGen is the other consumer of every type
this plug-in touches, and it is the one most likely to break silently.

---

## Rules that are not negotiable

**The component triple is forever.** `aumi/MdCr/Enke` — not `Mcur`, which is the
JUCE MIDIcurator's and would collide with the AUv3 that build ships. This project
was scaffolded by copying SwiftPitchFold's project file, which came from Serpe's,
which came from ProgGenie's, which came from MelGen's, so it started life
claiming somebody else's code four removes back.

**So is the bundle identifier**, and that one is worse when it is wrong. A
colliding subtype makes a host load the wrong plug-in, which is visible. A
colliding bundle id makes the plug-in *silently not exist* — which is what
happened to the Swift Serpe, shipped as `com.enkerli.Serpe` against the JUCE
build's `com.enkerli.serpe`, and it did not appear in AUM at all. Both are
checked by `Scripts/verify.sh identity`, across every sibling checkout, JUCE
`CMakeLists.txt` and Swift `Info.plist` alike.

**Nothing generates on the audio thread.** A clip is read off disk, decided
whole, and handed to the kernel as already-decided notes. Inherited from the
shell and load-bearing.

**Passes, not scores.** A mark is never overwritten and a clip is never deleted.
If you find yourself computing an average of somebody's dispositions, or adding a
"rating" field, you are removing the one thing this model has that a star rating
does not: the record of having changed your mind.

**The library is not the session.** Clips live in the extension's defaults; the
audio unit's `fullState` holds only a cursor. Do not move the clips into
`fullState` to make something simpler — a library that vanished with the host
project would not be a library. `CuratorState`'s header argues it.

**A control that does nothing gets removed, not shipped.** `playbackDirection`
works in the kernel and is deliberately not declared here, for a reason written
down in `AudioUnit/Parameters.swift`. Adding a control because the kernel
supports it is how three inert parameters ended up in two sibling plug-ins.

---

## House style

The prose in this repo — comments, commit messages, documents — explains *why*,
records what was measured, and says plainly what is not known. A comment that
restates the code is noise; a comment naming the bug that made the code look like
that is the reason the file is readable a month later. When you are unsure
whether something works, write that down instead of rounding up. The README's
"What has not been done" section is the model.
