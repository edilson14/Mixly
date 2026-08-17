# Saída de áudio por aplicação (per-app output device)

## Contexto

O Mixly hoje só controla **volume** por app (`AudioKitController` + `ProcessTap`), sempre
redirecionando o áudio capturado para o dispositivo de saída padrão do sistema
(`ProcessTap.defaultOutputDeviceUID()`, hardcoded em `ProcessTap.swift:66`). A feature pedida
(branch `feature/per-app-audio-output`) é deixar o usuário escolher, por app, para **qual
dispositivo de saída** o áudio vai — ex: Spotify no fone USB, Chrome nos alto-falantes do Mac.

Decisão já tomada com o usuário: a seleção de saída por app é **só de sessão** (in-memory),
igual ao volume hoje — não persiste entre reinícios do Mixly.

Ponto de arquitetura chave: hoje um `ProcessTap` só existe enquanto o volume do app está < 100%
(`AudioKitController.swift:44-46`, otimização para não criar tap desnecessário). Para roteamento
funcionar, o tap precisa existir sempre que **volume < 1.0 OU um dispositivo não-padrão estiver
selecionado** — essa condição vira o novo critério de ciclo de vida do tap.

`Mixly/AudioUnitController.h/.m` é código legado não usado por nada em Swift — ignorar, não usar
como base.

## Sequência de implementação

### 1. `Mixly/AudioOutputDevice.swift` (novo arquivo)

Struct de modelo, no padrão de `AppAudioInfo` (`AudioKitController.swift:327-337`):

```swift
struct AudioOutputDevice: Identifiable, Equatable, Hashable {
    var id: String { uid }
    let uid: String
    let name: String
}
```

`static func listOutputDevices() -> [AudioOutputDevice]`, em duas camadas:

- **Camada CoreAudio (não testável por unit test)**: enumerar `kAudioHardwarePropertyDevices`
  (mesmo padrão de duas chamadas — `GetPropertyDataSize` + `GetPropertyData` — já usado em
  `AudioKitController.listAudioProcesses()`, `AudioKitController.swift:244-263`). Para cada
  `AudioObjectID`: checar capacidade de saída via `kAudioDevicePropertyStreamConfiguration`
  (`mScope: kAudioObjectPropertyScopeOutput`) somando `mNumberChannels` dos buffers (property de
  tamanho variável — não dá pra reusar o helper genérico `readProcessProperty<T>` de
  `AudioKitController.swift:294-312`, que assume `MemoryLayout<T>.size` fixo; precisa de alocação
  raw baseada no `GetPropertyDataSize`); pular se `kAudioDevicePropertyIsHidden` estiver setado;
  ler `kAudioDevicePropertyDeviceUID` (igual a `ProcessTap.defaultOutputDeviceUID()`,
  `ProcessTap.swift:198-209`) e `kAudioObjectPropertyName` (preferir a essa API sobre a
  deprecated `kAudioDevicePropertyDeviceNameCFString`).
  - Dispositivos agregados privados que o próprio `ProcessTap` cria (`isPrivate: true`,
    `ProcessTap.swift:75`) não aparecem em `kAudioHardwarePropertyDevices` — não precisa filtrar
    o próprio Mixly da lista.
- **Camada pura (testável)**: `static func filterAndSort(_:) -> [AudioOutputDevice]` — dedup por
  UID, descarta não-output/hidden, ordena por nome localizado. Vale um teste real em
  `MixlyTests/MixlyTests.swift` (hoje um scaffold vazio), já que não depende de hardware.

**Atualização da lista**: aproveitar o `Timer` de 2s já existente em `AudioKitController.init()`
(`AudioKitController.swift:26-30`) — chamar `listOutputDevices()` a cada `refresh()`. Não vale a
pena um listener (`AudioObjectAddPropertyListenerBlock`) para hot-plug: o projeto não usa nenhum
listener hoje, adicionaria complexidade de threading (callback fora da main queue, precisaria
saltar pra `@MainActor` pra tocar `@Published`), e 2s de cadência já é responsivo o suficiente.

### 2. `Mixly/ProcessTap.swift`

- Novo stored property `let outputDeviceUID: String?` e novo parâmetro no init
  (`ProcessTap.swift:28`): `init?(processObjectIDs:name:initialGain:outputDeviceUID: String? = nil)`
  — default `nil` mantém compatibilidade se algum call site não for atualizado imediatamente.
