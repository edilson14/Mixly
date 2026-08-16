//
//  AudioUnitController.h
//  MacMixer
//

#ifndef AudioUnitController_h
#define AudioUnitController_h

#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>

// Estrutura para armazenar informações do ganho
typedef struct {
    AudioUnit audioUnit;
    Float32 gain;
    pid_t processID;
} AudioUnitGainInfo;

#ifdef __cplusplus
extern "C" {
#endif

// Função para definir o ganho de um dispositivo de áudio
OSStatus SetAudioDeviceGain(AudioDeviceID deviceID, Float32 gain);

// Função para obter o ganho atual
OSStatus GetAudioDeviceGain(AudioDeviceID deviceID, Float32 *gain);

// Função para obter o ID do dispositivo de saída padrão
AudioDeviceID GetDefaultOutputDevice(void);

// Função para listar todos os dispositivos de áudio
void ListAudioDevices(void);

// Função para obter volume em dB
OSStatus GetAudioDeviceVolumeDB(AudioDeviceID deviceID, Float32 *volumeDB);

// Função para definir volume em dB
OSStatus SetAudioDeviceVolumeDB(AudioDeviceID deviceID, Float32 volumeDB);

#ifdef __cplusplus
}
#endif

#endif /* AudioUnitController_h */
