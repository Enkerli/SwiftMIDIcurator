//
//  SwiftMIDIcuratorMainView.swift
//  SwiftMIDIcuratorExtension
//
//  One screen: the clip in front of you, what you say about it, and what's next.
//
//  Almost nothing in this file draws anything. `DispositionBar`, `FacetChips`,
//  `TagField`, `ReviewRow` and `MiniRoll` are all in the shared `UI` target,
//  built for MelGen's review panel, and a curator is that panel with a file
//  importer where the generator was. PORTING.md §6 called this plug-in "wrong
//  shape for a SwiftUI rewrite" on the grounds that the engine was cheap and the
//  interface was the whole cost. The engine is still cheap. The interface turned
//  out to have been built already, for a different plug-in, which is the only
//  interesting thing this file demonstrates.
//
//  What is left here is arrangement and one real decision: the *subject* of the
//  screen is a single clip, not the list. A library browser would put the list
//  first and make judging a detail view; this puts the clip first because
//  curation is a sweep — you are answering one thing at a time, and the list is
//  where you are up to.
//

import SwiftUI
import Carrier
import Shell
import Theory
import UI
import UniformTypeIdentifiers

struct SwiftMIDIcuratorMainView: View {
    var parameterTree: ObservableAUParameterGroup
    weak var audioUnit: SwiftMIDIcuratorAudioUnit?

    @State private var state = CuratorState()
    @State private var isImporting = false
    @State private var lastReport: String?
    /// The clip that was loaded immediately before this one, so a mark can
    /// record what it was heard after. `CurationMark.heardAfter` exists because
    /// judgement is comparative whether or not anyone admits it.
    @State private var previousClipID: UUID?
    @Environment(\.colorScheme) private var colorScheme

