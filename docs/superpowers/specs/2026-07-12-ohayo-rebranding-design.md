# Rebranding completo para Ohayo

**Data:** 2026-07-12  
**Status:** Aprovado para planejamento

## Objetivo

Renomear integralmente o aplicativo, o código, a distribuição e a documentação
para **Ohayo**. A mudança será um corte limpo: a nova versão não migrará dados
nem manterá compatibilidade com instalações anteriores.

## Decisões

- O produto público, o app e o executável se chamarão `Ohayo`.
- O repositório existente será renomeado para `hayashirafael/ohayo`, preservando
  commits, issues, releases e os redirecionamentos oferecidos pelo GitHub.
- O cask Homebrew será `ohayo`, no tap existente `hayashirafael/tap`.
- O pacote, módulo e target Swift serão `Ohayo`; o target de testes será
  `OhayoTests`.
- O bundle ID será `io.github.hayashirafael.Ohayo`.
- Os dados locais usarão `~/Library/Application Support/Ohayo` e as preferências
  usarão o domínio `io.github.hayashirafael.Ohayo`.
- O app será `Ohayo.app` e o instalador será `Ohayo-<versão>.dmg`.
- A primeira versão com a nova identidade será `1.0.0`, publicada pela tag
  `v1.0.0`.
- A identidade visual e o conteúdo do ícone atual serão preservados nesta
  mudança. Arquivos de imagem cujo nome contenha uma identidade anterior serão
  renomeados.

## Limite da limpeza

O conteúdo atual versionado não poderá conter referências às identidades
anteriores, independentemente de capitalização ou separadores. Isso inclui:

- código-fonte e testes;
- nomes de arquivos e diretórios;
- pacote, targets, imports, executável e resource bundle;
- bundle ID, subsystems de log, suites temporárias e nomes de arquivos
  temporários;
- scripts de build, DMG e Homebrew;
- workflows de CI e release;
- textos visíveis, notificações, comentários e documentação;
- README, `CONTEXT.md`, `CLAUDE.md`, ADRs, specs, planos e relatórios
  versionados.

O critério não se aplica ao histórico Git nem às releases antigas. Preservar o
repositório existente mantém esses registros históricos sem reescrevê-los.
Diretórios gerados e metadados internos do Git também ficam fora da varredura do
conteúdo atual.

## Instalação e dados locais

Ohayo será um aplicativo novo para o macOS:

- não lerá nem migrará preferências, contas, agendamentos, histórico, workspace
  ou login item de instalações anteriores;
- não conterá paths, bundle IDs, defaults ou código de compatibilidade legado;
- usará seu próprio diretório de suporte, domínio de preferências e lock de
  instância;
- exigirá que a única instalação atual conhecida seja removida completamente
  antes da instalação do Ohayo.

Os READMEs documentarão a remoção completa da instalação anterior e a instalação
limpa do Ohayo. Essas instruções poderão citar comandos com paths antigos apenas
separadamente, fora do conteúdo versionado, pois o requisito deste rebranding é
zero ocorrências no repositório atual. O procedimento operacional de remoção
será entregue ao usuário durante a publicação.

## Alterações estruturais

A implementação incluirá, no mínimo:

- mover o diretório-fonte do target executável para `Sources/Ohayo`;
- mover o diretório do target de testes para `Tests/OhayoTests`;
- renomear o arquivo do entry point para `OhayoApp.swift` e o tipo `@main` para
  `OhayoApp`;
- atualizar `Package.swift`, imports de teste e referências ao resource bundle;
- substituir nomes de produto em textos, notificações, logs, temporários e
  testes;
- simplificar `AppPaths` para conter somente paths do Ohayo, removendo qualquer
  migração ou fallback;
- gerar `build/Ohayo.app` com executável `Ohayo` e metadados coerentes;
- gerar `build/Ohayo-1.0.0.dmg` com volume e itens nomeados Ohayo;
- gerar `Casks/ohayo.rb` com URL, homepage, app, caveats e `zap` da nova
  identidade;
- atualizar o workflow para publicar o novo DMG e substituir o cask antigo pelo
  novo no tap;
- reescrever a documentação histórica versionada para descrever o estado atual
  sem preservar as identidades anteriores.

## Distribuição e sequência operacional

A mudança local será concluída e validada antes das operações externas. A
sequência será:

1. concluir a renomeação no checkout local;
2. executar toda a validação local;
3. renomear o repositório existente no GitHub para `ohayo`;
4. atualizar o remote local para `hayashirafael/ohayo`;
5. confirmar links e configuração do workflow após o rename;
6. atualizar o tap para remover o cask anterior e adicionar `ohayo`;
7. criar e enviar a tag `v1.0.0` somente quando o estado anterior estiver
   consistente;
8. confirmar a release e a instalação pelo cask `ohayo`.

Se uma operação falhar após o rename do repositório, o nome `ohayo` será mantido
e a publicação será interrompida antes de criar uma release parcial. A correção
continuará a partir desse estado, sem restaurar temporariamente a identidade
anterior.

## Verificação e critérios de aceite

A implementação só estará concluída quando:

1. `swift test` passar com pacote e targets Ohayo;
2. `Ohayo.app` for gerado com executável, display name, bundle ID e versão
   corretos;
3. `codesign --verify --deep --strict build/Ohayo.app` passar;
4. `Ohayo-1.0.0.dmg` for gerado e contiver o app correto;
5. o bundle for aberto localmente e o processo executado corresponder ao binário
   empacotado;
6. uma busca case-insensitive no conteúdo atual e nos nomes versionados não
   encontrar nenhuma identidade anterior;
7. o cask `ohayo` passar na validação disponível do Homebrew e apontar para o
   artefato correto;
8. o repositório remoto, os links dos READMEs e os workflows apontarem para
   `hayashirafael/ohayo`;
9. a tag `v1.0.0` produzir uma release íntegra com o DMG esperado;
10. uma instalação limpa pelo Homebrew abrir o Ohayo sem depender de nenhum dado
    da instalação removida.

## Fora de escopo

- criar um novo ícone ou reformular a identidade visual;
- migrar ou importar dados de instalações anteriores;
- manter alias, cask de transição ou compatibilidade entre instalações;
- criar um repositório novo e abandonar o histórico existente;
- reescrever commits, tags ou releases históricas.
