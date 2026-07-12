# HiYashi

[English](README.md) | **Português**

App de menu bar para macOS que mantém as janelas de uso de 5h do seu plano
Claude sempre abertas — por conta, automaticamente. Swift + SwiftUI
(`MenuBarExtra`), sem dependências externas.

## Por quê

Os planos Claude (Pro/Max) abrem uma janela de uso de 5h a partir do primeiro
prompt. Quem usa pesado quer a janela já aberta na hora de sentar para
trabalhar — não gastar a primeira hora dela aquecendo. O HiYashi renova cada
conta sozinho, e a renovação contínua nunca dispara de forma redundante se já
existe uma janela ativa: ele detecta a janela corrente passivamente pelos
transcripts locais do Claude Code, sem nenhuma chamada de rede própria.

## Recursos

- **Agendamentos unificados** — um único conceito para tudo que é agendado.
  Cada agendamento carrega um comando embutido e uma repetição: **Contínua**
  (encadeia janelas de 5h 24/7 — a antiga renovação automática) ou **Horários
  fixos** (horários × dias da semana). Tudo na seção **Horários**
- **Comandos configuráveis** — um prompt do Claude (modelo, esforço,
  safe-mode, pasta de trabalho), um prompt do Codex (modelo, esforço de
  raciocínio, pasta de trabalho), ou qualquer comando shell — embutido direto
  no agendamento. Prompts Claude/Codex abrem no Terminal.app por padrão, para
  você continuar interagindo na mesma sessão; se desligar essa opção, rodam em
  modo batch
- **Multi-conta, Claude e Codex** — as pastas padrão (`~/.claude`, `~/.codex`)
  são detectadas automaticamente quando existem; outras pastas `~/.claude*`
  entram uma única vez, no primeiro launch, e daí em diante novas contas são
  adicionadas a qualquer momento via "Adicionar conta…" — mostra o e-mail
  logado, aceita apelidos
- **Histórico** — disparos recentes com status e resposta expansível (detalhe
  completo do erro nas falhas); notificações do macOS opcionais em falhas e
  respostas, além de notificações de sucesso opt-in por agendamento
- **Idioma** — inglês por padrão, com opção para português nas Configurações
- **Pausar/Retomar** por conta (a partir do painel do menu) e **Iniciar com o
  Mac** opcional

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

Baixe o `HiYashi-<versão>.dmg` da [última release](../../releases/latest) e
arraste o **HiYashi** para **Applications**.

> O HiYashi é assinado ad-hoc, não notarizado. Na primeira abertura o
> Gatekeeper pode bloquear: use **Ajustes do Sistema → Privacidade e
> Segurança → Abrir Assim Mesmo**, ou remova o quarantine com
> `xattr -dr com.apple.quarantine /Applications/HiYashi.app`.

### A partir do código

```bash
git clone https://github.com/hayashirafael/hiclaude.git
cd hiclaude
swift test            # suíte de testes
./scripts/make-app.sh # build/HiYashi.app (assinado ad-hoc)
./scripts/make-dmg.sh # build/HiYashi-<versão>.dmg (requer `brew install create-dmg`)
open build/HiYashi.app
```

## Uso

O HiYashi vive na menu bar (sem ícone no Dock). O ícone fica preenchido
enquanto alguma conta tem janela ativa, mostra `!` em erro e esmaece quando
todas as contas agendadas estão pausadas; opcionalmente mostra também o tempo
até a próxima janela vencer entre elas.

Clicar no ícone abre um painel com um card por conta que tem agendamento
ativo: ícone do provedor com uma bolinha de status (verde = janela ativa,
cinza = aguardando, laranja = pausada), tempo restante na janela de 5h (ou
"—") e uma linha "nome · horário" com o próximo evento. Passar o mouse sobre
um card permite pausar/retomar aquela conta, ou ir direto para as tarefas ou
o histórico dela. O rodapé tem **Tarefas**, **Histórico** e
**Configurações…**; o cabeçalho mostra um aviso se algum CLI estiver
faltando, além de **Sair**.

**Configurações** é uma janela em sidebar com quatro seções:

- **Contas** — informativa: por conta, a identidade logada / apelido, o
  provedor com seu ícone, a pasta local e quantos agendamentos ativos miram a conta.
  Adicione ou remova contas aqui
