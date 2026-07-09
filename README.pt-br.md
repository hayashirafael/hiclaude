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

Fica na menu bar (sem ícone no Dock). O ícone se enche/esvazia refletindo a janela
corrente de 5 horas; mostra um `!` de erro se a CLI não for encontrada, e fica
esmaecido se pausado.

Clique no ícone do menu para ações rápidas:

- **Status** — horário do próximo disparo e minutos restantes na janela de 5 horas
- **Linhas de renovação** (`↻`) — horário da próxima renovação automática de cada conta
- **Último hi** — clicável quando há resposta salva; abre a resposta
- **Enviar hi agora** — dispara manualmente
- **Pausar / Retomar** — suspende todos os disparos agendados e renovações automáticas (afeta todas as contas)
- **Mensagem** — escolher rápido a mensagem ativa, ou **Gerenciar…** para abrir Configurações
- **Configurações…** — abre a janela de configuração
- **Sair**

### Janela de Configurações

A janela de **Configurações** tem quatro abas:

- **Horários** — adicionar/remover/editar horários diários de disparo (default: 07:00). Cada horário
  pode fixar uma mensagem específica ou seguir a mensagem ativa global. Se o Mac estava
  dormindo, o disparo ocorre ao acordar (catch-up).
- **Mensagens** — gerenciar a lista de mensagens. Defina uma como ativa (é o default em cada
  horário, a menos que sobrescrito). Cada mensagem tem um toggle **Mostrar resposta** para
  exibir a resposta na menu bar após o disparo.
- **Histórico** — ver os últimos 20 disparos com horários, status e a mensagem enviada. Clique
  em qualquer linha para expandir e ler a resposta completa.
- **Geral** — defina a conta padrão para disparos, toggle "Iniciar com o Mac" (`SMAppService`),
  mostrar minutos restantes na menu bar e ativar/desativar renovação automática por conta.

### Renovação Automática

Quando ativada em **Geral**, cada conta renova automaticamente janelas de 5 horas enviando
uma mensagem default (`1+1`) a cada 5 horas. Pausar suspende todas as renovações. O horário
da próxima renovação de cada conta é mostrado no menu (ex.: "↻ Renova às 18:00 (.claude)")
apenas como informação.

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