    private var theme: MelGenTheme { colorScheme == .dark ? .dark : .light }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MelGenMetrics.space3) {
                header
                if let clip = state.currentClip {
                    roll(for: clip)
                    judgement(for: clip)
                    tags(for: clip)
                } else {
                    emptyState
                }
                transport
                library
            }
            .padding(MelGenMetrics.space3)
        }
        .background(theme.background)
        .onAppear { if let audioUnit { state = audioUnit.state } }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.midi],
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
    }

    // MARK: - What you're listening to

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: MelGenMetrics.space2) {
                Eyebrow(text: "Pass \(state.pass)", theme: theme)
                Spacer(minLength: 0)
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .frame(minHeight: MelGenMetrics.controlHeight)
                .accessibilityHint("Adds MIDI files to the library")
            }

            Text(state.currentClip?.displayName ?? "No clip loaded")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(state.currentClip?.summary ?? "\(state.clips.count) in the library")
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)

            if let report = lastReport {
                Text(report)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }

            // Warnings are the reader's, and they are shown rather than
            // swallowed: "we guessed the changes" and "we read the changes"
            // produce the same analysis and are not the same claim.
            if let warnings = state.currentClip?.warnings, !warnings.isEmpty {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.warning)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Text("Nothing here yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
            Text("Import MIDI files and this becomes a queue: hear one, say what "
                 + "you think of it, move on. Nothing is deleted and nothing is "
                 + "scored — a clip you skip comes back on the next pass.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
        }
        .padding(MelGenMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusMedium)
            .fill(theme.raised))
    }

    private func roll(for clip: Clip) -> some View {
        MiniRoll(notes: clip.notes,
                 progression: clip.progressionText.flatMap {
                     try? ChordProgression.parse($0, beatsPerBar: clip.beatsPerBar)
                 },
                 lengthBeats: max(clip.lengthBeats, 1),
                 theme: theme)
            .frame(height: 96)
    }

    // MARK: - Saying what you think

    private func judgement(for clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            FacetChips(facets: clip.facets, theme: theme)

            DispositionBar(current: clip.mark(onPass: state.pass)?.disposition,
                           theme: theme,
                           onSelect: { disposition in
                               guard let disposition else { return }
                               judge(disposition, clip: clip)
                           },
                           startExpanded: state.showsAllDispositions)

            // The history, not a summary of it. A clip skipped on pass one and
            // kept on pass three is a disagreement, and the disagreement is what
            // is worth reading — so every mark is listed with its pass rather
            // than folded into a latest value.
            if clip.marks.count > 1 {
                MoreRow(summary: "\(clip.marks.count) marks across "
                                 + "\(Set(clip.marks.map(\.pass)).count) passes",
                        isExpanded: $showsHistory,
                        theme: theme)
                if showsHistory {
                    ForEach(clip.marks.sorted { $0.date > $1.date }) { mark in
                        HStack(spacing: MelGenMetrics.space2) {
                            Image(systemName: mark.disposition.symbolName)
                                .foregroundStyle(theme.textSecondary)
                            Text(mark.disposition.chipLabel)
                                .foregroundStyle(theme.text)
                            Text("pass \(mark.pass)")
                                .foregroundStyle(theme.textMuted)
                            Spacer(minLength: 0)
                            Text(mark.date, style: .date)
                                .foregroundStyle(theme.textMuted)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
        }
    }

    @State private var showsHistory = false

    private func tags(for clip: Clip) -> some View {
        TagField(tags: clip.tags,
                 suggestions: state.tagVocabulary.suggestions,
                 theme: theme,
                 onCommit: { tags in
                     var next = state
                     next.retag(clip.tags + tags, clip: clip)
                     apply(next)
                 })
    }

    // MARK: - Hearing it

    /// Play and host sync, and no direction control — see Parameters.swift for
    /// why a curator that can play a clip backwards would be recording marks
    /// against music that isn't in the library.
    private var transport: some View {
        HStack(spacing: MelGenMetrics.space2) {
            ToggleChip(title: "Play",
                       systemImage: playBinding.wrappedValue ? "pause.fill" : "play.fill",
                       isOn: playBinding,
                       theme: theme)
            ToggleChip(title: "Host",
                       systemImage: "metronome",
                       isOn: hostSyncBinding,
                       theme: theme)
            Spacer(minLength: 0)
            if state.unheardThisPass == 0 && !state.clips.isEmpty {
                Button("Next pass") {
                    var next = state
                    next.pass += 1
                    apply(next)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(minHeight: MelGenMetrics.controlHeight)
            } else if !state.clips.isEmpty {
                Text("\(state.unheardThisPass) to go")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    private var playBinding: Binding<Bool> {
        let parameter: ObservableAUParameter = parameterTree.global.playMelody
        return Binding(get: { parameter.boolValue }, set: { parameter.boolValue = $0 })
    }

    private var hostSyncBinding: Binding<Bool> {
        let parameter: ObservableAUParameter = parameterTree.global.hostSync
        return Binding(get: { parameter.boolValue }, set: { parameter.boolValue = $0 })
    }

    // MARK: - Where you're up to

    private var library: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            HStack {
                Eyebrow(text: "Library", theme: theme)
                Spacer(minLength: 0)
                ChipPicker(options: CuratorState.Order.allCases.map {
                               (value: $0, label: $0.label)
                           },
                           selection: Binding(get: { state.order },
                                              set: { order in
                                                  var next = state
                                                  next.order = order
                                                  apply(next)
                                              }),
                           theme: theme)
            }

            ForEach(state.ordered) { clip in
                ReviewRow(name: clip.displayName,
                          facets: clip.facets,
                          tags: clip.tags,
                          latestMark: clip.latestMark,
                          isCurrent: clip.id == state.currentClipID,
                          currentPass: state.pass,
                          theme: theme,
                          onLoad: { load(clip) })
            }
        }
    }

    // MARK: - Doing things

    private func load(_ clip: Clip) {
        var next = state
        previousClipID = next.currentClipID
        next.currentClipID = clip.id
        apply(next)
    }

    private func judge(_ disposition: TakeDisposition, clip: Clip) {
        var next = state
        next.judge(disposition, clip: clip, heardAfter: previousClipID)
        // Advance, because a sweep that made you pick the next clip yourself
        // would be a browser. `nextUnheard` skips what this pass has already
        // answered, so the queue drains rather than looping.
        if let following = next.nextUnheard(after: clip) {
            previousClipID = clip.id
            next.currentClipID = following.id
        }
        apply(next)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            lastReport = error.localizedDescription
        case .success(let urls):
            let outcomes = ClipImport.importFiles(at: urls)
            lastReport = ClipImport.report(outcomes)
            var next = state
            // Land on the first thing that came in, so an import is immediately
            // auditionable rather than leaving you looking at the old clip.
            if next.currentClipID == nil || outcomes.contains(where: \.isAdded) {
                if case .added(let clip)? = outcomes.first(where: \.isAdded) {
                    previousClipID = next.currentClipID
                    next.currentClipID = clip.id
                }
            }
            apply(next)
        }
    }

    private func apply(_ next: CuratorState) {
        state = next
        audioUnit?.update(state: next)
    }
}
