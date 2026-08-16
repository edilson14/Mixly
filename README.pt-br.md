# Mixly

[English](README.md) | **Português (BR)**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
[![GitHub release](https://img.shields.io/github/v/release/edilson14/Mixly)](https://github.com/edilson14/Mixly/releases/latest)

**Mixly é um mixer de volume por aplicativo para macOS** — permite controlar o volume de cada aplicativo de forma independente, da mesma forma que o mixer de volume nativo do Windows funciona. O macOS nunca ofereceu isso nativamente; o Mixly adiciona esse recurso como um pequeno app na barra de menu.

Está ouvindo música em um app enquanto uma chamada de vídeo em outro está alta? Abaixe um sem mexer no outro, direto da barra de menu — sem precisar pausar nada ou vasculhar o ajuste de volume de cada app.

![Popup do Mixly na barra de menu — ajustando o volume do Discord e do Chrome de forma independente](docs/demo.gif)

## Instalação

Baixe o `.dmg` mais recente em [Releases](https://github.com/edilson14/Mixly/releases/latest) e arraste o `Mixly.app` para `/Applications`.

> **Nota:** este build não é assinado com um Apple Developer ID, então o Gatekeeper do macOS vai avisar na primeira abertura. Clique com o botão direito (ou Control-clique) no `Mixly.app` e escolha **Abrir** — ou vá em **Ajustes do Sistema → Privacidade e Segurança** e clique em **Abrir Mesmo Assim**. Só é preciso fazer isso uma vez.

## Funcionalidades

- **Mixer de volume por app** — veja todo app que estiver produzindo áudio e ajuste seu volume (ou silencie-o) independentemente dos outros.
- **Vive na barra de menu** — sem ícone no dock, sem janela para gerenciar. Clique no ícone, ajuste, pronto.
- **Atividade de áudio ao vivo** — a lista se atualiza automaticamente conforme os apps começam a emitir som.
- **Agrupamento de processos auxiliares** — processos auxiliares (ex: helpers de navegador) são agrupados sob o app pai, então vários processos do mesmo app aparecem como uma única entrada.

## Como funciona

O macOS não expõe um mixer de volume por app nativo, então o Mixly constrói um usando **Core Audio Process Taps**:

1. Ele enumera os processos que produzem áudio registrados no HAL do sistema (`kAudioHardwarePropertyProcessObjectList`) e os agrupa pela aplicação dona.
2. Quando você muda o volume de um app, o Mixly cria um **process tap** (`ProcessTap.swift`) para os processos daquele app com `muteBehavior = .mutedWhenTapped`, o que silencia a saída original do app.
3. Um dispositivo agregado privado combina o tap com o dispositivo de saída padrão do sistema. O IO proc do Mixly lê o áudio capturado, aplica o ganho escolhido e o renderiza de volta no dispositivo de saída real.
4. Definir o volume de volta para 100% remove o tap por completo, restaurando o caminho de áudio original do app.

Isso significa que o Mixly não apenas altera um valor de volume — ele de fato re-renderiza o fluxo de áudio capturado de cada app com o ganho definido.

> **Nota:** o macOS reporta a sessão de áudio de um app como ativa enquanto o app a mantiver aberta, o que para a maioria dos apps inclui o período em pausa — não só enquanto o som está realmente tocando. Por isso um app pode permanecer na lista do Mixly por um tempo depois de pausado; ele só desaparece quando o app libera totalmente a sessão de áudio (geralmente ao fechar).

## Requisitos

- macOS 26 (Tahoe) ou posterior
- Xcode 26+ para compilar
- Permissão de "Captura de Áudio", concedida no primeiro uso via **Ajustes do Sistema → Privacidade e Segurança → Gravação de Tela e Áudio do Sistema**

## Compilando a partir do código-fonte

```bash
git clone https://github.com/edilson14/Mixly.git
cd Mixly
xcodebuild build -scheme Mixly -configuration Release
```

## Compilando e empacotando um DMG

```bash
./build_and_distribute.sh YOUR_TEAM_ID
```

Veja [DISTRIBUTION.md](DISTRIBUTION.md) para o fluxo completo de build, assinatura e notarização.

## Estrutura do projeto

| Arquivo | Propósito |
|---|---|
| `MixlyApp.swift` | Ponto de entrada do app — configura a cena `MenuBarExtra` |
| `AudioKitController.swift` | Descobre processos de áudio, agrupa por app e gerencia os taps |
| `ProcessTap.swift` | Encapsula `AudioHardwareCreateProcessTap` e o dispositivo agregado usado para re-renderizar o áudio com ganho |
| `AudioKitAppView.swift` | UI do mixer por app (lista, sliders, mudo) |
| `ContentView.swift` | View raiz do popover da barra de menu |

## Licença

MIT — veja [LICENSE](LICENSE).
