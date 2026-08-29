# AGENTS.md — .NET Backend Architecture Skill Router

## Objetivo

Este arquivo é o roteador central das skills de backend .NET. Antes de alterar código, o agente deve identificar quais aspectos da tarefa estão envolvidos e carregar somente as skills correspondentes.

## Regra principal

**Nunca imponha uma arquitetura nova sem antes inspecionar a arquitetura existente do repositório.**

A diretriz deve ser aplicada de forma incremental, respeitando contratos públicos, padrões internos, compatibilidade e decisões já consolidadas no projeto.

## Local das skills

Todas as skills ficam em:

`.agents/skills/<nome-da-skill>/SKILL.md`

## Roteamento

| Situação encontrada na tarefa | Skill obrigatória |
|---|---|
| Criar módulo/projeto, reorganizar camadas/namespaces, separar responsabilidades, reduzir acoplamento | `backend-modular-architecture` |
| Escolher Controllers, Minimal APIs, Worker Service, versão/runtime ou modelo de aplicação .NET | `backend-framework-selection` |
| Alterar `.csproj`, `Directory.Packages.props`, `global.json`, SDK ou pacotes NuGet | `backend-dependency-management` |
| Criar/refatorar services, repositories, clients, registros no DI ou lifetimes | `backend-dependency-injection` |
| Criar/alterar endpoint REST, contrato HTTP, Swagger ou OpenAPI | `backend-api-openapi` |
| Endpoint de coleção, busca/listagem grande, `IQueryable`, `Skip`/`Take`, EF Core ou paginação | `backend-pagination` |
| Autenticação, autorização, JWT/OAuth2/OIDC, ASP.NET Core Authorization ou controle de acesso | `backend-security` |
| Escrita em banco, múltiplas operações atômicas, `DbContext`, `SaveChanges` ou transações EF Core | `backend-persistence-transactions` |
| Adicionar/alterar `ILogger`, logging estruturado, diagnóstico ou rastreabilidade | `backend-logging` |
| Atualizar versão do .NET, ASP.NET Core, EF Core, SDK/runtime ou stack associada | `backend-dotnet-upgrade` |

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

### Upgrade de .NET

Carregar:

1. `backend-dotnet-upgrade`
2. `backend-dependency-management`
3. skills afetadas pela mudança, como `backend-security`, `backend-persistence-transactions` ou `backend-api-openapi`

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

- Inspecione `.sln`, `.csproj`, `Program.cs`, configuração e estrutura existentes antes de criar abstrações novas.
- Preserve nomes, namespaces e convenções já adotados quando forem coerentes.
- Evite duplicar responsabilidade entre Controller/Endpoint, Application Service e persistência.
- Não acople regra de negócio a `HttpContext`, ASP.NET Core ou EF Core sem necessidade.
- Não adicione pacote NuGet quando a plataforma ou stack já oferece recurso equivalente.
- Não exponha segredo, token, credencial, dado sensível ou stack trace em resposta HTTP ou log.
- Toda listagem potencialmente grande deve ser avaliada para paginação no banco.
- Toda sequência de escritas que precise de atomicidade deve ser avaliada para transação.
- Toda alteração de contrato deve considerar documentação OpenAPI e compatibilidade dos consumidores.
- Preserve operações assíncronas e `CancellationToken` quando o projeto utilizar esse padrão.
- Após qualquer mudança, execute `dotnet restore`, `dotnet build` e `dotnet test` quando aplicáveis e disponíveis.

## Saída esperada do agente

Ao concluir uma tarefa, informe de forma objetiva:

- skills aplicadas;
- arquivos alterados;
- decisão arquitetural relevante;
- validações executadas;
- riscos ou pendências reais, se existirem.
