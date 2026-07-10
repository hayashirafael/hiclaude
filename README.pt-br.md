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

- **Agendamentos unificados** — um único conceito para tudo que é agendado.
  Cada agendamento carrega um comando embutido e uma repetição: **Contínua**
  (encadeia janelas de 5h 24/7 — a antiga renovação automática) ou **Horários
  fixos** (horários × dias da semana). Tudo na seção **Horários**
- **Comandos configuráveis** — um prompt do Claude (modelo, esforço,
  safe-mode, pasta de trabalho), um prompt do Codex (modelo, esforço de
  raciocínio), ou qualquer comando shell — embutido direto no agendamento
- **Multi-conta, Claude e Codex** — as pastas padrão (`~/.claude` e
  `~/.codex`) são sempre detectadas; outras pastas `~/.claude*` entram uma
  única vez, no primeiro launch, e daí em diante novas contas são adicionadas
  a qualquer momento via "Adicionar conta…" — mostra o e-mail logado, aceita
  apelidos
- **Histórico** — disparos recentes com status e resposta expansível (detalhe
  completo do erro nas falhas)
- **Idioma** — inglês por padrão, com opção para português nas Configurações
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
enquanto há uma janela ativa, mostra `!` em erro e esmaece quando pausado;
opcionalmente mostra também o tempo até a próxima janela vencer.

O menu lista cada conta com um agendamento ativo — o horário do próximo
disparo e o resultado do último; uma linha da próxima tarefa (se houver);
além de **Pausar/Retomar**, **Configurações…** e **Sair**.

**Configurações** é uma janela em sidebar com quatro seções:

- **Contas** — informativa: por conta, a identidade logada / apelido, o
  provedor, a pasta local e quantos agendamentos ativos miram a conta.
  Adicione ou remova contas aqui
- **Horários** — a lista única de agendamentos. Cada um tem nome, um tipo
  (Claude / Codex / comando shell) com sua config, uma conta e uma repetição —
  **Contínua** (uma renovação da janela de 5h, no máximo uma por conta) ou
  **Horários fixos** (horários × dias da semana). Um único formulário cria ou
  edita qualquer um deles
- **Histórico** — disparos recentes; clique numa linha para ler a resposta
  completa ou o detalhe do erro
- **Geral** — Iniciar com o Mac, tempo restante na menu bar e Idioma (inglês
  ou português)

## Como funciona

Antes de cada disparo Claude/Codex, o HiClaude lê os transcripts locais da
conta (`<conta>/projects/**.jsonl` no Claude, `sessions/**.jsonl` no Codex,
streaming linha a linha, por `mtime`) e reconstrói a janela de 5h corrente.
Se houver uma ativa, o disparo é pulado. A janela do Claude começa na hora
cheia da primeira mensagem (espelhando como o plano contabiliza); a do Codex
começa no horário exato.

Um disparo Claude executa:

```
claude -p --model <modelo> --effort <esforço> [--safe-mode] "<texto>"
```

com `CLAUDE_CONFIG_DIR` fixado na conta alvo. Os padrões — Haiku, esforço
baixo, `--safe-mode` (pula CLAUDE.md/skills/MCP) e o comando `1+1` — fazem
dele o ping mais barato possível que abre a janela. Um disparo Codex executa
`codex exec [--model <modelo>] --sandbox read-only [-c
model_reasoning_effort=<esforço>] "<texto>"` com `CODEX_HOME` fixado no lugar,
e tem seu próprio padrão mínimo `1+1` embutido. Quando você deixa o modelo (ou
o raciocínio) do Codex em branco, o HiClaude omite a flag para o default da
própria conta (`config.toml`) valer — o único valor garantidamente aceito pelo
plano da conta. Comandos shell rodam pelo seu shell de login.

Qual conta é Claude ou Codex é inferido pelo conteúdo da pasta, não pelo nome:
um `.claude.json` ou subpasta `projects/` indica Claude; um `auth.json` ou
subpasta `sessions/` indica Codex.

Um agendamento **Contínuo** arma no fim da janela detectada e encadeia a
próxima, 24/7. Um agendamento de **Horários fixos** dispara nos seus horários ×
dias da semana; no wake (ou no launch) ele dispara no máximo uma vez para
recuperar a ocorrência mais recente que perdeu — um sleep longo nunca gera uma
rajada de disparos atrasados. A antiga renovação *Programada* (âncora diária +
0/5/10/15h) é apenas um agendamento de horários fixos com quatro horários após
a migração.
