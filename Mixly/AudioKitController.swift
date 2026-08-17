import Foundation
import AppKit
import Combine
import CoreAudio

/// Mixer por aplicação usando Core Audio Process Taps (macOS 14.4+).
///
/// Enumera os processos registrados no HAL (`kAudioHardwarePropertyProcessObjectList`),
/// agrupa-os pela aplicação dona (resolvendo processos auxiliares como
/// "Google Chrome Helper" pelo PID pai ou prefixo do bundle ID) e cria um
/// `ProcessTap` por aplicação quando o usuário altera o volume.
class AudioKitController: ObservableObject {
    static let shared = AudioKitController()

    @Published var apps: [AppAudioInfo] = []
    @Published var lastError: String?
    @Published var availableOutputDevices: [AudioOutputDevice] = []

    private var taps: [String: ProcessTap] = [:]
    private var volumes: [String: Float] = [:]
    private var previousVolumes: [String: Float] = [:]
    private var selectedOutputDevices: [String: String] = [:]
    private var timer: Timer?

    init() {
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Volume

    /// Definir volume (0.0 a 1.0) para uma aplicação identificada pelo bundle ID do grupo
    func setVolume(for bundleID: String, volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        volumes[bundleID] = clampedVolume
        syncTap(for: bundleID)
        updatePublishedApps()
    }

    /// Definir o dispositivo de saída para uma aplicação (nil = padrão do sistema)
    func setOutputDevice(for bundleID: String, deviceUID: String?) {
        if let deviceUID, !deviceUID.isEmpty {
            selectedOutputDevices[bundleID] = deviceUID
        } else {
            selectedOutputDevices.removeValue(forKey: bundleID)
        }
        syncTap(for: bundleID)
        updatePublishedApps()
    }

    func getOutputDevice(for bundleID: String) -> String? {
        selectedOutputDevices[bundleID]
    }

    /// Um tap só é necessário enquanto o volume estiver abaixo de 100% ou uma
    /// saída diferente da padrão estiver selecionada — nos dois casos o áudio
    /// original precisa ser interceptado e re-renderizado.
    private func needsTap(for bundleID: String) -> Bool {
        (volumes[bundleID] ?? 1.0) < 1.0 || selectedOutputDevices[bundleID] != nil
    }

    private func syncTap(for bundleID: String) {
        guard needsTap(for: bundleID) else {
            taps.removeValue(forKey: bundleID)?.invalidate()
            return
        }

        let desiredUID = selectedOutputDevices[bundleID]
        if let tap = taps[bundleID] {
            if tap.outputDeviceUID != desiredUID {
                // Dispositivo de saída mudou: o aggregate device não é reconfigurável
                // em tempo real, então o tap inteiro é recriado.
                tap.invalidate()
                taps.removeValue(forKey: bundleID)
                createTap(for: bundleID, outputDeviceUID: desiredUID)
            } else {
                tap.gain = volumes[bundleID] ?? 1.0
            }
        } else {
            createTap(for: bundleID, outputDeviceUID: desiredUID)
        }
    }

    private func createTap(for bundleID: String, outputDeviceUID: String?) {
        guard let app = apps.first(where: { $0.bundleIdentifier == bundleID }) else { return }

        if let tap = ProcessTap(
            processObjectIDs: app.processObjectIDs,
            name: app.name,
            initialGain: volumes[bundleID] ?? 1.0,
            outputDeviceUID: outputDeviceUID
        ) {
            taps[bundleID] = tap
            lastError = nil
        } else {
            volumes[bundleID] = 1.0
            selectedOutputDevices.removeValue(forKey: bundleID)
            lastError = "Não foi possível criar o tap para \(app.name). Verifique a permissão de Gravação de Áudio do Sistema em Ajustes > Privacidade e Segurança."
        }
    }

    func muteApp(bundleID: String) {
        let current = volumes[bundleID] ?? 1.0
        if current > 0 {
            previousVolumes[bundleID] = current
        }
        setVolume(for: bundleID, volume: 0.0)
    }

    func unmuteApp(bundleID: String) {
        let previous = previousVolumes[bundleID] ?? 1.0
        setVolume(for: bundleID, volume: previous)
    }

    func getVolume(for bundleID: String) -> Float {
        return volumes[bundleID] ?? 1.0
    }

    // MARK: - Descoberta de processos

    func refresh() {
        availableOutputDevices = AudioOutputDevice.listOutputDevices()

        // Se o dispositivo escolhido para algum app foi desconectado, volta pro padrão.
        let availableUIDs = Set(availableOutputDevices.map(\.uid))
        for (key, uid) in selectedOutputDevices where !availableUIDs.contains(uid) {
            selectedOutputDevices.removeValue(forKey: key)
            syncTap(for: key)
        }

        // O IO proc do tap roda no processo do próprio Mixly, então o HAL às vezes
        // reporta o Mixly como "running output" — nunca deve aparecer na sua própria lista.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let processes = Self.listAudioProcesses().filter { $0.pid != ownPID }
        let regularApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var appsByPID: [pid_t: NSRunningApplication] = [:]
        for app in regularApps {
            appsByPID[app.processIdentifier] = app
        }

        struct Group {
            var name: String
            var pid: pid_t
            var icon: NSImage?
            var objectIDs: [AudioObjectID] = []
            var isPlaying = false
        }

        var groups: [String: Group] = [:]

        for process in processes {
            let key: String
            var name: String
            var pid = process.pid
            var icon: NSImage?

            if let owner = owningApp(for: process, appsByPID: appsByPID, regularApps: regularApps) {
                // Inclui o PID da instância dona no grouping key: dois processos
                // com o mesmo bundle ID (ex: duas instâncias do Chrome rodando com
                // --user-data-dir diferentes, cada uma com seu próprio Audio Service)
                // devem aparecer como entradas separadas no mixer, não uma só.
                let ownerBundleID = owner.bundleIdentifier ?? "pid-\(owner.processIdentifier)"
                key = "\(ownerBundleID)#\(owner.processIdentifier)"
                name = owner.localizedName ?? ownerBundleID
                pid = owner.processIdentifier
                icon = owner.icon
            } else if !process.bundleID.isEmpty {
                key = process.bundleID
                name = process.bundleID.components(separatedBy: ".").last ?? process.bundleID
                icon = NSRunningApplication(processIdentifier: process.pid)?.icon
            } else {
                key = "pid-\(process.pid)"
                name = NSRunningApplication(processIdentifier: process.pid)?.localizedName ?? "Processo \(process.pid)"
                icon = NSRunningApplication(processIdentifier: process.pid)?.icon
            }

            var group = groups[key] ?? Group(name: name, pid: pid, icon: icon)
            group.objectIDs.append(process.objectID)
            group.isPlaying = group.isPlaying || process.isRunningOutput
            groups[key] = group
        }

        // Remover taps de aplicações que desapareceram e
        // recriar taps cujo conjunto de processos mudou (ex: novo helper do Chrome)
        for (key, tap) in taps {
            guard let group = groups[key] else {
                tap.invalidate()
                taps.removeValue(forKey: key)
                continue
            }

            if Set(tap.processObjectIDs) != Set(group.objectIDs) {
                tap.invalidate()
                taps.removeValue(forKey: key)
                if let newTap = ProcessTap(
                    processObjectIDs: group.objectIDs,
                    name: group.name,
                    initialGain: volumes[key] ?? 1.0,
                    outputDeviceUID: selectedOutputDevices[key]
                ) {
                    taps[key] = newTap
                }
            }
        }

        let entries = groups.compactMap { key, group -> AppAudioInfo? in
            // Só exibe apps que estão reproduzindo áudio agora ou que já têm
            // volume/tap ajustado pelo usuário (para não sumir da lista ao
            // pausar temporariamente e permitir religar o volume depois).
            guard group.isPlaying || volumes[key] != nil || taps[key] != nil else {
                return nil
            }

            let volume = volumes[key] ?? 1.0
            return AppAudioInfo(
                name: group.name,
                bundleIdentifier: key,
                processID: group.pid,
                icon: group.icon,
                volume: volume,
                isMuted: volume == 0,
                isPlaying: group.isPlaying,
                processObjectIDs: group.objectIDs,
                outputDeviceUID: selectedOutputDevices[key]
            )
        }

        // Quando o mesmo app tem várias instâncias (ex: duas janelas do Chrome),
        // mostra só a mais recente (maior PID) em vez de uma linha por instância.
        var seenNames: Set<String> = []
        apps = entries
            .sorted { $0.processID > $1.processID }
            .filter { seenNames.insert($0.name).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func updatePublishedApps() {
        apps = apps.map { app in
            var updated = app
            let volume = volumes[app.bundleIdentifier] ?? 1.0
            updated.volume = volume
            updated.isMuted = volume == 0
            updated.outputDeviceUID = selectedOutputDevices[app.bundleIdentifier]
            return updated
        }
    }

    /// Resolve a aplicação dona de um processo de áudio:
    /// PID direto, cadeia de PIDs pais (helpers) ou prefixo do bundle ID.
    private func owningApp(
        for process: AudioProcessInfo,
        appsByPID: [pid_t: NSRunningApplication],
        regularApps: [NSRunningApplication]
    ) -> NSRunningApplication? {
        var pid = process.pid
        var depth = 0
        while pid > 1 && depth < 10 {
            if let app = appsByPID[pid] {
                return app
            }
            pid = Self.parentPID(of: pid)
            depth += 1
        }

        if !process.bundleID.isEmpty {
            // Match exato primeiro: evita que um app com bundle ID mais específico
            // (ex: Chrome App/PWA "com.google.Chrome.app.<hash>") seja engolido pelo
            // prefixo genérico "com.google.Chrome." antes de checar se ele mesmo
            // já é um app regular com bundle ID próprio.
            if let exact = regularApps.first(where: { $0.bundleIdentifier == process.bundleID }) {
                return exact
            }

            return regularApps.first { app in
                guard let appBundleID = app.bundleIdentifier else { return false }
                return process.bundleID.hasPrefix(appBundleID + ".")
            }
        }

        return nil
    }

    // MARK: - Core Audio

    private struct AudioProcessInfo {
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleID: String
        let isRunningOutput: Bool
    }

    private static func listAudioProcesses() -> [AudioProcessInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else {
            return []
        }

        var objectIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objectIDs
        ) == noErr else {
            return []
        }

        return objectIDs.compactMap { objectID in
            guard objectID != kAudioObjectUnknown else { return nil }

            let pid: pid_t = readProcessProperty(objectID, selector: kAudioProcessPropertyPID) ?? -1
            guard pid > 0 else { return nil }

            var bundleID = ""
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundleRef: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            if AudioObjectGetPropertyData(objectID, &bundleAddress, 0, nil, &bundleSize, &bundleRef) == noErr {
                bundleID = bundleRef as String
            }

            let isRunningOutput: UInt32 = readProcessProperty(objectID, selector: kAudioProcessPropertyIsRunningOutput) ?? 0

            return AudioProcessInfo(
                objectID: objectID,
                pid: pid,
                bundleID: bundleID,
                isRunningOutput: isRunningOutput != 0
            )
        }
    }

    private static func readProcessProperty<T>(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, value) == noErr else {
            return nil
        }

        return value.pointee
    }

    private static func parentPID(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            return 0
        }

        return info.kp_eproc.e_ppid
    }
}

struct AppAudioInfo: Identifiable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let processID: Int32
    let icon: NSImage?
    var volume: Float
    var isMuted: Bool
    var isPlaying: Bool
    let processObjectIDs: [AudioObjectID]
    var outputDeviceUID: String?
}
