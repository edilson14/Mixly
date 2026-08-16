import Foundation
import CoreAudio

/// Dispositivo de saída de áudio disponível no sistema (para roteamento por app).
struct AudioOutputDevice: Identifiable, Equatable, Hashable {
    var id: String { uid }
    let uid: String
    let name: String

    static func listOutputDevices() -> [AudioOutputDevice] {
        filterAndSort(rawDevices())
    }

    // MARK: - CoreAudio

    private struct RawDevice {
        let uid: String
        let name: String
        let isOutputCapable: Bool
        let isHidden: Bool
    }

    private static func rawDevices() -> [RawDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else {
            return []
        }

        var deviceIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard let uid = deviceUID(deviceID) else { return nil }
            let name = deviceName(deviceID) ?? uid
            return RawDevice(
                uid: uid,
                name: name,
                isOutputCapable: hasOutputStreams(deviceID),
                isHidden: isHidden(deviceID)
            )
        }
    }

    private static func hasOutputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }

        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func isHidden(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIsHidden,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    private static func deviceUID(_ deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr else {
            return nil
        }
        return uid as String
    }

    private static func deviceName(_ deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name as String
    }

    // MARK: - Filtragem/ordenação (puro, testável)

    private static func filterAndSort(_ raw: [RawDevice]) -> [AudioOutputDevice] {
        var seenUIDs: Set<String> = []
        return raw
            .filter { $0.isOutputCapable && !$0.isHidden }
            .filter { seenUIDs.insert($0.uid).inserted }
            .map { AudioOutputDevice(uid: $0.uid, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
