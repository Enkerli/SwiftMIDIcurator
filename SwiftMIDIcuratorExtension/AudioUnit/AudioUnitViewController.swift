//
//  AudioUnitViewController.swift
//  SwiftMIDIcuratorExtension
//
//  SwiftMIDIcurator's principal class: the three things a plug-in tells the shell.
//
//  Info.plist names `$(PRODUCT_MODULE_NAME).AudioUnitViewController` as both the
//  principal class and the factory function, so this type keeps that name.
//
//  Fifth plug-in, fifth identical file. The shape stopped being evidence of
//  anything after the third; it is here because it is the entry point, not
//  because it proves the shell works.
//

import CoreAudioKit
import SwiftUI
import Shell

@MainActor
public final class AudioUnitViewController: PluginViewController {

    public override func makeAudioUnit(componentDescription: AudioComponentDescription) throws -> PluginAudioUnit {
        try SwiftMIDIcuratorAudioUnit(componentDescription: componentDescription, options: [])
    }

    public override var parameterTreeSpec: ParameterTreeSpec { SwiftMIDIcuratorParameterSpecs }

    public override func makeRootView(parameterTree: ObservableAUParameterGroup,
                                      audioUnit: PluginAudioUnit) -> AnyView {
        AnyView(SwiftMIDIcuratorMainView(parameterTree: parameterTree,
                                         audioUnit: audioUnit as? SwiftMIDIcuratorAudioUnit))
    }
}
