---
name: backend-dotnet-upgrade
description: Use exclusivamente para planejar e executar atualização de versão do .NET, ASP.NET Core, Entity Framework Core e dependências relacionadas, reduzindo risco de incompatibilidade e regressão.
---

# .NET Upgrade

## Quando usar

Use quando a tarefa solicitar:

- atualizar versão do .NET;
- migrar entre versões major do .NET;
- atualizar ASP.NET Core;
- atualizar Entity Framework Core;
- corrigir incompatibilidades após upgrade do SDK/runtime;
- revisar pacotes NuGet afetados pela nova versão;
- atualizar imagens Docker do SDK/runtime.

## Objetivo

Executar upgrade de forma controlada, garantindo compatibilidade entre SDK, runtime, ASP.NET Core, EF Core, pacotes NuGet, segurança, OpenAPI, persistência, containers e pipeline.

## Procedimento

1. Registre o estado atual:
   - versão do SDK (`dotnet --info` quando disponível);
   - `TargetFramework` dos projetos;
   - `global.json`, se existir;
   - versões de ASP.NET Core/EF Core e principais pacotes NuGet;
   - imagens .NET usadas no Dockerfile;
   - versão usada no pipeline CI/CD.
2. Identifique a versão alvo e se ela é LTS/STS quando isso for relevante ao projeto.
3. Verifique breaking changes, APIs obsoletas/removidas e requisitos do SDK/runtime.
4. Atualize primeiro os pontos centrais de versão:
   - `global.json`;
   - `TargetFramework`/`TargetFrameworks`;
   - `Directory.Packages.props`, quando existir;
   - imagens `mcr.microsoft.com/dotnet/sdk` e `aspnet` no Dockerfile;
   - configuração do SDK no pipeline.
5. Atualize pacotes Microsoft relacionados mantendo versões major compatíveis.
6. Revise áreas frequentemente afetadas:
   - ASP.NET Core hosting e middleware;
   - Authentication/Authorization;
   - Entity Framework Core e provider do banco;
   - serialização JSON;
   - configuration/options;
   - OpenAPI/Swagger;
   - health checks;
   - logging/observability;
   - testes;
   - Docker/containers.
7. Não atualize bibliotecas de terceiros indiscriminadamente; altere apenas o necessário para compatibilidade ou segurança da migração.
8. Compile após cada conjunto pequeno de mudanças.
9. Execute restore, build e testes disponíveis.
10. Valide inicialização da aplicação e endpoints críticos.
11. Quando houver EF Core, valide migrations existentes e acesso ao banco sem gerar migrations desnecessárias.
12. Quando houver container, valide build e inicialização usando o runtime alvo.

## Validações recomendadas

```bash
dotnet --info
dotnet restore
dotnet build
dotnet test
dotnet list package --outdated
```

Quando EF Core estiver presente e a ferramenta estiver configurada:

```bash
dotnet ef migrations list
```

## Regras

- não misture upgrade major com refatoração funcional extensa;
- não altere arquitetura apenas por causa do upgrade;
- não force versões individuais incompatíveis com a versão principal da stack sem motivo comprovado;
- mantenha pacotes `Microsoft.EntityFrameworkCore.*` e provider do banco compatíveis;
- trate warnings/deprecations relevantes durante a migração;
- preserve comportamento público da API, salvo mudança explicitamente solicitada;
- não gere migration apenas para eliminar erro de build;
- não considere o upgrade concluído apenas porque compila;
- valide runtime, testes e endpoints críticos;
- em Docker multi-stage, mantenha imagens SDK e runtime coerentes com a versão alvo.

## Ordem recomendada

1. SDK / `global.json`.
2. `TargetFramework`.
3. ASP.NET Core e pacotes Microsoft.
4. EF Core e provider do banco.
5. Authentication/Authorization.
6. OpenAPI/Swagger.
7. Bibliotecas de terceiros necessárias.
8. Build e testes.
9. Docker/runtime.
10. Smoke tests e endpoints críticos.

## Checklist

- [ ] Versão atual do SDK foi identificada?
- [ ] Versão alvo foi definida?
- [ ] `TargetFramework` está correto?
- [ ] `global.json` foi revisado?
- [ ] `Directory.Packages.props` foi revisado quando existir?
- [ ] Breaking changes foram analisados?
- [ ] Pacotes NuGet estão compatíveis?
- [ ] ASP.NET Core foi validado?
- [ ] Authentication/Authorization foram validadas?
- [ ] EF Core e provider do banco estão compatíveis?
- [ ] Persistência/migrations foram validadas?
- [ ] OpenAPI/Swagger continua funcionando?
- [ ] Health checks continuam funcionando?
- [ ] Dockerfile usa SDK/runtime corretos?
- [ ] Pipeline CI/CD suporta a versão alvo?
- [ ] Restore, build e testes passaram?
- [ ] Aplicação inicia corretamente?
- [ ] Endpoints críticos foram testados?
