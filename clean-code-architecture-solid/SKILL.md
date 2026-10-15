---
name: clean-code-architecture-solid
description: Diretrizes para programar com Clean Code de Robert C. Martin, Clean Architecture e principios SOLID.
---

# Skill: clean-code-architecture-solid

Ao implementar, refatorar, revisar ou propor codigo neste workspace, siga estas diretrizes como padrao.

## Objetivo

Produzir codigo:

- simples de entender
- facil de manter
- orientado a responsabilidades claras
- com baixo acoplamento
- com comportamento testavel
- alinhado a Clean Code, Clean Architecture e SOLID

## Clean Code

### Nomes

- Use nomes explicitos, semanticamente claros e consistentes com a linguagem de dominio.
- Prefira nomes que revelem intencao em vez de abreviacoes opacas.
- Evite nomes genericos como `data`, `info`, `manager`, `helper`, `utils`, `obj` e `temp`, salvo quando o contexto for realmente obvio.

### Funcoes e metodos

- Mantenha funcoes pequenas e com uma responsabilidade principal.
- Se uma funcao exige muitos comentarios para ser compreendida, reestruture-a.
- Evite funcoes com multiplos niveis de abstracao misturados.
- Extraia etapas conceitualmente independentes para metodos privados ou colaboradores quando isso reduzir complexidade.

### Estrutura e legibilidade

- Prefira fluxo direto, com guard clauses e condicoes simples.
- Evite aninhamento desnecessario.
- Mantenha ordem logica: validacao, orquestracao, transformacao e persistencia.
- Elimine duplicacoes relevantes, mas nao introduza abstracoes prematuras.

### Comentarios

- Nao use comentarios para compensar codigo confuso.
- Comente apenas quando houver regra de negocio, decisao arquitetural ou restricao nao obvia.
- Prefira codigo autoexplicativo.

### Tratamento de erros

- Falhas devem ser tratadas perto da fronteira adequada.
- Mensagens de erro devem ser claras e orientadas ao problema real.
- Evite capturar excecoes apenas para esconder defeitos.

## SOLID

### Single Responsibility Principle

- Cada classe, modulo ou componente deve ter um motivo claro para mudar.
- Evite concentrar validacao, orquestracao, acesso a dados, mapeamento e formatacao na mesma unidade.

### Open/Closed Principle

- Estruture o codigo para extensao por novas implementacoes, estrategias, adaptadores ou especializacoes.
- Evite crescimento por cadeias repetidas de `if`, `switch` e condicionais por tipo quando houver comportamento variavel previsivel.

### Liskov Substitution Principle

- Subtipos devem preservar o contrato do tipo base.
- Nao introduza comportamentos inesperados, precondicoes mais restritivas ou retornos inconsistentes.

### Interface Segregation Principle

- Prefira contratos pequenos e especificos por caso de uso.
- Nao force consumidores a depender de membros que nao usam.

### Dependency Inversion Principle

- Regras de negocio devem depender de abstracoes, nao de detalhes concretos.
- Infraestrutura, frameworks e IO devem ficar nas bordas.

## Clean Architecture

### Regra de dependencia

- Dependencias devem apontar para dentro, em direcao ao dominio e aos casos de uso.
- Camadas externas nao devem vazar detalhes tecnicos para o dominio.

### Separacao por responsabilidade

- Dominio: entidades, regras centrais, invariantes e value objects.
- Aplicacao: casos de uso, orquestracao, validacoes de fluxo e coordenacao entre dependencias.
- Infraestrutura: persistencia, integracoes externas, autenticacao, storage e detalhes tecnicos.
- Apresentacao: controllers, pages, components, requests e view models.

### Fronteiras

- DTOs, requests e responses devem atravessar fronteiras; entidades de dominio nao devem ser moldadas por necessidades de UI ou transporte.
- Nao acople regras centrais a framework, banco, HTTP ou detalhes de serializacao.

## Regras praticas para implementacao

- Antes de adicionar uma nova abstracao, confirme que ela reduz acoplamento ou complexidade real.
- Prefira a menor mudanca correta que preserve extensibilidade.
- Quando existir variacao por entidade, tipo ou contexto, prefira estrategia, especializacao ou registro de comportamento em vez de condicionais em cascata.
- Preserve coesao: validadores validam, builders constroem, services orquestram, repositories persistem.
- Mantenha consistencia com os padroes existentes do repositorio.

## Checklist antes de concluir

- O nome das classes e metodos revela claramente a intencao?
- Existe mais de uma responsabilidade relevante na mesma unidade?
- Algum `if` ou `switch` tende a crescer a cada nova entidade ou regra?
- O dominio ficou protegido de detalhes de framework e infraestrutura?
- O codigo novo ficou mais facil de testar e evoluir?
- A solucao evita duplicacao sem criar abstracao desnecessaria?

## Em revisoes

Ao revisar codigo, priorize apontar:

- responsabilidades misturadas
- abstrações prematuras ou desnecessarias
- acoplamento indevido entre camadas
- crescimento por condicionais repetitivas
- nomes pouco expressivos
- metodos excessivamente longos ou confusos
- violacoes de SOLID
- vazamento de detalhes de infraestrutura para regras de negocio
