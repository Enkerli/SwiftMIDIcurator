//
//  curate-main.swift
//  SwiftMIDIcurator
//
//  What the plug-in decides, checked away from a host.
//
//  Three things are worth checking here and none of them is the interface: how
//  a file becomes a clip, how the queue is ordered, and what happens when the
//  same file arrives twice. The interface is `Carrier` and `UI` and is checked
//  where it lives.
//
//  The import tests go through the real writer and the real reader — `MIDIExport
//  .write` then `MIDIImport.read` — rather than through a hand-built `Clip`.
//  That is deliberate and it costs nothing: a duplicate check that only ever
//  saw clips this file constructed would pass while the reader put a different
//  start beat on every import, and then nothing would ever look like a
//  duplicate. The round trip is the point.
//

import Foundation
import Carrier
import Theory

var failures = 0
var checks = 0

func check(_ what: String, _ passed: Bool, _ detail: String = "") {
    checks += 1
    print("  \(passed ? "PASS" : "FAIL")  \(what)\(detail.isEmpty ? "" : " — \(detail)")")
    if !passed { failures += 1 }
}

// A throwaway store, so this never touches a real library.
let suiteName = "SwiftMIDIcurator.tests.\(UUID().uuidString)"
ClipLibrary.defaults = UserDefaults(suiteName: suiteName)!
defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

func note(_ pitch: UInt8, _ beat: Double, _ length: Double = 0.5) -> SequencedNote {
    SequencedNote(note: pitch, velocity: 90, startBeat: beat, durationBeats: length)
}

let scale = (0..<8).map { note(UInt8(60 + [0, 2, 4, 5, 7, 9, 11, 12][$0]), Double($0) * 0.5) }

print("── a file becomes a clip ──────────────────────────")

let data = MIDIExport.write(notes: scale,
                            progressionText: "Cmaj7 | Dm7 | G7 | Cmaj7",
                            name: "ascending")
let imported = try! MIDIImport.read(data, name: "ascending")
let clip = Clip(from: imported)

check("the notes survive the round trip", clip.notes.count == scale.count,
      "\(clip.notes.count) of \(scale.count)")
check("and so do their pitches",
      clip.notes.map(\.note).sorted() == scale.map(\.note).sorted())
check("the changes come back as changes",
      clip.progressionText?.contains("Cmaj7") == true,
      clip.progressionText ?? "none")
check("and the plug-in records how they got here, not just that they did",
      !clip.harmonySource.isEmpty, clip.harmonySource)
check("length is the last note's end, not the note count",
      clip.lengthBeats == 4.0, "\(clip.lengthBeats) beats")

// The source chip is the reason `TakeSource.imported` was added to Carrier: an
// imported clip labelled "line" would put a lie on every row in the library,
// and `TakeFacets.chips` says the source chip is never elided.
check("facets call it imported rather than generated",
      clip.facets.source == .imported, clip.facets.chips.joined(separator: " · "))
check("and analysis happens, because the file carried changes",
      clip.analysis != nil)

let bare = Clip(from: try! MIDIImport.read(
    MIDIExport.write(notes: scale, progressionText: "", name: "bare"), name: "bare"))
check("a file with no changes analyses to nothing rather than to invented numbers",
      bare.analysis == nil)
check("and still gets facets, from the defaults", bare.facets.bars >= 1,
      bare.facets.chips.joined(separator: " · "))

print("\n── the same file twice ────────────────────────────")

ClipLibrary.write([])
_ = ClipLibrary.add(clip)
let again = Clip(from: try! MIDIImport.read(data, name: "ascending (1)"))
check("a re-import of the same music is recognised under a different name",
      again.isSameMaterial(as: clip))

var shifted = clip
shifted.notes = scale.map { note($0.note, $0.startBeat + 0.25) }
check("but nudging every note is different music", !shifted.isSameMaterial(as: clip))

var louder = clip
louder.notes = scale.map { SequencedNote(note: $0.note, velocity: 40,
                                         startBeat: $0.startBeat,
                                         durationBeats: $0.durationBeats) }
check("and a different velocity curve is not", louder.isSameMaterial(as: clip),
      "velocity and duration are export settings, not material")

print("\n── the queue ──────────────────────────────────────")

