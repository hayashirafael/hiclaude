# HiClaude

App de menu bar para macOS que dispara `claude -p` em horários fixos para
iniciar a janela de uso de 5h do plano Claude — e pula o disparo se já houver
uma janela ativa. Swift + SwiftUI (`MenuBarExtra`), sem dependências externas.

## Requisitos

- macOS 13+
- [Claude Code](https://claude.com/claude-code) instalado e logado (o binário `claude` no `PATH`)
- Para build a partir do código: Swift 5.9+ (Xcode ou Command Line Tools)

## Instalação

### Via release

1. Baixe o `HiClaude.zip` da [última release](../../releases/latest) e descompacte
2. Mova `HiClaude.app` para `/Applications`
3. Na primeira abertura, clique-direito no app > **Abrir** (não é notarizado)

### A partir do código

```bash
git clone https://github.com/hayashirafael/hiclaude.git
cd hiclaude
swift test            # roda a suíte (43 testes)
./scripts/make-app.sh # gera build/HiClaude.app (assinado ad-hoc, LSUIElement)
open build/HiClaude.app
```

## Uso

O app fica na menu bar (sem ícone no Dock). Clique no balão para o menu:

- **Status** — próximo horário, `Pausado`, ou erro (CLI não encontrado / falha)
- **Último disparo** — sucesso, pulado (janela já ativa) ou falha
- **Enviar hi agora** — dispara manualmente na hora
- **Pausar / Retomar** — suspende os disparos agendados
- **Horários…** — abre a janela de configuração (adicionar/remover/editar horários)
- **Iniciar com o Mac** — registra como item de login (`SMAppService`)
- **Sair**

Horários são diários e configuráveis (default: 07:00). Se o Mac estava dormindo
no horário agendado, o disparo ocorre ao acordar (catch-up). Falha em disparo
agendado gera uma notificação do sistema.

## Como funciona

O plano Claude (Pro/Max) abre janelas de uso de 5h a partir do primeiro prompt.
Nos horários configurados, o HiClaude executa:

```
claude -p --model claude-haiku-4-5 --effort low --safe-mode "1+1"
```

Um ping mínimo em tokens (Haiku, esforço baixo, `--safe-mode` pula
CLAUDE.md/skills/MCP) — só o suficiente para abrir a janela.

Antes de disparar, ele lê passivamente os transcripts locais do Claude Code em
`~/.claude/projects/**.jsonl` (streaming linha a linha, por `mtime`) e
reconstrói a janela de 5h corrente. Se já houver uma ativa, o disparo é pulado.

## Limitações

- A detecção de janela ativa só enxerga o uso do Claude Code **nesta máquina**;
  sessões no navegador ou em outro computador não são vistas (o "hi" redundante
  é inofensivo).
- Sem daemon: com o app fechado, nada dispara.
- Build v1 é assinada ad-hoc e não notarizada.
