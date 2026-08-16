import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("🔊 Mac Mixer")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            ScrollView {
                VStack(spacing: 0) {
                    // Volume do Sistema
                    SystemVolumeView()
                    
                    // AudioKit - Controle Real por App
                    AudioKitAppView()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
