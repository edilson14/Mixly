import Foundation
import CoreAudio
import AVFoundation

class CoreAudioManager {
    static let shared = CoreAudioManager()

    /// Obter o ID do dispositivo de saída padrão
    private func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var outputDeviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &outputDeviceID
        )

        guard status == kAudioHardwareNoError, outputDeviceID != kAudioObjectUnknown else {
            print("Erro ao obter dispositivo de áudio: \(status)")
            return nil
        }

        return outputDeviceID
    }

    /// Elementos onde o volume está disponível: master (0) ou canais individuais (1, 2)
    /// Dispositivos como os alto-falantes internos do MacBook não expõem volume no master.
    private func volumeElements(for deviceID: AudioDeviceID) -> [UInt32] {
        let candidates: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]

        return candidates.filter { element in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            return AudioObjectHasProperty(deviceID, &address)
        }
    }

    /// Obter o volume do dispositivo de saída padrão (0.0 a 1.0)
    func getSystemVolume() -> Float {
        guard let deviceID = getDefaultOutputDeviceID() else { return 0.0 }
        return getVolume(deviceID: deviceID)
    }

    private func getVolume(deviceID: AudioDeviceID) -> Float {
        let elements = volumeElements(for: deviceID)
        guard !elements.isEmpty else {
            print("Dispositivo não expõe controle de volume")
            return 0.0
        }

        var total: Float = 0.0
        var count: Float = 0.0

        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            var volume: Float = 0.0
            var size = UInt32(MemoryLayout<Float>.size)

            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
            if status == kAudioHardwareNoError {
                total += volume
                count += 1
            }

            // Se o master existe, ele já representa o volume todo
            if element == kAudioObjectPropertyElementMain && status == kAudioHardwareNoError {
                return volume
            }
        }

        return count > 0 ? total / count : 0.0
    }

    /// Definir o volume do dispositivo de saída (0.0 a 1.0)
    func setSystemVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))

        guard let deviceID = getDefaultOutputDeviceID() else { return }

        let elements = volumeElements(for: deviceID)
        guard !elements.isEmpty else {
            print("Dispositivo não expõe controle de volume")
            return
        }

        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == kAudioHardwareNoError,
                  settable.boolValue else {
                continue
            }

            var volumeToSet = clampedVolume
            let size = UInt32(MemoryLayout<Float>.size)

            let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volumeToSet)
            if status != kAudioHardwareNoError {
                print("Erro ao definir volume no elemento \(element): \(status)")
            }

            // Se o master é settable, não precisa mexer nos canais
            if element == kAudioObjectPropertyElementMain && status == kAudioHardwareNoError {
                return
            }
        }
    }
    
    /// Obter informações sobre o dispositivo de saída
    func getOutputDeviceInfo() -> (name: String, volume: Float) {
        guard let outputDeviceID = getDefaultOutputDeviceID() else {
            return ("Unknown Device", 0.0)
        }

        // Obter nome do dispositivo
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)

        AudioObjectGetPropertyData(
            outputDeviceID,
            &nameAddress,
            0,
            nil,
            &nameSize,
            &deviceName
        )

        return ((deviceName as String), getVolume(deviceID: outputDeviceID))
    }
}
