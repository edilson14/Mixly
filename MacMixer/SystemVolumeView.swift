import SwiftUI

struct SystemVolumeView: View {
    @State private var systemVolume: Float = 0.0
    @State private var deviceName: String = "Unknown"
    @State private var timer: Timer?
    @State private var isEditing = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Dispositivo de áudio
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dispositivo de Saída")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(deviceName)
                        .font(.body)
                        .fontWeight(.semibold)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            // Controle de Volume do Sistema
            VStack(spacing: 8) {
                HStack {
                    Text("Volume do Sistema")
                        .font(.body)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(systemVolume * 100))%")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                    
                    Slider(
                        value: $systemVolume,
                        in: 0...1,
                        onEditingChanged: { editing in
                            isEditing = editing
                            if !editing {
                                CoreAudioManager.shared.setSystemVolume(systemVolume)
                            }
                        }
                    )
                    .onChange(of: systemVolume) { newValue in
                        if isEditing {
                            CoreAudioManager.shared.setSystemVolume(newValue)
                        }
                    }
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            Divider()
                .padding(.vertical, 8)
        }
        .padding()
        .onAppear {
            updateVolume()
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }
    
    private func updateVolume() {
        let (deviceName, volume) = CoreAudioManager.shared.getOutputDeviceInfo()
        self.deviceName = deviceName
        // Não sobrescrever o slider enquanto o usuário está arrastando
        if !isEditing {
            self.systemVolume = volume
        }
    }
    
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            updateVolume()
        }
    }
    
    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    SystemVolumeView()
}
