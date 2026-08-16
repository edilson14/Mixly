//
//  AudioUnitController.m
//  Mixly
//

#include "AudioUnitController.h"
#include <stdio.h>
#include <string.h>
#include <math.h>

// Função auxiliar para converter ganho linear para dB
static Float32 LinearToDecibels(Float32 linear) {
    if (linear <= 0.0) return -96.0;
    return 20.0 * log10f(linear);
}

// Função auxiliar para converter dB para ganho linear
static Float32 DecibelsToLinear(Float32 decibels) {
    return powf(10.0, decibels / 20.0);
}

// Obter o ID do dispositivo de saída padrão
AudioDeviceID GetDefaultOutputDevice(void) {
    AudioDeviceID deviceID = kAudioDeviceUnknown;
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 size = sizeof(AudioDeviceID);
    OSStatus status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address,
        0,
        NULL,
        &size,
        &deviceID
    );
    
    if (status != kAudioHardwareNoError) {
        fprintf(stderr, "Erro ao obter dispositivo padrão: %d\n", (int)status);
        return kAudioDeviceUnknown;
    }
    
    return deviceID;
}

// Definir o ganho (volume) de um dispositivo
OSStatus SetAudioDeviceGain(AudioDeviceID deviceID, Float32 gain) {
    // Garantir que o ganho está entre 0.0 e 1.0
    Float32 clampedGain = fmaxf(0.0f, fminf(1.0f, gain));
    
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyVolumeScalar,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 size = sizeof(Float32);
    
    OSStatus status = AudioObjectSetPropertyData(
        deviceID,
        &address,
        0,
        NULL,
        size,
        &clampedGain
    );
    
    if (status != kAudioHardwareNoError) {
        fprintf(stderr, "Erro ao definir ganho: %d\n", (int)status);
    } else {
        fprintf(stdout, "Volume definido para %.2f%%\n", clampedGain * 100.0f);
    }
    
    return status;
}

// Obter o ganho atual
OSStatus GetAudioDeviceGain(AudioDeviceID deviceID, Float32 *gain) {
    if (gain == NULL) {
        return paramErr;
    }
    
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyVolumeScalar,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 size = sizeof(Float32);
    
    OSStatus status = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        NULL,
        &size,
        gain
    );
    
    if (status != kAudioHardwareNoError) {
        fprintf(stderr, "Erro ao obter ganho: %d\n", (int)status);
        *gain = 0.0f;
    }
    
    return status;
}

// Obter volume em dB
OSStatus GetAudioDeviceVolumeDB(AudioDeviceID deviceID, Float32 *volumeDB) {
    if (volumeDB == NULL) {
        return paramErr;
    }
    
    Float32 gainLinear = 0.0f;
    OSStatus status = GetAudioDeviceGain(deviceID, &gainLinear);
    
    if (status == kAudioHardwareNoError) {
        *volumeDB = LinearToDecibels(gainLinear);
    }
    
    return status;
}

// Definir volume em dB
OSStatus SetAudioDeviceVolumeDB(AudioDeviceID deviceID, Float32 volumeDB) {
    Float32 gainLinear = DecibelsToLinear(volumeDB);
    return SetAudioDeviceGain(deviceID, gainLinear);
}

// Listar todos os dispositivos de áudio
void ListAudioDevices(void) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject,
        &address,
        0,
        NULL,
        &dataSize
    );
    
    if (status != kAudioHardwareNoError) {
        fprintf(stderr, "Erro ao listar dispositivos: %d\n", (int)status);
        return;
    }
    
    UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
    AudioDeviceID *deviceIDs = (AudioDeviceID *)malloc(dataSize);
    
    status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address,
        0,
        NULL,
        &dataSize,
        deviceIDs
    );
    
    if (status == kAudioHardwareNoError) {
        printf("Dispositivos de áudio encontrados: %d\n", deviceCount);
        
        for (UInt32 i = 0; i < deviceCount; i++) {
            AudioDeviceID deviceID = deviceIDs[i];
            
            // Obter nome do dispositivo
            CFStringRef deviceName = NULL;
            AudioObjectPropertyAddress nameAddress = {
                kAudioDevicePropertyDeviceNameCFString,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            
            UInt32 nameSize = sizeof(CFStringRef);
            AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                NULL,
                &nameSize,
                &deviceName
            );
            
            if (deviceName != NULL) {
                const char *nameC = CFStringGetCStringPtr(deviceName, kCFStringEncodingUTF8);
                printf("  Dispositivo %d: %s (ID: %d)\n", i, nameC ? nameC : "Unknown", deviceID);
                CFRelease(deviceName);
            }
        }
    }
    
    free(deviceIDs);
}
