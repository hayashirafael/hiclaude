# Fluxo guiado de permissoes na primeira abertura

**Data:** 2026-07-12
**Status:** Aprovado para planejamento

## Objetivo

Apresentar, na primeira abertura do Ohayo, um fluxo guiado que ajude o usuario
a configurar as permissoes e integracoes usadas pelo app. O fluxo sera
informativo e acionavel, mas nunca impedira o acesso ao menu, as configuracoes
ou as demais funcoes do aplicativo.

O app solicitara apenas acessos que utiliza no momento. Novas permissoes poderao
ser acrescentadas ao mesmo modelo quando uma funcionalidade futura realmente
passar a depender delas.

## Experiencia da primeira abertura

- Na primeira execucao do app empacotado, uma janela de configuracao sera aberta
  automaticamente.
- A janela apresentara uma checklist com o nome, a finalidade e o estado de cada
  item.
- Cada solicitacao do macOS sera iniciada somente por uma acao explicita do
  usuario dentro do guia.
- O usuario podera escolher `Configurar depois` ou fechar a janela a qualquer
  momento, sem perder acesso ao aplicativo.
- Depois de dispensado, o guia nao abrira automaticamente nas execucoes
  seguintes.
- Uma entrada nas configuracoes permitira reabrir o guia e consultar os estados
  atuais.
- Fechar ou dispensar o guia registra apenas que a apresentacao inicial ocorreu;
  isso nao transforma permissoes pendentes em concluidas.

## Itens do guia

### Notificacoes

As notificacoes sao necessarias para avisar sobre execucoes e eventos do Ohayo.
O item exibira os estados `Nao configurado`, `Permitido` ou `Negado`.

Ao selecionar `Permitir notificacoes`, o Ohayo chamara a API nativa de
autorizacao. Depois da resposta, o estado sera consultado novamente e refletido
na interface. Se o acesso estiver negado, o guia explicara que a alteracao deve
ser feita nos Ajustes do Sistema e oferecera uma acao para abrir a area
apropriada quando houver uma URL publica e estavel no macOS suportado.

O caminho atual de entrega de notificacoes continuara tratando a ausencia de
autorizacao como fallback, mas a solicitacao principal ocorrera no guia.

### Automacao do Terminal

O Ohayo usa Apple Events para ativar e controlar o Terminal ao iniciar uma
sessao interativa. O bundle incluira `NSAppleEventsUsageDescription` com uma
explicacao objetiva dessa finalidade.

O macOS nao oferece uma consulta antecipada confiavel desse consentimento sem
tentar enviar um Apple Event. Por isso, o guia nao disparara automaticamente a
solicitacao. O item explicara que o sistema pedira acesso na primeira operacao e
oferecera `Testar Terminal`, uma acao manual e inofensiva que envia um comando
de verificacao ao Terminal. O teste nao iniciara Claude ou Codex nem alterara
dados do usuario.

O resultado sera apresentado como `Ainda nao testado`, `Disponivel` ou
`Bloqueado`. Uma recusa nao impedira o restante do Ohayo de funcionar.

### Abrir ao iniciar sessao

O guia reutilizara a integracao existente com `SMAppService` para oferecer
`Abrir o Ohayo ao iniciar sessao`. Esse item sera claramente marcado como
opcional e desativado por padrao. Ele e uma preferencia, nao uma permissao
necessaria para concluir o guia.

## Arquitetura

O fluxo sera dividido em unidades pequenas e testaveis:

- uma janela SwiftUI dedicada ao guia, separada da janela geral de
  configuracoes;
- um coordenador de primeira abertura responsavel somente por decidir quando
  abrir a janela;
- um modelo de item de configuracao com titulo, finalidade, estado e acao;
- um cliente de notificacoes que encapsula consulta e solicitacao ao
  `UNUserNotificationCenter`;
- um cliente de automacao que executa o teste explicito do Terminal e traduz o
  resultado para um estado de interface;
- persistencia em `UserDefaults` para registrar que o guia inicial foi
  dispensado;
- reutilizacao de `LoginItem` para a preferencia de inicializacao.

As dependencias que interagem com APIs do macOS serao injetaveis. A interface e
as regras de apresentacao poderao ser testadas sem exibir prompts reais do
sistema.

## Fluxo de dados

Ao iniciar, o coordenador consulta o indicador de primeira abertura. Se o guia
ainda nao foi dispensado, abre sua janela sem bloquear as demais cenas. Quando
a janela aparece, cada cliente consulta seu estado atual e atualiza a checklist.

Uma acao do usuario chama somente o cliente correspondente. Ao terminar, o
estado desse item e recarregado. `Configurar depois` e o fechamento da janela
persistem o indicador de apresentacao; a reabertura manual sempre consulta os
estados reais novamente.

## Erros e recusas

- Uma recusa sera exibida como estado valido, sem repeticao automatica do prompt.
- Falhas ao consultar uma API do sistema serao exibidas no item afetado e nao
  interromperao os demais.
- O teste do Terminal tera resultado explicito e nao sera considerado concluido
  apenas porque o AppleScript foi iniciado.
- Ambientes sem bundle valido, como certas execucoes de desenvolvimento, nao
  tentarao registrar login item nem abrir automaticamente o guia.
- O app nao solicitara Acessibilidade, Gravacao de Tela, Calendario, Arquivos ou
  qualquer outra permissao sem uma dependencia funcional concreta.

## Localizacao e documentacao

Todos os textos visiveis serao adicionados em portugues e ingles pelo mecanismo
de localizacao existente. `README.md` e `README.pt-br.md` documentarao o guia,
as permissoes utilizadas e como reabri-lo.

## Testes

Os testes cobrirao:

- abertura automatica apenas antes de o guia ser dispensado;
- persistencia e reabertura manual;
- mapeamento dos estados de notificacao;
- atualizacao do estado depois de permitir ou negar notificacoes;
- resultados disponivel, bloqueado e erro no teste do Terminal;
- independencia entre os itens quando uma integracao falha;
- opcionalidade do login item;
- ausencia de solicitacoes automaticas de permissao.

A verificacao final incluira `swift test`, geracao do bundle, validacao com
`codesign --verify --deep --strict build/Ohayo.app` e uma verificacao manual da
primeira abertura no app empacotado.

## Criterios de aceite

1. Uma instalacao limpa abre o guia automaticamente uma unica vez.
2. O usuario consegue usar o app, fechar o guia ou configurar depois em qualquer
   momento.
3. Nenhum prompt do macOS aparece sem acao explicita do usuario no guia ou uso
   direto da funcionalidade correspondente.
4. O estado de notificacoes reflete a configuracao real do sistema.
5. O teste manual do Terminal provoca o consentimento quando necessario e
   informa corretamente sucesso, recusa ou erro.
6. O guia pode ser reaberto pelas configuracoes.
7. Recusas e falhas isoladas nao bloqueiam o app nem os outros itens.
8. Nenhuma permissao sem uso atual e solicitada.

## Fora de escopo

- tornar qualquer permissao obrigatoria para usar o Ohayo;
- solicitar preventivamente permissoes de funcionalidades futuras;
- criar um onboarding geral de produto alem das permissoes e integracoes;
- alterar a semantica das execucoes agendadas ou interativas;
- abrir repetidamente o guia enquanto houver itens pendentes.
