//
//  ClipImport.swift
//  SwiftMIDIcuratorExtension
//
//  Getting `.mid` files into the library.
//
//  The reading is `Carrier`'s `MIDIImport.read` and none of it is here. What is
//  here is the part that is genuinely this plug-in's: which files, what to do
//  with one that won't parse, and what to do with one that is already in the
//  library.
//
//  On that last question — a re-import of a file you have already judged does
//  *not* replace it, and does not silently make a second copy either. It is
//  reported as a duplicate and skipped, because the marks are the valuable half
//  and the notes are the cheap half: losing a pass of judgements to a dragged
//  folder would be the worst bug this plug-in could have.
//

import Foundation
import Carrier

enum ClipImport {

    /// What happened to one file.
    enum Outcome {
        case added(Clip)
        case duplicate(name: String, existing: Clip)
        case failed(name: String, reason: String)

        var isAdded: Bool { if case .added = self { return true }; return false }

        var line: String {
            switch self {
            case .added(let clip):
                return "\(clip.displayName) — \(clip.summary)"
            case .duplicate(let name, let existing):
                let marks = existing.marks.count
                return "\(name) — already in the library"
                    + (marks == 0 ? "" : ", with \(marks) mark\(marks == 1 ? "" : "s")")
            case .failed(let name, let reason):
                return "\(name) — \(reason)"
            }
        }
    }

    /// Reads one file and adds it, unless the library already has it.
    ///
    /// `security-scoped` because a document picker hands back a URL the process
    /// is not otherwise allowed to open; the balanced stop is what makes a second
    /// import of the same folder work.
    static func importFile(at url: URL) -> Outcome {
        let name = url.deletingPathExtension().lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failed(name: name, reason: "couldn't be read")
        }

        let imported: MIDIFileImport
        do {
            imported = try MIDIImport.read(data, name: name)
        } catch {
            return .failed(name: name, reason: "isn't a MIDI file this can read")
        }

        guard !imported.melody.isEmpty else {
            return .failed(name: name, reason: "has no notes on any track")
        }

        var clip = Clip(from: imported)
        if let existing = ClipLibrary.clips.first(where: { $0.isSameMaterial(as: clip) }) {
            return .duplicate(name: name, existing: existing)
        }
        clip = ClipLibrary.add(clip)
        return .added(clip)
    }

    /// Reads a batch, in the order given.
    static func importFiles(at urls: [URL]) -> [Outcome] {
        urls.map(importFile(at:))
    }

    /// A one-line report of a batch, for the interface to show once rather than
    /// as an alert per file.
    static func report(_ outcomes: [Outcome]) -> String {
        let added = outcomes.filter(\.isAdded).count
        var parts: [String] = []
        if added > 0 { parts.append("\(added) clip\(added == 1 ? "" : "s") added") }
        let duplicates = outcomes.filter { if case .duplicate = $0 { return true }; return false }.count
        if duplicates > 0 { parts.append("\(duplicates) already here") }
        let failed = outcomes.filter { if case .failed = $0 { return true }; return false }.count
        if failed > 0 { parts.append("\(failed) couldn't be read") }
        return parts.isEmpty ? "Nothing to import" : parts.joined(separator: ", ")
    }
}
