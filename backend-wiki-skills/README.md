# .NET Backend Wiki Skills

Conjunto de skills para agentes de desenvolvimento backend .NET/ASP.NET Core, organizado como regras operacionais para arquitetura, APIs, persistência, segurança, observabilidade e manutenção da stack.

## Estrutura

```text
backend-wiki-skills/
├── AGENTS.md
├── README.md
└── .agents/
    └── skills/
        ├── backend-modular-architecture/SKILL.md
        ├── backend-framework-selection/SKILL.md
        ├── backend-dependency-management/SKILL.md
        ├── backend-dependency-injection/SKILL.md
        ├── backend-api-openapi/SKILL.md
        ├── backend-pagination/SKILL.md
        ├── backend-security/SKILL.md
        ├── backend-persistence-transactions/SKILL.md
        ├── backend-logging/SKILL.md
        └── backend-dotnet-upgrade/SKILL.md
```

## Stack alvo

As skills foram adaptadas para projetos que utilizam principalmente:

- .NET / ASP.NET Core;
- Controllers ou Minimal APIs;
- Entity Framework Core;
- NuGet / `PackageReference`;
- `Directory.Packages.props` quando houver gerenciamento central;
- Dependency Injection nativa do .NET;
- `ILogger<T>` e logging estruturado;
- JWT/OAuth2/OpenID Connect;
- OpenAPI/Swagger;
- Docker e ambientes Kubernetes/OpenShift quando aplicável.

## Como usar

1. Coloque `AGENTS.md` na raiz do repositório em que o agente irá trabalhar.
2. Copie `.agents/skills/` para o mesmo repositório.
3. O agente deve ler primeiro `AGENTS.md` e carregar apenas as skills necessárias para a tarefa corrente.
4. Em tarefas que cruzem vários assuntos, o `AGENTS.md` define a ordem e a combinação das skills.

## Princípio

As skills não servem para gerar código mecanicamente. Elas funcionam como regras operacionais: primeiro entender a arquitetura existente, depois aplicar a diretriz pertinente, preservar compatibilidade e validar o resultado.

A adaptação para .NET evita impor padrões como Repository, Clean Architecture, CQRS, Controllers ou Minimal APIs quando o repositório já possui uma abordagem válida diferente.
