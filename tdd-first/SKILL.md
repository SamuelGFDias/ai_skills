---
name: tdd-first
description: Use quando a demanda exigir implementacao de codigo e a abordagem deve priorizar TDD, escrevendo testes antes do codigo de producao. Cobre o primeiro movimento por tipo de operacao (correcao, feature, mudanca de comportamento, refatoracao), deteccao do runner de testes e o relatorio de evidencia RED/GREEN.
---

# Skill: tdd-first

**Tipo:** internal

## Quando executar

Ao implementar, corrigir ou refatorar codigo de producao, inclusive quando o `arquiteto` indicar esta skill no prompt de um executor (regra 5). Tambem ao revisar uma entrega, para conferir se o comportamento novo tem teste.

Ao receber uma demanda de implementacao, adote TDD como fluxo padrao: escreva primeiro o teste que descreve o comportamento esperado, veja o teste falhar, implemente o minimo necessario para passar, e refatore mantendo a suite verde.

## Primeiro movimento por tipo de operacao

Identifique o tipo antes de comecar. Ele decide o primeiro passo:

| tipo | primeiro movimento |
|---|---|
| correcao de defeito | reproduzir o defeito num teste que falha, antes de tocar no codigo de producao |
| feature nova | teste do comportamento esperado |
| mudanca de comportamento existente | alterar o teste antigo junto com o codigo; nunca deixa-lo verde por fixture herdada |
| refatoracao | testes verdes antes e depois, sem mudar teste nenhum |

Se nao houver teste possivel (script de infra, texto, configuracao), declare qual e a verificacao substituta.

## Regra principal

Antes de alterar codigo de producao:

- identifique o comportamento esperado
- escreva ou ajuste o teste que expresse esse comportamento
- execute o teste alvo e confirme a falha inicial quando isso for viavel
- so depois implemente a mudanca de producao

## Passo 0: detectar o runner de testes

Antes de escrever o teste, descubra como o projeto roda testes, em vez de supor:

- .NET: projeto de teste em `tests/` ou `*.Tests.csproj`; `dotnet test <projeto>`. Com `.slnx`, `dotnet test` pode exigir `--solution`. Em projeto da SES-RJ, siga `dotnet-unit-tests`/`dotnet-integration-tests`.
- Angular: `package.json` (`test`, `test:ci`), `karma.conf.js`, `jest.config.*` ou `vitest.config.*`.
- Python: `pyproject.toml`, `pytest.ini`, `tox.ini`.
- Outros: o `AGENTS.md`/`README.md` do repo, ou o pipeline de CI.

Rode so o teste alvo (filtro por nome ou projeto), nao a suite inteira, enquanto estiver no ciclo.

## Ciclo obrigatorio

### 1. Red

- Crie um teste pequeno, focado e legivel.
- O teste deve falhar pelo motivo correto. Falha por erro de compilacao, import ou setup nao conta como RED: corrija o setup e rode de novo ate a falha ser a asserção do comportamento.
- Prefira cobrir comportamento observavel, nao detalhes acidentais de implementacao.

### 2. Green

- Implemente a menor mudanca correta para fazer o teste passar.
- Evite refatoracoes amplas antes de estabilizar o comportamento.
- Nao introduza abstrações desnecessarias nesta etapa.

### 3. Refactor

- Limpe nomes, remova duplicacao relevante e melhore estrutura.
- Preserve o comportamento validado.
- Reexecute os testes apos refatorar.

## Diretrizes de escrita de testes

- Cada teste deve descrever uma regra de negocio, contrato ou comportamento relevante.
- Use nomes de teste claros, orientados ao cenario e resultado esperado.
- Prefira testes pequenos e independentes: cada teste prepara os proprios dados e nao depende da ordem de execucao nem do estado deixado por outro.
- Use doubles apenas quando ajudarem a isolar o comportamento do caso de uso.
- Nao masque defeitos com mocks excessivos ou asserts vagos.
- Cubra, alem do caminho feliz, os casos de borda e os cenarios de erro (entrada invalida, recurso ausente, timeout).
- Em UI e e2e, use seletores semanticos (papel, rotulo, texto visivel, `data-testid`), nao classes CSS nem estrutura de markup.

## Prioridade por tipo de teste

- Para regras de negocio e services: priorize testes unitarios.
- Para integracao entre camadas, persistencia ou contratos HTTP: adicione testes de integracao quando o risco justificar.
- Para UI: teste comportamento visivel e integracoes relevantes, sem acoplar o teste demais a detalhes de markup.
- Cobertura e sinal, nao meta: um numero alto com asserts vagos vale menos que poucos testes que falhariam sem a mudanca.

## Quando nao for possivel seguir TDD puro

Em manutencao de legado, hotfix ou area sem cobertura:

- primeiro capture o comportamento atual ou esperado com teste caracterizador ou teste de regressao
- depois implemente a correcao
- se o teste antes da mudanca for inviavel por restricao tecnica real, documente isso na resposta final e adicione o teste imediatamente apos viabilizar a implementacao

## Regras praticas no repositorio

- Ao planejar uma implementacao, inclua explicitamente a etapa de testes antes do codigo de producao.
- Ao editar backend, procure primeiro o projeto de testes correspondente em `tests/`.
- Ao editar frontend, procure primeiro os testes do modulo ou service correspondente.
- Sempre que possivel, execute pelo menos os testes diretamente afetados pela mudanca.

## Relatorio de evidencia

Ao concluir, relate a evidencia em vez de afirmar "testes passando". Uma linha por comportamento:

| comportamento | teste | RED (saida que falhou) | GREEN (saida que passou) |
|---|---|---|---|

A saida citada deve ser a do runner (nome do teste e contagem de testes executados), nao so o exit code: comando chamado errado pode sair com 0 sem rodar teste nenhum. Para um executor do `arquiteto`, esta tabela vai no campo `Evidência` do bloco de retorno.

## Checklist antes de concluir

- Existe teste cobrindo o comportamento novo ou corrigido?
- O teste foi escrito antes da implementacao ou, em legado, o mais cedo possivel?
- O teste falhava pelo motivo esperado, e nao por erro de setup?
- O codigo de producao foi a menor mudanca correta para passar?
- Os testes relevantes foram executados e ficaram verdes, com a contagem no log?

## Em revisoes

Ao revisar uma implementacao, aponte como problema quando houver:

- mudanca de comportamento sem teste correspondente
- teste que valida detalhe interno em vez de comportamento
- cobertura insuficiente para regressao previsivel
- implementacao maior que o necessario para satisfazer o teste
- ausencia de evidencias de execucao dos testes relevantes
- teste que so passa por fixture herdada do comportamento antigo
