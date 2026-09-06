//
//  Parameters.swift
//  SwiftMIDIcuratorExtension
//
//  Two of the kernel's three.
//
//  This is the first Swift-native plug-in in the suite whose parameter tree is
//  neither MelGen's full three nor empty, and the reasoning for each is the same
//  question asked separately: does the kernel act on it, and does acting on it
//  mean something here?
//
//  · `playMelody` — yes and yes. Auditioning is the whole job.
//  · `hostSync` — yes and yes. A clip auditioned against the host's tempo is
//    the clip you would actually use, which is the judgement being recorded.
//    GAPS.md lists "no UI surfaces host sync" as a shared gap; this plug-in
//    surfaces it, so the register says so.
//  · `playbackDirection` — the kernel acts on it, and here it would mean
//    something *wrong*. A mark records what you heard; hearing a clip backwards
//    and writing "keep" against the forward one records a judgement of music
//    that isn't in the library. Left out deliberately, not forgotten.
//
//  Everything genuinely this plug-in's — the pass number, the order, which clip
//  is loaded — is session state. A host automating "which clip" would be
//  automating a curation decision, which is the one thing here that has to be a
//  person's.
//

import AudioToolbox
import Foundation
import Kernel
import Shell

let SwiftMIDIcuratorParameterSpecs = ParameterTreeSpec {
    ParameterGroupSpec(identifier: "global", name: "Global") {
        ParameterSpec(
            address: .playMelody,
            identifier: "playMelody",
            name: "Play",
            units: .boolean,
            valueRange: 0...1,
            defaultValue: 0
        )

        ParameterSpec(
            address: .hostSync,
            identifier: "hostSync",
            name: "Sync to Host",
            units: .boolean,
            valueRange: 0...1,
            defaultValue: 0
        )
    }
}

extension ParameterSpec {
    init(
        address: PluginParameterAddress,
        identifier: String,
        name: String,
        units: AudioUnitParameterUnit,
        valueRange: ClosedRange<AUValue>,
        defaultValue: AUValue,
        unitName: String? = nil,
        flags: AudioUnitParameterOptions = [AudioUnitParameterOptions.flag_IsWritable, AudioUnitParameterOptions.flag_IsReadable],
        valueStrings: [String]? = nil,
        dependentParameters: [NSNumber]? = nil
    ) {
        self.init(address: address.rawValue,
                  identifier: identifier,
                  name: name,
                  units: units,
                  valueRange: valueRange,
                  defaultValue: defaultValue,
                  unitName: unitName,
                  flags: flags,
                  valueStrings: valueStrings,
                  dependentParameters: dependentParameters)
    }
}
