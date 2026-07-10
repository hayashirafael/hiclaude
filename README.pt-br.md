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
- **Multi-conta, Claude e Codex** — detecta cada pasta de config `~/.claude*`
  e uma conta Codex em `~/.codex` no primeiro launch (migração única); depois
  disso, novas contas são adicionadas a qualquer momento via "Adicionar
  conta…" — mostra o e-mail logado, aceita apelidos
- **Comandos configuráveis** — um prompt do Claude (modelo, esforço,
  safe-mode, pasta de trabalho), um prompt do Codex (modelo, esforço de
  raciocínio), ou qualquer comando shell
- **Horários** — tarefas independentes que disparam um comando em horários
  fixos × dias da semana, sem depender do estado de renovação de nenhuma conta
- **Histórico** — disparos recentes com status e resposta expansível
- **Pausar/Retomar** global e **Iniciar com o Mac** opcional

## Requisitos

- macOS 13+
- [Claude Code](https://claude.com/claude-code) instalado e logado
- [Codex CLI](https://github.com/openai/codex) instalado e logado (opcional,
  só para contas/comandos Codex)
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
renovação e o resultado do último disparo; uma linha da próxima tarefa
agendada (se houver); além de **Pausar/Retomar**, **Configurações…** e
**Sair**.

**Configurações** é uma janela em sidebar com cinco seções:

- **Contas** — por conta: apelido, modo de renovação (Off / Automática /
  Programada), hora de início diária (só na Programada, padrão 09:00) e qual
  comando enviar (escolha da biblioteca ou crie na hora)
- **Horários** — tarefas independentes: um comando disparado em horários
  fixos × dias da semana, sem depender do estado de renovação de nenhuma conta
- **Comandos** — a biblioteca de comandos (prompt do Claude, prompt do Codex,
  ou comando shell, cada um com seu modelo/esforço/raciocínio/safe-mode/pasta
  de trabalho e um toggle de "mostrar resposta")
- **Histórico** — disparos recentes; clique numa linha para ler a resposta
  completa
- **Geral** — Iniciar com o Mac, tempo restante na menu bar

## Como funciona

Antes de cada disparo Claude/Codex, o HiClaude lê os transcripts locais da
conta (`<conta>/projects/**.jsonl` no Claude, `sessions/**.jsonl` no Codex,
streaming linha a linha, por `mtime`) e reconstrói a janela de 5h corrente.
Se houver uma ativa, o disparo é pulado.

Um disparo Claude executa:

```
claude -p --model <modelo> --effort <esforço> [--safe-mode] "<texto>"
```

com `CLAUDE_CONFIG_DIR` fixado na conta alvo. Os padrões — Haiku, esforço
baixo, `--safe-mode` (pula CLAUDE.md/skills/MCP) e o comando `1+1` — fazem
dele o ping mais barato possível que abre a janela. Um disparo Codex executa
`codex exec --model <modelo> --sandbox read-only -c
model_reasoning_effort=<esforço> "<texto>"` com `CODEX_HOME` fixado no lugar.
Comandos shell rodam pelo seu shell de login.

Qual conta é Claude ou Codex é inferido pelo conteúdo da pasta, não pelo nome:
um `.claude.json` ou subpasta `projects/` indica Claude; um `auth.json` ou
subpasta `sessions/` indica Codex.

**Automática** arma no fim da janela detectada e encadeia a próxima.
**Programada** dispara na âncora diária + 0/5/10/15h (quatro janelas por dia,
deixando o gap de ~4h antes da próxima âncora) e recupera disparos perdidos
durante o sleep enquanto a janela deles ainda vale.

As tarefas de **Horários** rodam independentes de qualquer conta: cada uma
dispara seu comando nos horários fixos × dias da semana marcados. No wake (ou
no launch), uma tarefa dispara no máximo uma vez para recuperar a ocorrência
mais recente que perdeu — um sleep longo nunca gera uma rajada de disparos
atrasados.
