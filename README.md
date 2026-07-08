# HiClaude

App de menu bar para macOS que envia um "hi" ao Claude Code em horarios
agendados, iniciando a janela de 5h do seu plano Claude alinhada com o seu
expediente, sem desperdiçar prompt quando a janela ja esta ativa.

*macOS menu bar app that pings Claude Code on a schedule so your 5-hour usage
window starts when your workday does. It skips the ping if a window is already
active. English docs below.*

## Como funciona

O plano do Claude (Pro/Max) funciona em janelas de 5h que começam no primeiro
prompt enviado. O HiClaude roda `claude -p "hi"` em background nos horarios que
voce configurar. Antes de disparar, ele le os transcripts locais do Claude Code
(`~/.claude/projects/`) e reconstroi a janela de 5h corrente. Se ja houver uma
ativa, o disparo e pulado.

- Icone na menu bar: ativo, pausado ou erro
- Menu com ultimo disparo, proximo horario, janela ativa, "Enviar hi agora",
  pausar/retomar e iniciar com o Mac
- Se o Mac estava dormindo no horario, dispara ao acordar
- Notificacao do sistema apenas quando um disparo agendado falha

## Requisitos

- macOS 13+
- [Claude Code](https://claude.com/claude-code) instalado e logado

## Instalacao

1. Baixe o `HiClaude.zip` da [ultima release](../../releases/latest) e
   descompacte
2. Mova `HiClaude.app` para `/Applications`
3. Primeira abertura: clique-direito > **Abrir** (o app nao e notarizado)
4. No menu do balao, ative **Iniciar com o Mac** e configure os **Horarios...**

## Build a partir do codigo

```bash
git clone <repo> && cd hiclaude
swift test
./scripts/make-app.sh
```

O app bundleado fica em `build/HiClaude.app`.

## Limitacoes

- A deteccao de janela ativa so enxerga o uso do Claude Code nesta maquina.
  Sessoes iniciadas no navegador ou em outro computador nao sao detectadas; um
  "hi" redundante e inofensivo.
- Com o app fechado, nada dispara. O HiClaude e um app de menu bar, sem daemon.
- A build de v1 usa assinatura ad-hoc e nao e notarizada.

---

## English

HiClaude sends `claude -p "hi"` at times you configure, so your Claude plan's
5-hour usage window starts on schedule. Before firing, it passively reads Claude
Code's local transcripts to reconstruct the current 5-hour window. If one is
already active, the ping is skipped.

## Requirements

- macOS 13+
- [Claude Code](https://claude.com/claude-code) installed and logged in

## Install

1. Download `HiClaude.zip` from the [latest release](../../releases/latest) and
   unzip it
2. Move `HiClaude.app` to `/Applications`
3. First launch: right-click > **Open** (the app is not notarized)
4. In the menu bar bubble, enable **Iniciar com o Mac** and set times under
   **Horarios...**

## Build from source

```bash
git clone <repo> && cd hiclaude
swift test
./scripts/make-app.sh
```

The app bundle is generated at `build/HiClaude.app`.

## Known limitations

- Active window detection only sees Claude Code usage on this Mac. Browser
  sessions or sessions on another computer are not detected; a redundant "hi" is
  harmless.
- If the app is closed, nothing fires. HiClaude is a menu bar app, not a daemon.
- v1 is ad-hoc signed and not notarized.
