import Foundation
import AppKit
import Combine

class AudioManager: NSObject, ObservableObject {
    @Published var runningApps: [AppAudio] = []
    
    private var timer: Timer?
    
    override init() {
        super.init()
        startMonitoring()
    }
    
    func startMonitoring() {
        updateRunningApps()
        
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateRunningApps()
        }
    }
    
    func updateRunningApps() {
        DispatchQueue.main.async {
            let workspace = NSWorkspace.shared
            let running = workspace.runningApplications
            
            self.runningApps = running
                .filter { $0.activationPolicy == .regular }
                .map { app in
                    AppAudio(
                        name: app.localizedName ?? "Unknown",
                        bundleIdentifier: app.bundleIdentifier ?? "",
                        icon: app.icon,
                        volume: 1.0
                    )
                }
                .sorted { $0.name < $1.name }
        }
    }
    
    func setVolume(for app: AppAudio, volume: Double) {
        if let index = runningApps.firstIndex(where: { $0.id == app.id }) {
            DispatchQueue.main.async {
                self.runningApps[index].volume = volume
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

struct AppAudio: Identifiable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String
    let icon: NSImage?
    var volume: Double
}