- `setup(name:)` vira `setup(name:outputDeviceUID:)`.
- Novo helper de resolução com fallback:
  ```swift
  private static func resolvedOutputDeviceUID(preferred: String?) -> String? {
      if let preferred, deviceID(forUID: preferred) != nil { return preferred }
      return defaultOutputDeviceUID()
  }
  private static func deviceID(forUID uid: String) -> AudioObjectID? {
      // kAudioHardwarePropertyTranslateUIDToDevice em kAudioObjectSystemObject,
      // qualifier = CFString(uid) -> AudioDeviceID; kAudioObjectUnknown = não existe
  }
  ```
- Trocar a chamada hardcoded em `ProcessTap.swift:66` (`Self.defaultOutputDeviceUID()`) por
  `Self.resolvedOutputDeviceUID(preferred: outputDeviceUID)`. O resultado alimenta tanto
  `kAudioAggregateDeviceMainSubDeviceKey` (linha 74) quanto o `kAudioSubDeviceUIDKey` dentro de
  `kAudioAggregateDeviceSubDeviceListKey` (linha 79) — só muda a origem do UID, o resto do
  dicionário do aggregate device continua igual.
- **Não** tentar reconfigurar o aggregate device em tempo real (mutar
  `kAudioAggregateDeviceSubDeviceListKey` via `AudioObjectSetPropertyData` com o IO proc rodando)
  — é comportamento não documentado/frágil. Trocar de dispositivo = destruir e recriar o tap
  inteiro, reusando exatamente o padrão que já existe pra dois outros casos (volume cruzando o
  limite de 1.0, `AudioKitController.swift:44-46`; mudança no conjunto de processos em
  `refresh()`, linhas 147-157).
- `teardown()` não precisa mudar — já derruba IO proc → aggregate → tap na ordem certa
  independente de qual dispositivo estava configurado.

### 3. `Mixly/AudioKitController.swift`

Novo estado (perto de `AudioKitController.swift:15-20`):
```swift
@Published var availableOutputDevices: [AudioOutputDevice] = []
private var selectedOutputDevices: [String: String] = [:]   // mesma key de taps/volumes
```

Extrair a lógica de ciclo de vida do tap (hoje só dentro de `setVolume`,
`AudioKitController.swift:40-64`) para helpers compartilhados, já que agora tem duas condições
independentes:

```swift
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
        lastError = "Não foi possível criar o tap para \(app.name). Verifique a permissão de Gravação de Áudio do Sistema em Ajustes > Privacidade e Segurança."
    }
}
```

`setVolume(for:volume:)` simplifica para: clamp, guardar `volumes[bundleID]`,
`syncTap(for: bundleID)`, `updatePublishedApps()`.

Nova API pública:
```swift
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
```

`refresh()` (`AudioKitController.swift:85-188`):
- Popular `availableOutputDevices = AudioOutputDevice.listOutputDevices()` a cada ciclo.
- **Reconciliação de dispositivo removido**: depois de montar a nova lista, comparar com
  `selectedOutputDevices` — se o UID selecionado não existe mais, remover a seleção e chamar
  `syncTap(for:)` para aquele app (fallback automático pro padrão em até ~2s, sem risco de crash).
- No bloco de recriação por mudança de processos (linhas 140-158), passar
  `outputDeviceUID: selectedOutputDevices[key]` na chamada `ProcessTap(...)` (linhas 150-154) —
  senão um respawn de helper (ex: Chrome) reverteria silenciosamente o roteamento escolhido.

`AppAudioInfo` (`AudioKitController.swift:327-337`): adicionar `var outputDeviceUID: String?`
(mesmo padrão de `volume`/`isMuted`, espelhado a partir de `selectedOutputDevices` tanto no
`compactMap` de `refresh()` quanto em `updatePublishedApps()` — que hoje só re-deriva
`volume`/`isMuted`, `AudioKitController.swift:190-198`, precisa re-derivar isso também pra
refletir a escolha imediatamente sem esperar o próximo tick do timer).

### 4. `Mixly/AudioKitAppView.swift`

- Novo closure em `AudioKitAppRow`: `let onOutputDeviceChange: (String?) -> Void`, e novo param
  `let availableDevices: [AudioOutputDevice]`, wireados em `AudioKitAppView.body`
  (`AudioKitAppView.swift:34-49`) como `controller.setOutputDevice(for: app.bundleIdentifier, deviceUID:)`
  e `controller.availableOutputDevices`.
