import Foundation
import CoreAudio
import AudioToolbox
import os

/// Tap de áudio sobre os processos de uma aplicação (macOS 14.4+).
///
/// O tap é criado com `muteBehavior = .mutedWhenTapped`: enquanto estiver ativo,
/// a saída original dos processos é silenciada e este objeto re-renderiza o áudio
/// capturado no dispositivo de saída padrão, aplicando o ganho configurado.
nonisolated final class ProcessTap: @unchecked Sendable {
    let processObjectIDs: [AudioObjectID]

    /// UID do dispositivo de saída solicitado (nil = padrão do sistema).
    let outputDeviceUID: String?

    private var tapID: AudioObjectID = .init(kAudioObjectUnknown)
    private var aggregateID: AudioObjectID = .init(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let gainState = OSAllocatedUnfairLock<Float>(initialState: 1.0)

    /// Ganho aplicado ao áudio (0.0 = mudo, 1.0 = volume original)
    var gain: Float {
        get { gainState.withLock { $0 } }
        set {
            let clamped = max(0.0, min(1.0, newValue))
            gainState.withLock { $0 = clamped }
        }
    }

    init?(processObjectIDs: [AudioObjectID], name: String, initialGain: Float, outputDeviceUID: String? = nil) {
        guard !processObjectIDs.isEmpty else { return nil }
        self.processObjectIDs = processObjectIDs
        self.outputDeviceUID = outputDeviceUID
        gainState.withLock { $0 = max(0.0, min(1.0, initialGain)) }

        guard setup(name: name, outputDeviceUID: outputDeviceUID) else {
            teardown()
            return nil
        }
    }

    deinit {
        teardown()
    }

    /// Desfaz o tap e restaura o áudio original da aplicação
    func invalidate() {
        teardown()
    }

    // MARK: - Setup

    private func setup(name: String, outputDeviceUID: String?) -> Bool {
        // 1. Criar o process tap (requer permissão de captura de áudio do sistema)
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.name = "Mixly: \(name)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr, newTapID != kAudioObjectUnknown else {
            print("Erro ao criar process tap para \(name): \(status)")
            return false
        }
        tapID = newTapID

        // 2. Dispositivo agregado privado contendo a saída escolhida (ou a padrão) + o tap
        guard let outputUID = Self.resolvedOutputDeviceUID(preferred: outputDeviceUID) else {
            print("Erro ao obter UID do dispositivo de saída")
            return false
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Mixly Tap: \(name)",
            kAudioAggregateDeviceUIDKey as String: "sound.Mixly.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: outputUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapDriftCompensationKey as String: true,
                    kAudioSubTapUIDKey as String: description.uuid.uuidString
                ]
            ]
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard status == noErr, newAggregateID != kAudioObjectUnknown else {
            print("Erro ao criar dispositivo agregado para \(name): \(status)")
            return false
        }
        aggregateID = newAggregateID

        // 3. IO proc: copia o áudio capturado pelo tap para a saída aplicando o ganho
        let gainState = self.gainState
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, inInputData, _, outOutputData, _ in
            let gain = gainState.withLock { $0 }
            ProcessTap.render(input: inInputData, output: outOutputData, gain: gain)
        }
        guard status == noErr, ioProcID != nil else {
            print("Erro ao criar IO proc para \(name): \(status)")
            return false
        }

        // 4. Iniciar o fluxo de áudio
        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            print("Erro ao iniciar dispositivo agregado para \(name): \(status)")
            return false
        }

        return true
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: - Render (executa na thread de áudio)

    private static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        gain: Float
    ) {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputBuffers = UnsafeMutableAudioBufferListPointer(output)

        guard let inBuffer = inputBuffers.first(where: { $0.mData != nil }),
              let inData = inBuffer.mData,
              inBuffer.mNumberChannels > 0 else {
            for buffer in outputBuffers {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return
        }

        let inSamples = inData.assumingMemoryBound(to: Float.self)
        let inChannels = Int(inBuffer.mNumberChannels)
        let inFrames = Int(inBuffer.mDataByteSize) / (MemoryLayout<Float>.size * inChannels)

        for buffer in outputBuffers {
            guard let outData = buffer.mData, buffer.mNumberChannels > 0 else { continue }

            let outSamples = outData.assumingMemoryBound(to: Float.self)
            let outChannels = Int(buffer.mNumberChannels)
            let outFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
            let frames = min(inFrames, outFrames)

            memset(outData, 0, Int(buffer.mDataByteSize))

            for frame in 0..<frames {
                for channel in 0..<outChannels {
                    let inChannel = min(channel, inChannels - 1)
                    outSamples[frame * outChannels + channel] = inSamples[frame * inChannels + inChannel] * gain
                }
            }
        }
    }

    // MARK: - Helpers

    /// Resolve o UID a usar: o preferido, se ainda existir no sistema, ou o padrão como fallback.
    private static func resolvedOutputDeviceUID(preferred: String?) -> String? {
        if let preferred, deviceID(forUID: preferred) != nil {
            return preferred
        }
        return defaultOutputDeviceUID()
    }

    private static func deviceID(forUID uid: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var cfUID = uid as CFString
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr -> OSStatus in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), uidPtr, &size, &deviceID
            )
        }

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)

        guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid) == noErr else {
            return nil
        }

        return uid as String
    }
}
