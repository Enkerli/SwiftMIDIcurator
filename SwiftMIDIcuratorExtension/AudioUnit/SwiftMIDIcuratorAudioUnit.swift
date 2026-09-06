//
//  SwiftMIDIcuratorAudioUnit.swift
//  SwiftMIDIcuratorExtension
//
//  SwiftMIDIcurator's half of the audio unit: which clip is loaded, and handing
//  its notes to the kernel.
//
//  Fifth time this file has been written. Three of the five commit a sequence,
//  one commits a map, one commits curves — and all five are this shape, because
//  the shell's contract never changed: decide off-thread, commit atomically,
//  from here.
//
//  What is different is where the notes come from. The other four *generate*
//  them; this one reads them out of a file somebody made. That is the whole
//  reason the plug-in exists, and it is also why `loadCurrentClip` is the only
//  interesting method in the file.
//

import AVFoundation
import Carrier
import Shell

public final class SwiftMIDIcuratorAudioUnit: PluginAudioUnit, @unchecked Sendable {

    private let stateLock = NSLock()
    private var _state = CuratorState()

    /// Which clip the kernel is holding, so re-reading the library — which
    /// happens after every judgement — doesn't restart the loop under a
    /// listener who is still deciding.
    private var lastLoadedClipID: UUID?

    var state: CuratorState {
        get { stateLock.withLock { _state } }
        set { update(state: newValue) }
    }

    func update(state newState: CuratorState) {
        stateLock.withLock { _state = newState }
        loadCurrentClip(newState)
    }

    /// Hands the loaded clip's notes to the kernel.
    ///
    /// A *different* clip starts from its own beginning; the same clip being
    /// re-committed — which is what tagging, renaming and marking all do — keeps
    /// playing from wherever the loop is. Judging a clip while it plays should
    /// not jump the playhead, because the next thing you do after judging is
    /// listen to the rest of it.
    private func loadCurrentClip(_ state: CuratorState) {
        guard let clip = state.currentClip, !clip.notes.isEmpty else {
            // Nothing chosen, or a clip that read as empty. Leave the kernel
            // holding what it has rather than committing an empty sequence,
            // which would cut a note off mid-audition.
            return
        }
        let isNewClip = clip.id != lastLoadedClipID
        lastLoadedClipID = clip.id
        setMelody(clip.notes,
                  lengthBeats: max(clip.lengthBeats, 1),
                  restartFromTop: isNewClip)
    }

    private static let stateKey = "SwiftMIDIcurator.sessionState"

    /// The session, not the library.
    ///
    /// Only the cursor round-trips here — which clip, which pass, which order.
    /// The clips themselves are in the extension's defaults, because a library
    /// that lived in one host project would not be a library. `CuratorState`'s
    /// header argues that decision; this is where it shows up.
    public override var fullState: [String: Any]? {
        get {
            var dictionary = super.fullState ?? [:]
            if let data = try? JSONEncoder().encode(state) {
                dictionary[Self.stateKey] = data
            }
            return dictionary
        }
        set {
            super.fullState = newValue
            guard let data = newValue?[Self.stateKey] as? Data,
                  let restored = try? JSONDecoder().decode(CuratorState.self, from: data) else {
                return
            }
            state = restored
        }
    }

    public override var fullStateForDocument: [String: Any]? {
        get { fullState }
        set { fullState = newValue }
    }
}