- **Tarefas** — a lista única de agendamentos. Cada um tem nome, um tipo
  (Claude / Codex / comando shell) com sua config, uma conta e uma repetição —
  **Contínua** (uma renovação da janela de 5h, no máximo uma por conta) ou
  **Horários fixos** (horários × dias da semana). Um único formulário cria ou
  edita qualquer um deles; novos agendamentos começam com o campo de comando
  vazio. Entrar por um card de conta no painel do menu filtra essa lista para
  a conta, com um chip para limpar o filtro
- **Histórico** — disparos recentes em cards com status, ícone do provedor,
  modelo, apelido/e-mail da conta, comando, resposta e detalhes de erro;
  filtrável por conta do mesmo jeito que Tarefas
- **Geral** — Iniciar com o Mac, tempo restante na menu bar, Idioma (inglês
  ou português) e a versão do app

## Como funciona

Para gerenciar as renovações contínuas, o HiYashi lê os transcripts locais da
conta (`<conta>/projects/**.jsonl` no Claude, `sessions/**.jsonl` no Codex,
streaming linha a linha, por `mtime`) e reconstrói a janela de 5h corrente. Se
houver uma ativa, somente uma renovação contínua redundante é pulada; horários
fixos sempre executam. A janela começa no horário exato da primeira mensagem
e dura 5h (como o plano contabiliza — o `/usage` reseta exatamente 5h após a
primeira mensagem).

Um disparo Claude executa:

```
claude -p --model <modelo> --effort <esforço> [--safe-mode] "<texto>"
```

com `CLAUDE_CONFIG_DIR` fixado na conta alvo quando o agendamento está em modo
batch. Por padrão, Claude/Codex abrem no Terminal.app sem `-p` / `exec`, usando
o mesmo prompt e ambiente para deixar a sessão interativa aberta; um horário
fixo interativo abre no horário agendado mesmo quando a conta já tem janela
ativa. Sem diretório de trabalho definido, as sessões interativas abrem em
`~/Library/Application Support/HiYashi/workspace` (nunca no home, cujo trust o
Claude Code só mantém por sessão), e o HiYashi pré-confia a pasta no
`.claude.json` da conta — e pré-aprova os imports externos do `CLAUDE.md` —
para que nem o prompt "do you trust this folder?" nem o "allow external
imports?" travem a sessão não-supervisionada.
Só uma instância do HiYashi roda por vez: uma segunda aberta avisa e encerra
(duas instâncias disparariam os agendamentos em dobro).
Os padrões —
Haiku, esforço baixo, `--safe-mode` (pula CLAUDE.md/skills/MCP) e o comando
`1+1` — fazem dele o ping mais barato possível que abre a janela. Um disparo
Codex em batch executa `codex exec [--model <modelo>] --sandbox read-only [-c
model_reasoning_effort=<esforço>] "<texto>"` com `CODEX_HOME` fixado no lugar,
e tem seu próprio padrão mínimo `1+1` embutido. Quando você deixa o modelo (ou
o raciocínio) do Codex em branco, o HiYashi omite a flag para o default da
própria conta (`config.toml`) valer — o único valor garantidamente aceito pelo
plano da conta. Comandos shell rodam pelo seu shell de login.

Qual conta é Claude ou Codex é inferido pelo conteúdo da pasta, não pelo nome,
nesta ordem: um `.claude.json` indica Claude; senão um `auth.json` indica
Codex; senão uma subpasta `projects/` indica Claude; senão uma subpasta
`sessions/` indica Codex. Ou seja, `auth.json` vence `projects/` quando os dois
existem.

Um agendamento **Contínuo** arma no fim da janela detectada e encadeia a
próxima, 24/7; uma tentativa redundante é pulada enquanto a janela da conta
ainda está ativa. Um agendamento de **Horários fixos** sempre dispara nos seus
horários × dias da semana, tanto em batch quanto no modo interativo. No wake,
horários fixos disparam no máximo uma vez para recuperar a ocorrência mais
recente que perdeu — um sleep longo nunca gera uma rajada de disparos
atrasados, e o launch em si nunca reproduz ocorrências perdidas antes dele.
A antiga renovação *Programada* (âncora diária +
0/5/10/15h) é apenas um agendamento de horários fixos com quatro horários após
a migração.
