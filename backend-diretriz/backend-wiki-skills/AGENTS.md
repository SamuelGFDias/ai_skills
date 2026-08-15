# AGENTS.md — Backend Architecture Skill Router

## Objetivo

Este arquivo é o roteador central das skills de backend. Antes de alterar código, o agente deve identificar quais aspectos da tarefa estão envolvidos e carregar somente as skills correspondentes.

## Regra principal

**Nunca imponha uma arquitetura nova sem antes inspecionar a arquitetura existente do repositório.**

A diretriz deve ser aplicada de forma incremental, respeitando contratos públicos, padrões internos, compatibilidade e decisões já consolidadas no projeto.

## Local das skills

Todas as skills ficam em:

`.agents/skills/<nome-da-skill>/SKILL.md`

## Roteamento

| Situação encontrada na tarefa | Skill obrigatória |
|---|---|
| Criar módulo, reorganizar camadas, separar responsabilidades, reduzir acoplamento | `backend-modular-architecture` |
| Escolher Spring Boot ou Quarkus para um serviço novo ou modernização relevante | `backend-framework-selection` |
| Alterar `pom.xml`, `build.gradle`, versões, plugins ou dependências | `backend-dependency-management` |
| Criar/refatorar services, components, beans ou dependências entre classes | `backend-dependency-injection` |
| Criar/alterar endpoint REST, contrato HTTP, Swagger ou OpenAPI | `backend-api-openapi` |
| Endpoint de coleção, busca, listagem grande, filtros com `Pageable`/paginação | `backend-pagination` |
| Autenticação, autorização, JWT/OAuth2, Spring Security ou controle de acesso | `backend-security` |
| Escrita em banco, várias operações atômicas, repositórios, `@Transactional` | `backend-persistence-transactions` |
| Adicionar/alterar logs, diagnóstico, rastreabilidade ou tratamento operacional | `backend-logging` |
| Atualizar versão do Spring Boot ou stack Spring associada | `backend-spring-boot-upgrade` |

## Combinação de skills

Uma tarefa pode exigir mais de uma skill. Exemplos:

### Novo endpoint paginado protegido

Carregar, nesta ordem:

1. `backend-modular-architecture`
2. `backend-api-openapi`
3. `backend-pagination`
4. `backend-security`
5. `backend-logging`

### Nova operação de negócio com gravação em múltiplas tabelas

Carregar:

1. `backend-modular-architecture`
2. `backend-dependency-injection`
3. `backend-persistence-transactions`
4. `backend-logging`

### Upgrade de framework

Carregar:

1. `backend-spring-boot-upgrade`
2. `backend-dependency-management`
3. skills afetadas pela mudança, como `backend-security` ou `backend-api-openapi`

## Ordem de precedência

Quando houver conflito entre orientações, priorize:

1. segurança e controle de acesso;
2. integridade transacional e de dados;
3. contratos públicos da API;
4. arquitetura e separação de responsabilidades;
5. compatibilidade com o projeto existente;
6. observabilidade e logs;
7. conveniência de implementação.

## Regras globais de execução

- Inspecione o código existente antes de criar abstrações novas.
- Preserve nomes e convenções já adotados quando forem coerentes com a diretriz.
- Evite duplicar responsabilidade entre Controller, Service e Repository.
- Não acople regras de negócio a detalhes de HTTP ou persistência sem necessidade.
- Não adicione dependência nova quando a stack já oferece recurso equivalente.
- Não exponha segredo, token, credencial, dado sensível ou stack trace em resposta HTTP ou log.
- Toda listagem potencialmente grande deve ser avaliada para paginação.
- Toda sequência de escritas que precise de atomicidade deve ser avaliada para transação.
- Toda alteração de contrato deve considerar documentação OpenAPI e compatibilidade dos consumidores.
- Após qualquer mudança, execute os testes disponíveis e valide build/lint quando existirem.

## Saída esperada do agente

Ao concluir uma tarefa, informe de forma objetiva:

- skills aplicadas;
- arquivos alterados;
- decisão arquitetural relevante;
- validações executadas;
- riscos ou pendências reais, se existirem.
