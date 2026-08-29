---
name: backend-dependency-management
description: Use ao adicionar, remover ou atualizar pacotes NuGet, SDKs e versões em projetos .NET, mantendo restore/build reproduzíveis e evitando conflitos de compatibilidade.
---

# Backend Dependency Management (.NET)

## Quando usar

Use quando mexer em:

- `.csproj`;
- `.fsproj` quando aplicável;
- `Directory.Packages.props`;
- `Directory.Build.props`;
- `global.json`;
- `NuGet.config`;
- `PackageReference`;
- SDKs e workloads;
- versões de bibliotecas;
- dependências transitivas.

## Objetivo

Usar NuGet e os mecanismos de gerenciamento do .NET como fonte explícita e reproduzível das dependências, reduzindo conflitos, duplicidade e versões incompatíveis.

## Procedimento

1. Identifique o `TargetFramework` e a versão do SDK utilizada.
2. Verifique se o repositório usa Central Package Management com `Directory.Packages.props`.
3. Antes de adicionar biblioteca, procure recurso equivalente já disponível no .NET, ASP.NET Core ou stack existente.
4. Use versão compatível com o `TargetFramework`, ASP.NET Core e EF Core do projeto.
5. Evite declarar versão no `.csproj` quando o projeto centraliza versões em `Directory.Packages.props`.
6. Avalie dependências transitivas e conflitos.
7. Não misture versões major incompatíveis de pacotes do mesmo ecossistema, especialmente `Microsoft.EntityFrameworkCore.*`.
8. Remova dependência antiga somente após confirmar que não há uso.
9. Execute restore, build e testes.

## Comandos úteis

```bash
dotnet restore
dotnet build
dotnet test
dotnet list package
dotnet list package --outdated
dotnet list package --include-transitive
```

Use os comandos apenas quando forem compatíveis com a versão do SDK instalada no ambiente.

## Regras

- Prefira pacotes oficiais ou amplamente mantidos.
- Evite duas bibliotecas com a mesma responsabilidade sem motivo concreto.
- Não atualize um conjunto grande de pacotes em tarefa não relacionada.
- Em upgrade de .NET, trate primeiro SDK, `TargetFramework` e pacotes centrais da plataforma.
- Dependências de teste não devem vazar para runtime/publicação.
- Não force uma versão isolada de pacote Microsoft contra a versão principal da stack sem motivo comprovado.
- Preserve feeds privados e configuração existente do `NuGet.config`.

## Checklist

- [ ] A dependência é realmente necessária?
- [ ] Já existe recurso equivalente no projeto/framework?
- [ ] A versão é compatível com o `TargetFramework`?
- [ ] O repositório usa gerenciamento central de pacotes?
- [ ] O escopo/referência está correto?
- [ ] Não há conflito transitivo conhecido?
- [ ] `dotnet restore` funciona?
- [ ] Build reproduzível continua funcionando?
- [ ] Testes passaram?
