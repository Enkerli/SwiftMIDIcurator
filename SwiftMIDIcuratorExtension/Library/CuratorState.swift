//
//  CuratorState.swift
//  SwiftMIDIcuratorExtension
//
//  The library, which pass you are on, and which clip you are looking at.
//
//  One architectural decision here is worth arguing about, and it is where the
//  clips live. Everything else in this plug-in persists through the audio unit's
//  `fullState`, which belongs to one project in one host. That is right for
//  "which clip am I looking at" and wrong for "the clips": a library that
//  vanished when you opened a different project would not be a library.
//
//  So the clips go in the extension's own defaults and the *session* holds a
//  cursor into them. Reopening a project puts you back where you were; opening
//  a different one still has your clips. MelGen made the same split for the same
//  reason — its take history is a log and belongs to the project, its saved
//  setups do not.
//
//  The consequence is worth stating plainly rather than discovering: two
//  instances of this plug-in in the same host share one library, and a judgement
//  made in one is visible in the other on next read. That is the behaviour a
//  library should have and it is also not transactional. See GAPS.md.
//

import Foundation
import Carrier

/// The clips, which outlive any one session.
///
/// Deliberately not an observable object. The library is read on appear and
/// after every write, which for a list of this size costs nothing and removes
/// the whole class of bug where two instances disagree about what is in it.
enum ClipLibrary {
    static let key = "SwiftMIDIcurator.clips"

    /// Where the library is stored. `.standard` in the plug-in; a throwaway
    /// suite in `curate-main.swift`, which is the only reason this is a
    /// variable — a test that judged clips into the real library and left them
    /// there would be a test that damages the thing it checks.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    static var clips: [Clip] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Clip].self, from: data) else {
            return []
        }
        return decoded
    }

    static func write(_ clips: [Clip]) {
        guard let data = try? JSONEncoder().encode(clips) else { return }
        defaults.set(data, forKey: key)
    }

    /// Adds a clip, newest first. Returns what was actually stored.
    @discardableResult
    static func add(_ clip: Clip) -> Clip {
        var all = clips
        all.insert(clip, at: 0)
        write(all)
        return clip
    }

    static func update(_ clip: Clip) {
        var all = clips
        guard let index = all.firstIndex(where: { $0.id == clip.id }) else { return }
        all[index] = clip
        write(all)
    }

    static func remove(_ id: UUID) {
        write(clips.filter { $0.id != id })
    }
}

/// What this instance is doing with them.
struct CuratorState: Codable, Hashable, Sendable {

    /// Which clip is loaded, by id. Nil before anything is chosen.
    ///
    /// By id rather than by index, because the library is shared and an index
    /// into a list another instance just inserted into points at the wrong clip.
    var currentClipID: UUID?

    /// Which sweep through the library you are on.
    ///
    /// Curation here is passes, not scores — `Carrier`'s model and its reason: a
    /// clip skipped on the first pass and kept on the third is a *disagreement*,
    /// and the disagreement is the most interesting thing in the record.
    /// Overwriting it with a running average would throw away the part worth
    /// keeping.
    var pass: Int = 1

    /// How the list is ordered.
    var order: Order = .review

    /// Whether the seven dispositions are showing, or just the three a sweep
    /// uses. `TakeDisposition.primary` decides which three; this only decides
    /// whether the rest are on screen.
    var showsAllDispositions: Bool = false

    enum Order: String, Codable, CaseIterable, Sendable {
        /// `TakeDisposition.reviewPriority`, which is the foundation's order and
        /// not this plug-in's: deferred first, then unheard, then settled, then
        /// skipped.
        case review
        /// Newest import first.
        case recent
        /// By name.
        case name

        var label: String {
            switch self {
            case .review: return "Review"
            case .recent: return "Recent"
            case .name: return "Name"
            }
        }
    }

    // MARK: - Reading the library

    var clips: [Clip] { ClipLibrary.clips }

    var currentClip: Clip? {
        guard let currentClipID else { return nil }
        return ClipLibrary.clips.first { $0.id == currentClipID }
    }

    /// The library in the chosen order.
    ///
    /// The review order is the interesting one, and none of its argument is made
    /// here: `reviewPriority` is a property of the disposition, written down in
    /// `Carrier` where MelGen's review queue also reads it. A second sweep over
    /// the discards is where the surprises are, so skipped clips come last but
    /// they do come.
    var ordered: [Clip] {
        let all = ClipLibrary.clips
        switch order {
        case .recent:
            return all.sorted { $0.importedAt > $1.importedAt }
        case .name:
            return all.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .review:
            func priority(_ clip: Clip) -> Int {
                clip.latestMark?.disposition.reviewPriority ?? TakeDisposition.unmarkedPriority
            }
            // Newest-first inside a band, and an explicit tiebreak because
            // Swift's sort is not stable — the same bug MelGen's degree
            // placement hit, and the same fix.
            return all.sorted {
                priority($0) != priority($1)
                    ? priority($0) < priority($1)
                    : $0.importedAt > $1.importedAt
            }
        }
    }

    // MARK: - Judging

    /// Records a judgement. Returns the clip as stored, marks and all.
    @discardableResult
    mutating func judge(_ disposition: TakeDisposition, clip: Clip,
                        heardAfter: UUID? = nil) -> Clip {
        var updated = clip
        updated.marks.append(CurationMark(disposition: disposition,
                                          pass: pass,
                                          heardAfter: heardAfter))
        ClipLibrary.update(updated)
        return updated
    }

    @discardableResult
    mutating func retag(_ tags: [String], clip: Clip) -> Clip {
        var updated = clip
        updated.tags = Array(Set(tags.map(TagVocabulary.normalize)))
            .filter { !$0.isEmpty }
            .sorted()
        ClipLibrary.update(updated)
        return updated
    }

    @discardableResult
    mutating func rename(_ title: String, clip: Clip) -> Clip {
        var updated = clip
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        ClipLibrary.update(updated)
        return updated
    }

    // MARK: - The state of the sweep

    /// How many clips this pass has not reached yet.
    var unheardThisPass: Int {
        ClipLibrary.clips.filter { $0.mark(onPass: pass) == nil }.count
    }

    /// The next clip to hear on this pass, in the current order.
    ///
    /// "Next" means next *unjudged on this pass*, not next in the list — so
    /// advancing through a sweep never lands you back on something you have
    /// already answered, and a sweep ends by running out rather than by looping.
    func nextUnheard(after clip: Clip?) -> Clip? {
        let queue = ordered.filter { $0.mark(onPass: pass) == nil }
        guard let clip else { return queue.first }
        if let index = queue.firstIndex(where: { $0.id == clip.id }),
           index + 1 < queue.count {
            return queue[index + 1]
        }
        // The current clip has just been judged and left the queue, so the
        // first remaining one is the next one.
        return queue.first { $0.id != clip.id }
    }

    /// Everything the library has been tagged with, most used first.
    ///
    /// The emergent half of the vocabulary — `Carrier`'s idea, and its
    /// implementation. This plug-in only supplies the corpus.
    var tagVocabulary: TagVocabulary {
        var vocabulary = TagVocabulary()
        for clip in ClipLibrary.clips { vocabulary.record(clip.tags) }
        return vocabulary
    }
}