- Widget: `Menu` com ícone SF Symbol `airplayaudio` (mesma família usada pelo próprio macOS pra
  escolha de saída), inserido depois do label de porcentagem na linha de controles existente
  (`AudioKitAppView.swift:101-126`), seguindo o padrão visual já existente (`.font(.system(size: 11))`,
  cor `.white.opacity(0.4)` quando no padrão / `accentColor` quando roteado — mesmo sinal visual
  já usado no `speaker.wave.3.fill`, linhas 117-119):
  ```swift
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
  ```
- Strings em português, no tom já usado (`"Nenhuma aplicação com áudio detectada"`, linha 23):
  `"Padrão do sistema"` pro item default; opcional `.help("Dispositivo de saída: ...")` no trigger.
- Polish opcional: esconder/desabilitar o menu quando `availableDevices.isEmpty` (só existe o
  padrão, nada pra escolher).

## Ordem de execução

1. `AudioOutputDevice.swift` (arquivo novo, sem dependentes ainda — dá pra checar com um
   `print(AudioOutputDevice.listOutputDevices())` temporário ou pelo teste puro de `filterAndSort`).
2. `ProcessTap.swift` — parâmetro `outputDeviceUID` com default `nil`; call sites existentes
   continuam compilando e se comportando exatamente igual a hoje.
3. `AudioKitController.swift` — estado novo, `needsTap`/`syncTap`/`createTap`,
   `setOutputDevice`/`getOutputDevice`, mudanças em `refresh()`, `AppAudioInfo.outputDeviceUID`.
4. `AudioKitAppView.swift` — o `Menu` e o wiring do novo closure.

## Verificação

Não há harness automatizado de CoreAudio, então a verificação é manual:

- **Setup de teste**: um segundo dispositivo de saída real (fone USB/Bluetooth) e/ou
  `brew install blackhole-2ch` pra um dispositivo virtual sempre disponível (UID estável,
  monitorável via um novo Audio Recording no QuickTime usando o BlackHole como fonte, ou um
  aggregate device no Audio MIDI Setup com medidor de nível).
- **Fluxo principal**: abrir dois apps de áudio ao mesmo tempo (ex: Spotify + uma aba do Chrome
  com vídeo). No Mixly, confirmar que o menu novo lista "Padrão do sistema" + os dispositivos
  reais/de teste. Rotear o Spotify só pro dispositivo de teste; confirmar que (a) o áudio aparece
  no medidor do dispositivo de teste, (b) os alto-falantes do Mac param de tocar o Spotify, (c) o
  Chrome continua tocando normalmente nos alto-falantes.
- **Interação com volume/mute**: com o Spotify roteado, mexer no slider (confirmar que o ganho
  ainda se aplica no dispositivo roteado) e mutar/desmutar (confirmar silêncio/retorno, e que a
  seleção de dispositivo sobrevive ao mute). Voltar pro "Padrão do sistema" e confirmar retorno
  aos alto-falantes do Mac.
- **Mudança de processos**: com um dispositivo custom selecionado num app cujos processos
  auxiliares mudam de PID em runtime (Chrome é o caso natural, ver comentário em
  `AudioKitController.swift:113-116`), fechar e reabrir o app; depois do próximo tick do
  `refresh()`, confirmar que o tap recriado ainda usa o dispositivo custom, não reverte pro padrão.
- **Robustez a remoção de dispositivo**: com um dispositivo físico plugável selecionado e
  tocando, desconectar no meio da reprodução; confirmar que o Mixly não trava/crasha e que em
  ~2s o checkmark do menu e `app.outputDeviceUID` voltam pro "Padrão do sistema".
- **Checagem de regressão**: pra um app sem nenhum dispositivo custom selecionado, confirmar que
  o comportamento do slider de volume é idêntico ao atual — tap só existe com volume < 100%,
  removido em 100% (ou seja, o refactor de `needsTap` não mudou nada pro caso de uso já existente).

### Arquivos principais
- `Mixly/ProcessTap.swift`
- `Mixly/AudioKitController.swift`
- `Mixly/AudioKitAppView.swift`
- `Mixly/AudioOutputDevice.swift` (novo)
- `MixlyTests/MixlyTests.swift` (teste puro opcional de `filterAndSort`)
