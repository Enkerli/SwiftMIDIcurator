//
//  Clip.swift
//  SwiftMIDIcuratorExtension
//
//  A MIDI file you kept, and what you have said about it.
//
//  This is the plug-in where the shared foundation pays off hardest, and it is
//  worth being specific about why rather than claiming it. Everything a curator
//  needs already existed:
//
//    · reading a `.mid` — `Carrier`'s `MIDIFileImport`, which even knows this
//      product's own marker (`MCURATOR:v1 PROG`), because the interchange
//      format was designed against it;
//    · what a judgement *is* — `Carrier`'s `TakeDisposition`, `CurationMark`,
//      passes, the emergent tag vocabulary, and facets derived from measurement
//      rather than typed;
//    · what to say about the notes — `MelodyAnalysis`;
//    · auditioning one — the kernel's note scheduler;
//    · and the whole interface — `DispositionBar`, `FacetChips`, `TagField`,
//      `ReviewRow`, `MiniRoll`, all in the shared `UI` target.
//
//  PORTING.md §6 rated this plug-in "engine cheap, UI is the plug-in. Wrong
//  shape for a SwiftUI rewrite." That was written before the UI kit had a
//  curation view in it. The engine is still cheap and the interface is now
//  cheap too, because MelGen needed the same one and it was built as foundation.
//
//  So what is left here is a *library*: a list, a file importer, and the
//  question of which clip you are looking at.
//

import Foundation
import Carrier
import Theory

/// One kept clip.
struct Clip: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    /// What the file called itself.
    var name: String
    /// When it came in.
    var importedAt: Date = Date()
    /// The notes, in beats from the start.
    var notes: [SequencedNote]
    /// Leadsheet text, when the file carried or implied harmony.
    var progressionText: String?
    /// How the harmony was arrived at — read from a marker, from a chord track,
    /// detected from the notes, or not at all. Kept because "we found changes"
    /// and "we guessed changes" are different claims about the same clip.
    var harmonySource: String
    var beatsPerBar: Double
    var beatsPerMinute: Double
    /// What the reader had to decide rather than know.
    var warnings: [String]

    // ── What you have said about it ─────────────────────────────────────────
    //
    // The same vocabulary MelGen judges takes with, and deliberately the same:
    // a disposition is not a rating, a pass is which sweep you were on, and a
    // clip skipped on the first pass and kept on the third is a disagreement
    // worth keeping rather than a correction to overwrite.

    var marks: [CurationMark] = []
    var tags: [String] = []
    var title: String = ""

    var lengthBeats: Double {
        notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0
    }

    var latestMark: CurationMark? {
        marks.max { ($0.pass, $0.date) < ($1.pass, $1.date) }
    }

    func mark(onPass pass: Int) -> CurationMark? {
        marks.filter { $0.pass == pass }.max { $0.date < $1.date }
    }

    /// What can be said about the notes — but only when there is harmony to say
    /// it against.
    ///
    /// `MelodyAnalyser.analyse` requires a progression, and that is not an
    /// oversight to work around: half of what it reports is *role* — chord tone,
    /// tension, off-scale — which has no meaning without changes. A clip whose
    /// file carried none analyses to nil, the facets fall back to their
    /// no-analysis defaults, and the interface says so rather than showing
    /// invented numbers. See GAPS.md: detecting harmony from the notes alone is
    /// a build-back, not a bug.
    var analysis: MelodyAnalysis? {
        guard notes.count > 1,
              let text = progressionText, !text.isEmpty,
              let progression = try? ChordProgression.parse(text) else { return nil }
        return MelodyAnalyser.analyse(notes, over: progression, beatsPerBar: beatsPerBar)
    }

    /// The structural facets, derived rather than typed — the same ones MelGen
    /// sorts takes by.
    var facets: TakeFacets {
        TakeFacetting.facets(for: notes, lengthBeats: lengthBeats,
                             analysis: analysis, source: .imported,
                             beatsPerBar: beatsPerBar)
    }

    var displayName: String { title.isEmpty ? name : title }

    /// Whether two clips are the same music, whatever the files were called.
    ///
    /// Pitch and start only — not velocity, not duration, and not the name. A
    /// file exported twice from a DAW can differ in release times and in the
    /// velocity curve applied on the way out without being a different clip, and
    /// a renamed file is obviously not one. Getting this wrong in the strict
    /// direction costs a duplicate row; getting it wrong in the loose direction
    /// would refuse to import a real variation, which is worse, so the beat
    /// comparison is exact rather than tolerant.
    func isSameMaterial(as other: Clip) -> Bool {
        guard notes.count == other.notes.count else { return false }
        return zip(notes.sorted { $0.startBeat < $1.startBeat },
                   other.notes.sorted { $0.startBeat < $1.startBeat })
            .allSatisfy { $0.note == $1.note && $0.startBeat == $1.startBeat }
    }

    var summary: String {
        var parts = ["\(notes.count) notes"]
        if lengthBeats > 0 {
            let bars = (lengthBeats / max(1, beatsPerBar)).rounded(.up)
            parts.append("\(Int(bars)) bar\(bars == 1 ? "" : "s")")
        }
        parts.append(harmonySource)
        if let text = progressionText, !text.isEmpty {
            let bars = text.split(separator: "|").count
            parts.append(bars == 1 ? text : "\(bars) bars of changes")
        }
        return parts.joined(separator: " · ")
    }

    init(from imported: MIDIFileImport) {
        name = imported.name
        notes = imported.melody
        progressionText = imported.progressionText
        harmonySource = imported.harmonySource.label
        beatsPerBar = imported.beatsPerBar
        beatsPerMinute = imported.beatsPerMinute
        warnings = imported.warnings
    }

    init(id: UUID = UUID(), name: String, notes: [SequencedNote],
         progressionText: String? = nil, harmonySource: String = "none",
         beatsPerBar: Double = 4, beatsPerMinute: Double = 120,
         warnings: [String] = [], marks: [CurationMark] = [],
         tags: [String] = [], title: String = "") {
        self.id = id
        self.name = name
        self.notes = notes
        self.progressionText = progressionText
        self.harmonySource = harmonySource
        self.beatsPerBar = beatsPerBar
        self.beatsPerMinute = beatsPerMinute
        self.warnings = warnings
        self.marks = marks
        self.tags = tags
        self.title = title
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
        notes = try c.decodeIfPresent([SequencedNote].self, forKey: .notes) ?? []
        progressionText = try c.decodeIfPresent(String.self, forKey: .progressionText)
        harmonySource = try c.decodeIfPresent(String.self, forKey: .harmonySource) ?? "none"
        beatsPerBar = try c.decodeIfPresent(Double.self, forKey: .beatsPerBar) ?? 4
        beatsPerMinute = try c.decodeIfPresent(Double.self, forKey: .beatsPerMinute) ?? 120
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        marks = try c.decodeIfPresent([CurationMark].self, forKey: .marks) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    }
}
