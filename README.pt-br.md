# HiClaude

[English](README.md) | **Português**

App de menu bar para macOS que mantém as janelas de uso de 5h do seu plano
Claude sempre abertas — por conta, automaticamente. Swift + SwiftUI
(`MenuBarExtra`), sem dependências externas.

## Por quê

Os planos Claude (Pro/Max) abrem uma janela de uso de 5h a partir do primeiro
prompt. Quem usa pesado quer a janela já aberta na hora de sentar para
trabalhar — não gastar a primeira hora dela aquecendo. O HiClaude renova cada
conta sozinho, e nunca dispara se já existe uma janela ativa: ele detecta a
janela corrente passivamente pelos transcripts locais do Claude Code, sem
nenhuma chamada de rede própria.

## Recursos

- **Renovação por conta** — Off / **Automática** (encadeia janelas de 5h
  continuamente) / **Programada** (ancorada a uma hora de início diária, com
  uma pausa noturna natural de ~4h)
- **Multi-conta** — detecta cada pasta de config `~/.claude*`, mostra o
  e-mail logado, aceita apelidos
- **Mensagens configuráveis** — um prompt do Claude com modelo, esforço,
  safe-mode e pasta de trabalho selecionáveis — ou qualquer comando shell
- **Histórico** — disparos recentes com status e resposta expansível
- **Pausar/Retomar** global e **Iniciar com o Mac** opcional

## Requisitos

- macOS 13+
- [Claude Code](https://claude.com/claude-code) instalado e logado
- Para build a partir do código: Swift 5.9+ (Xcode ou Command Line Tools)

## Instalação

### Homebrew

```bash
brew tap hayashirafael/tap
brew trust --cask hayashirafael/tap/hiclaude
brew install --cask hiclaude   # depois: brew upgrade --cask hiclaude
```

### DMG

Baixe o `HiClaude-<versão>.dmg` da [última release](../../releases/latest) e
arraste o **HiClaude** para **Applications**.

> O HiClaude é assinado ad-hoc, não notarizado. Na primeira abertura o
> Gatekeeper pode bloquear: use **Ajustes do Sistema → Privacidade e
> Segurança → Abrir Assim Mesmo**, ou remova o quarantine com
> `xattr -dr com.apple.quarantine /Applications/HiClaude.app`.

### A partir do código

```bash
git clone https://github.com/hayashirafael/hiclaude.git
cd hiclaude
swift test            # suíte de testes
./scripts/make-app.sh # build/HiClaude.app (assinado ad-hoc)
./scripts/make-dmg.sh # build/HiClaude-<versão>.dmg (requer `brew install create-dmg`)
open build/HiClaude.app
```

## Uso

O HiClaude vive na menu bar (sem ícone no Dock). O ícone fica preenchido
enquanto há uma renovação armada, mostra `!` em erro e esmaece quando pausado;
opcionalmente mostra também o tempo até a próxima janela vencer.

O menu lista cada conta em renovação com o modo, o horário da próxima
renovação e o resultado do último disparo, além de **Pausar/Retomar**,
**Configurações…** e **Sair**.

**Configurações** é uma janela em sidebar com quatro seções:

- **Contas** — por conta: apelido, modo de renovação (Off / Automática /
  Programada), hora de início diária (só na Programada, padrão 09:00) e qual
  mensagem enviar
- **Mensagens** — a biblioteca de mensagens (prompt do Claude ou comando
  shell, cada uma com seu modelo/esforço/safe-mode/pasta de trabalho e um
  toggle de "mostrar resposta")
- **Histórico** — disparos recentes; clique numa linha para ler a resposta
  completa
- **Geral** — Iniciar com o Mac, tempo restante na menu bar

## Como funciona

Antes de cada disparo, o HiClaude lê os transcripts locais da conta em
`<conta>/projects/**.jsonl` (streaming linha a linha, por `mtime`) e
reconstrói a janela de 5h corrente. Se houver uma ativa, o disparo é pulado.

Um disparo executa:

```
claude -p --model <modelo> --effort <esforço> [--safe-mode] "<texto>"
```

com `CLAUDE_CONFIG_DIR` fixado na conta alvo. Os padrões — Haiku, esforço
baixo, `--safe-mode` (pula CLAUDE.md/skills/MCP) e a mensagem `1+1` — fazem
dele o ping mais barato possível que abre a janela. Mensagens shell rodam
pelo seu shell de login.

**Automática** arma no fim da janela detectada e encadeia a próxima.
**Programada** dispara na âncora diária + 0/5/10/15h (quatro janelas por dia,
deixando o gap de ~4h antes da próxima âncora) e recupera disparos perdidos
durante o sleep enquanto a janela deles ainda vale.
