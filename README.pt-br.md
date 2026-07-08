# HiClaude

[English](README.md) | **Português**

App de menu bar para macOS que dispara `claude -p` em horários fixos para abrir a
janela de uso de 5h do plano Claude — e pula o disparo se já houver uma janela ativa.
Swift + SwiftUI (`MenuBarExtra`), sem dependências externas.

## Requisitos

- macOS 13+
- [Claude Code](https://claude.com/claude-code) instalado e logado (o binário `claude` no `PATH`)
- Para build a partir do código: Swift 5.9+ (Xcode ou Command Line Tools)

## Instalação

### Homebrew

```bash
brew tap hayashirafael/tap
brew trust --cask hayashirafael/tap/hiclaude
brew install --cask hiclaude
```

Para atualizar depois:

```bash
brew upgrade --cask hiclaude
```

O HiClaude é assinado ad-hoc, não notarizado. Na primeira abertura, o macOS
Gatekeeper pode bloquear o app; use **Ajustes do Sistema → Privacidade e
Segurança → Abrir Assim Mesmo** ou remova o quarantine:

```bash
xattr -dr com.apple.quarantine /Applications/HiClaude.app
```

### Via release (DMG)

1. Baixe o `HiClaude-<versão>.dmg` da [última release](../../releases/latest).
2. Abra o DMG e arraste o **HiClaude** para a pasta **Applications**.
3. Na primeira abertura: clique-direito no app → **Abrir** (o build é assinado
   ad-hoc, não notarizado, então o Gatekeeper avisa uma vez). Alternativa, remover
   o quarantine:
   ```bash
   xattr -dr com.apple.quarantine /Applications/HiClaude.app
   ```

Depois de instalado em `/Applications`, o HiClaude aparece no Spotlight e no
Launchpad (busque "HiClaude"), mesmo rodando só na menu bar.

### A partir do código

```bash
git clone https://github.com/hayashirafael/hiclaude.git
cd hiclaude
swift test            # roda a suíte de testes
./scripts/make-app.sh # gera build/HiClaude.app (assinado ad-hoc, LSUIElement)
./scripts/make-dmg.sh # gera build/HiClaude-<versão>.dmg (requer `brew install create-dmg`)
open build/HiClaude.app
```

O ícone do app é gerado no build a partir de `assets/AppIcon.png` (um único master
1024×1024); o script deriva todos os tamanhos do `.iconset` e compila o `.icns`.

## Uso

Fica na menu bar (sem ícone no Dock). Clique no balão para o menu:

- **Status** — próximo horário, `Pausado`, ou erro (CLI não encontrado / falha)
- **Último disparo** — sucesso, pulado (janela já ativa) ou falha
- **Enviar hi agora** — dispara manualmente
- **Pausar / Retomar** — suspende os disparos agendados
- **Mensagem** — escolhe a mensagem ativa a enviar; **Gerenciar…** abre a janela de configuração
- **Horários…** — abre a janela de configuração (adicionar/remover/editar horários e mensagens)
- **Iniciar com o Mac** — registra como item de login (`SMAppService`)
- **Sair**

Horários são diários e configuráveis (default: 07:00). Se o Mac estava dormindo no
horário agendado, o disparo ocorre ao acordar (catch-up). Falha em disparo agendado
gera uma notificação do sistema.

A mensagem enviada é configurável: mantenha uma lista de favoritos e selecione a ativa
no submenu **Mensagem**. O default (`1+1`) está sempre disponível e é usado como
fallback quando não há mensagem ativa válida.

## Como funciona

Os planos Claude (Pro/Max) abrem janelas de uso de 5h a partir do primeiro prompt. Nos
horários configurados, o HiClaude executa:

```
claude -p --model claude-haiku-4-5 --effort low --safe-mode "<mensagem ativa>"
```

Haiku, esforço baixo e `--safe-mode` (pula CLAUDE.md/skills/MCP) mantêm o custo baixo —
só o suficiente para abrir a janela. A mensagem é a que você deixou ativa (default
`1+1`, um ping mínimo em tokens).

Antes de disparar, ele lê passivamente os transcripts locais do Claude Code em
`~/.claude/projects/**.jsonl` (streaming linha a linha, por `mtime`) e reconstrói a
janela de 5h corrente. Se já houver uma ativa, o disparo é pulado.
