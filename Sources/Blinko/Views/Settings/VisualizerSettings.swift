import AppKit
import SwiftUI

/// Settings → Appearance → Details: Visualizer Off / Classic / Real, the player spectrum,
/// and the System Audio Recording status. Picking Real is the only thing that asks.
struct VisualizerSettings: View {
    var body: some View {
        @Bindable var p = Preferences.shared
        let service = AudioSpectrumService.shared
        Picker("Visualizer", selection: mode) {
            ForEach(VisualizerMode.allCases) { Text($0.title).tag($0) }
        }
        if p.visualizerMode == .real {
            if !AudioSpectrumService.isSupported {
                Label("Real needs macOS 14.2 or later; Classic is shown instead.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } else if service.permission == .denied || service.status == .denied {
                HStack {
                    Label("System audio recording is off for Blinko; Classic is shown instead.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                }
                .font(.callout)
            }
            Toggle("Spectrum on the player artwork", isOn: $p.expandedSpectrum)
            Text("Real listens to the playing app's sound (or all system audio when it can't tell) only while the bars are on screen and music plays, and never records. macOS asks once for System Audio Recording.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mode: Binding<VisualizerMode> {
        Binding(get: { Preferences.shared.visualizerMode }, set: { new in
            Preferences.shared.visualizerMode = new
            if new == .real { AudioSpectrumService.shared.requestPermission() }
            AudioSpectrumService.shared.preferencesChanged()
        })
    }
}
