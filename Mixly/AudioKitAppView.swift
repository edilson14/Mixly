import SwiftUI

struct AudioKitAppView: View {
    @EnvironmentObject private var controller: AudioKitController
    @Namespace private var glassNamespace

    private let accentBlue = Color(red: 0.35, green: 0.52, blue: 0.98)

    var body: some View {
        VStack(spacing: 16) {
            if let error = controller.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Spacer()
                }
            }

            if controller.apps.isEmpty {
                Text("Nenhuma aplicação com áudio detectada")
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                // GlassEffectContainer agrupa os cards para que o blur/luz
                // seja renderizado em um único passe e permite morphing
                // suave quando um item aparece/desaparece da lista.
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        ForEach(controller.apps) { app in
                            AudioKitAppRow(
                                app: app,
                                accentColor: accentBlue,
                                namespace: glassNamespace,
                                availableDevices: controller.availableOutputDevices,
                                onVolumeChange: { newVolume in
                                    controller.setVolume(for: app.bundleIdentifier, volume: Float(newVolume))
                                },
                                onMuteToggle: {
                                    if app.isMuted {
                                        controller.unmuteApp(bundleID: app.bundleIdentifier)
                                    } else {
                                        controller.muteApp(bundleID: app.bundleIdentifier)
                                    }
                                },
                                onOutputDeviceChange: { newDeviceUID in
                                    controller.setOutputDevice(for: app.bundleIdentifier, deviceUID: newDeviceUID)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .onAppear {
            controller.refresh()
        }
    }
}

struct AudioKitAppRow: View {
    let app: AppAudioInfo
    let accentColor: Color
    let namespace: Namespace.ID
    let availableDevices: [AudioOutputDevice]
    let onVolumeChange: (Double) -> Void
    let onMuteToggle: () -> Void
    let onOutputDeviceChange: (String?) -> Void

    @State private var volume: Double = 1.0

    private var shortName: String {
        app.name.components(separatedBy: " ").last ?? app.name
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)

                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.4))
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(shortName)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Button(action: onMuteToggle) {
                        Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)

                    Slider(value: $volume, in: 0...1)
                        .tint(accentColor)
                        .onChange(of: volume) { _, newValue in
                            if abs(Double(app.volume) - newValue) > 0.001 {
                                onVolumeChange(newValue)
                            }
                        }

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)

                    Text("\(Int(volume * 100))%")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.85))
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)

                    if !availableDevices.isEmpty {
                        Menu {
                            Button {
                                onOutputDeviceChange(nil)
                            } label: {
                                if app.outputDeviceUID == nil {
                                    Label("Padrão do sistema", systemImage: "checkmark")
                                } else {
                                    Text("Padrão do sistema")
                                }
                            }

                            Divider()

                            ForEach(availableDevices) { device in
                                Button {
                                    onOutputDeviceChange(device.uid)
                                } label: {
                                    if app.outputDeviceUID == device.uid {
                                        Label(device.name, systemImage: "checkmark")
                                    } else {
                                        Text(device.name)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "airplayaudio")
                                .font(.system(size: 11))
                                .foregroundColor(app.outputDeviceUID == nil ? .white.opacity(0.4) : accentColor)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Dispositivo de saída")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassEffectID(app.bundleIdentifier, in: namespace)
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

// MARK: - Liquid Glass helper com fallback

private extension View {
    /// Vidro escuro e neutro, sem tint colorido — igual ao Control Center:
    /// o conteúdo por trás (código, fundo do app) fica visível e borrado
    /// através do card, com só um leve realce de borda pra dar profundidade.
    ///
    /// `glassEffect` precisa ficar direto no conteúdo (não numa shape isolada
    /// em `.background`), pois é essa mesma view que o `GlassEffectContainer`
    /// combina com `.glassEffectID` para agrupar/morphar os cards — separados,
    /// o container não resolve a camada de vidro e borra a linha inteira.
    @ViewBuilder
    func liquidGlassBackground(in shape: some InsettableShape) -> some View {
        if #available(macOS 26, iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Escurece um pouco o material (o Control Center não usa
                        // o blur "cru" do sistema, ele é mais escuro/opaco)
                        shape.fill(Color.black.opacity(0.28))
                    )
                    .overlay(
                        shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
            }
        }
    }
}

#Preview {
    AudioKitAppView()
        .environmentObject(AudioKitController.shared)
        .background(Color(red: 0.08, green: 0.078, blue: 0.095))
}