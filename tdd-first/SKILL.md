---
name: tdd-first
description: Use quando a demanda exigir implementacao de codigo e a abordagem deve priorizar TDD, escrevendo testes antes do codigo de producao.
---

# Skill: tdd-first

Ao receber uma demanda de implementacao, adote TDD como fluxo padrao: escreva primeiro o teste que descreve o comportamento esperado, veja o teste falhar, implemente o minimo necessario para passar, e refatore mantendo a suite verde.

## Regra principal

Antes de alterar codigo de producao:

- identifique o comportamento esperado
- escreva ou ajuste o teste que expresse esse comportamento
- execute o teste alvo e confirme a falha inicial quando isso for viavel
- so depois implemente a mudanca de producao

## Ciclo obrigatorio

### 1. Red

- Crie um teste pequeno, focado e legivel.
- O teste deve falhar pelo motivo correto.
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
- Prefira testes pequenos e independentes.
- Use doubles apenas quando ajudarem a isolar o comportamento do caso de uso.
- Nao masque defeitos com mocks excessivos ou asserts vagos.

## Prioridade por tipo de teste

- Para regras de negocio e services: priorize testes unitarios.
- Para integracao entre camadas, persistencia ou contratos HTTP: adicione testes de integracao quando o risco justificar.
- Para UI: teste comportamento visivel e integracoes relevantes, sem acoplar o teste demais a detalhes de markup.

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

## Checklist antes de concluir

- Existe teste cobrindo o comportamento novo ou corrigido?
- O teste foi escrito antes da implementacao ou, em legado, o mais cedo possivel?
- O teste falhava pelo motivo esperado?
- O codigo de producao foi a menor mudanca correta para passar?
- Os testes relevantes foram executados e ficaram verdes?

## Em revisoes

Ao revisar uma implementacao, aponte como problema quando houver:

- mudanca de comportamento sem teste correspondente
- teste que valida detalhe interno em vez de comportamento
- cobertura insuficiente para regressao previsivel
- implementacao maior que o necessario para satisfazer o teste
- ausencia de evidencias de execucao dos testes relevantes