ClipLibrary.write([])
func stored(_ name: String, _ disposition: TakeDisposition?, pass: Int = 1) -> Clip {
    var made = Clip(name: name, notes: scale, beatsPerBar: 4)
    if let disposition {
        made.marks = [CurationMark(disposition: disposition, pass: pass)]
    }
    return ClipLibrary.add(made)
}

let skipped = stored("skipped", .skip)
let unheard = stored("unheard", nil)
let deferred = stored("deferred", .later)
let kept = stored("kept", .keep)

var state = CuratorState()
state.order = .review
let order = state.ordered.map(\.displayName)
check("review order is deferred, unheard, settled, skipped",
      order == ["deferred", "unheard", "kept", "skipped"],
      order.joined(separator: " → "))
check("which is the foundation's order and not this plug-in's",
      TakeDisposition.later.reviewPriority < TakeDisposition.unmarkedPriority
      && TakeDisposition.unmarkedPriority < TakeDisposition.keep.reviewPriority
      && TakeDisposition.keep.reviewPriority < TakeDisposition.skip.reviewPriority)

state.order = .name
check("name order is alphabetical",
      state.ordered.map(\.displayName) == ["deferred", "kept", "skipped", "unheard"],
      state.ordered.map(\.displayName).joined(separator: " "))

state.order = .recent
check("recent order is newest first",
      state.ordered.first?.id == kept.id, state.ordered.first?.displayName ?? "none")

print("\n── a sweep ────────────────────────────────────────")

state.order = .review
check("everything judged on pass 1 is behind us", state.unheardThisPass == 1,
      "\(state.unheardThisPass) unheard")

check("next unheard skips what this pass already answered",
      state.nextUnheard(after: nil)?.id == unheard.id,
      state.nextUnheard(after: nil)?.displayName ?? "none")

state.judge(.tweak, clip: unheard)
check("and once it is answered, the pass is empty", state.unheardThisPass == 0)
check("a drained queue has no next", state.nextUnheard(after: nil) == nil)

state.pass = 2
check("a new pass brings everything back", state.unheardThisPass == 4,
      "\(state.unheardThisPass) to hear again")

// The whole argument for passes rather than scores: the disagreement survives.
state.judge(.keep, clip: ClipLibrary.clips.first { $0.id == skipped.id }!)
let reconsidered = ClipLibrary.clips.first { $0.id == skipped.id }!
check("a clip skipped on pass 1 and kept on pass 2 keeps both marks",
      reconsidered.marks.count == 2,
      reconsidered.marks.map { "\($0.disposition.rawValue)@\($0.pass)" }
          .joined(separator: " "))
check("and the pass-1 mark still reads as a skip",
      reconsidered.mark(onPass: 1)?.disposition == .skip)
check("while the latest is the keep",
      reconsidered.latestMark?.disposition == .keep)

print("\n── tags ───────────────────────────────────────────")

var tagState = CuratorState()
tagState.retag(["Bossa", " bossa ", "sparse"], clip: reconsidered)
let tagged = ClipLibrary.clips.first { $0.id == reconsidered.id }!
check("tags are normalized so two spellings are one tag",
      tagged.tags == ["bossa", "sparse"], tagged.tags.joined(separator: " "))

tagState.retag(["bossa"], clip: ClipLibrary.clips.first { $0.id == kept.id }!)
check("the vocabulary is what the library actually uses, most used first",
      tagState.tagVocabulary.suggestions.first == "bossa",
      tagState.tagVocabulary.suggestions.joined(separator: " "))

print("\n── the session ────────────────────────────────────")

var session = CuratorState()
session.currentClipID = kept.id
session.pass = 3
session.order = .name
let encoded = try! JSONEncoder().encode(session)
let restored = try! JSONDecoder().decode(CuratorState.self, from: encoded)
check("the session round-trips through JSON", restored == session)
check("and the library is not in it — it is the cursor that is saved, not the clips",
      !String(data: encoded, encoding: .utf8)!.contains("notes"),
      "\(encoded.count) bytes")
check("restoring the cursor finds the clip again",
      restored.currentClip?.id == kept.id)

print("\n\(failures == 0 ? "all checks passed" : "\(failures) of \(checks) FAILED")")
exit(failures == 0 ? 0 : 1)
