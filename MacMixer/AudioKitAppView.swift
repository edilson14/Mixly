import SwiftUI

struct AudioKitAppView: View {
    @StateObject private var controller = AudioKitController.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Volume por Aplicação")
                    .font(.headline)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(controller.apps.count)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let error = controller.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            if controller.apps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text("Nenhuma aplicação com áudio detectada")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("Reproduza algum áudio para a aplicação aparecer aqui")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(controller.apps) { app in
                        AudioKitAppRow(
                            app: app,
                            onVolumeChange: { newVolume in
                                controller.setVolume(for: app.bundleIdentifier, volume: Float(newVolume))
                            },
                            onMuteToggle: {
                                if app.isMuted {
                                    controller.unmuteApp(bundleID: app.bundleIdentifier)
                                } else {
                                    controller.muteApp(bundleID: app.bundleIdentifier)
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding()
    }
}

struct AudioKitAppRow: View {
    let app: AppAudioInfo
    let onVolumeChange: (Double) -> Void
    let onMuteToggle: () -> Void

    @State private var volume: Double = 1.0

    var body: some View {
        VStack(spacing: 12) {
            // App Header
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(6)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.body)
                        .fontWeight(.semibold)
                    Text(app.bundleIdentifier.components(separatedBy: "#").first ?? app.bundleIdentifier)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()

                if app.isPlaying {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Reproduzindo")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                // Mute Button
                Button(action: onMuteToggle) {
                    Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 16))
                        .foregroundColor(app.isMuted ? .red : .blue)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help(app.isMuted ? "Desmutar" : "Mutar")
            }

            // Volume Control
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))

                    Slider(value: $volume, in: 0...1)
                        .onChange(of: volume) { _, newValue in
                            if abs(Double(app.volume) - newValue) > 0.001 {
                                onVolumeChange(newValue)
                            }
                        }

                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))

                    Text("\(Int(volume * 100))%")
                        .font(.caption)
                        .frame(width: 35, alignment: .trailing)
                        .foregroundColor(.gray)
                        .monospacedDigit()
                }

                if app.isMuted {
                    HStack {
                        Image(systemName: "speaker.slash.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        Text("Mutado")
                            .font(.caption2)
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
            }

            // Status Indicators
            HStack(spacing: 8) {
                Spacer()

                // PID Indicator
                Label("\(app.processID)", systemImage: "number.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            volume = Double(app.volume)
        }
        .onChange(of: app.volume) { _, newValue in
            if abs(Double(newValue) - volume) > 0.001 {
                volume = Double(newValue)
            }
        }
    }
}

#Preview {
    AudioKitAppView()
}
