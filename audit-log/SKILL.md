---
name: audit-log
description: AuditLog library — NuGet packages, DSL, troubleshooting, pack & publish
---

# AuditLog — Skill

Biblioteca de auditoria automática para EF Core com Source Generators Roslyn.

**Repositório:** https://github.com/SamuelGFDias/audit_log
**Path local:** /home/samueldias/dev/back/audit_log
**Docs:** /home/samueldias/dev/back/audit_log/docs/

---

## Pacotes NuGet

Última versão: **0.4.7** (consulte `curl -s https://api.nuget.org/v3-flatcontainer/AuditLog.Abstractions/index.json` para verificar)

| PackageId | Tipo | Descrição |
|-----------|------|-----------|
| `AuditLog.Abstractions` | lib net10.0 | Contratos: `AuditConfigurator<T>`, `IAuditDescriptor`, builders, `AuditOperation` enum |
| `AuditLog.EntityFrameworkCore` | lib net10.0 | EF Core: `AuditSaveInterceptor`, service extensions, model builder hooks |
| `AuditLog.Generator` | analyzer netstandard2.0 | Source generator: gera `*AuditLog`, maps, descriptors, DI extensions |
| `AuditLog.EntityFrameworkCore.SoftDelete` | lib net10.0 | SoftDelete runtime: `ISoftDeleteEntity`, interceptor, query filters, cascade |
| `AuditLog.Generator.SoftDelete` | analyzer netstandard2.0 | Source generator: handlers tipados de cascade/restrict/set-null |

### Instalação

```xml
<ItemGroup>
  <!-- Auditoria -->
  <PackageReference Include="AuditLog.EntityFrameworkCore" Version="0.4.7" />
  <PackageReference Include="AuditLog.Generator" Version="0.4.7" OutputItemType="Analyzer" ReferenceOutputAssembly="false" />

  <!-- SoftDelete (opcional) -->
  <PackageReference Include="AuditLog.EntityFrameworkCore.SoftDelete" Version="0.4.7" />
  <PackageReference Include="AuditLog.Generator.SoftDelete" Version="0.4.7" OutputItemType="Analyzer" ReferenceOutputAssembly="false" />
</ItemGroup>
```

---

## DSL Completa

### AuditConfigurator

```csharp
[GenerateAuditLog]
public sealed class PacienteAuditConfigurator : AuditConfigurator<Paciente>
{
    public PacienteAuditConfigurator()
    {
        For(x => x.Id).Key();
        For(x => x.Nome).HasMaxLength(200).IsRequired();
        For(x => x.Cpf).Sensitive().HasMaxLength(11);
        For(x => x.DataAtualizacao).Ignore();
        For(x => x.Tipo).HasOperationOn(EntityState.Modified);
    }
}
```

### Métodos do builder de propriedade

| Método | Descrição |
|--------|-----------|
| `.Key()` | Marca como chave composta na audit table |
| `.HasMaxLength(n)` | Define max length |
| `.IsRequired()` | Not null |
| `.Sensitive()` | Omite valor em logs |
| `.Ignore()` | Exclui da auditoria |
| `.HasOldValue()` | Inclui `ValorAnterior` |
| `.HasNewValue()` | Inclui `ValorNovo` |
| `.HasOperationOn(EntityState.{Added,Modified,Deleted})` | Loga só nessa operação |

### Collections e Owned

```csharp
For(x => x.Itens).AsCollection();
For(x => x.Itens).AsCollection(c => c.For(y => y.Id).Key());
For(x => x.Endereco).AsOwned();
For(x => x.Endereco).AsOwned(e =>
{
    e.For(x => x.Logradouro).HasMaxLength(200);
    e.For(x => x.Coordenadas).AsOwned(c =>
    {
        c.For(x => x.Lat);
        c.For(x => x.Lng);
    });
});
```

### Código gerado automaticamente

- `{Entity}AuditLog` — tabela de auditoria com `Id`, `EntidadeId`, `Operacao` (enum `AuditOperation`), `Data`, `UsuarioId`, colunas dinâmicas
- `{Entity}AuditLogDescriptor` — mapeia `EntityChange → AuditLog`
- `{Entity}AuditLogEntityMap` — EF Core configuration (column types, max length)
- `ServiceCollectionExtensions.AddGeneratedAuditLogs()` — DI registration
- Para collections: `{Entity}{Collection}AuditLog`, descritor, entity map

### Registro e interceptor

```csharp
// DI
services.AddGeneratedAuditLogs();

// No DbContext
optionsBuilder.AddInterceptors(new AuditSaveInterceptor());
```

---

## SoftDelete

### Interfaces

```csharp
public interface ISoftDeleteEntity
{
    bool IsDeleted { get; set; }
    DateTime? DeletedAt { get; set; }
}
```

### DbContext

```csharp
[GenerateSoftDelete]
public class AppDbContext : DbContext
{
    public DbSet<Paciente> Pacientes { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Paciente>(e =>
        {
            e.HasMany(x => x.Notificacoes)
                .WithOne(x => x.Paciente)
                .HasForeignKey(x => x.PacienteId)
                .OnDelete(DeleteBehavior.Cascade);
        });
        modelBuilder.ApplySoftDeleteQueryFilter();
    }
}
```

### DI

```csharp
// Com generator
var registry = new SoftDeleteHandlerRegistry();
registry.AddGeneratedSoftDeleteHandlers();
services.AddSoftDelete(registry);

// Sem generator (reflection fallback)
services.AddSoftDelete();
```

### Comportamentos de FK

| `OnDelete()` | Efeito |
|---|---|
| `Cascade` | Dependentes soft-deletados recursivamente |
| `Restrict` | Lança `RestrictDeleteViolationException` |
| `SetNull` | FK dos dependentes setada como null |

### Convenções (quando `OnDelete` não especificado)

| Navigation | Comportamento |
|---|---|
| Collection (`List<T>`) | `Cascade` |
| Reference (`T`) | `Restrict` |
| FK nullable (`Guid?`) | `SetNull` |

### Herança indireta de `IEntityTypeConfiguration<T>`

O gerador detecta entity maps via cadeia de herança completa (`AuditEntityMap<T>` → `IContextEntityMap<T>` → `IEntityTypeConfiguration<T>`). Funciona com `ApplyConfiguration` e `ApplyConfigurationsFromAssembly`.

### Descoberta sem `DbSet<T>`

Entidades registradas via `modelBuilder.Entity<T>()`, `ApplyConfiguration` ou `ApplyConfigurationsFromAssembly` são descobertas mesmo sem `DbSet<T>`.

---

## Erros Comuns e Diagnóstico

### Source generator não gera nada

- Verificar `OutputItemType="Analyzer"` e `ReferenceOutputAssembly="false"` no csproj
- Configurador precisa ser `public`, herdar de `AuditConfigurator<T>`, decorado com `[GenerateAuditLog]`
- SoftDelete: DbContext precisa de `[GenerateSoftDelete]` + entidades `ISoftDeleteEntity`
- Rodar `dotnet clean && dotnet build`

### AuditSaveInterceptor não salva

- `AddGeneratedAuditLogs()` foi chamado?
- Interceptor adicionado via `AddInterceptors`?
- Se não há configuradores `[GenerateAuditLog]`, nada é auditado

### RestrictDeleteViolationException inesperada

- Navigation reference (`T`) default é Restrict
- Adicionar `.OnDelete(DeleteBehavior.Cascade)` explicitamente na FK

### Conflito de versão EF Core

- AuditLog usa EF Core 10.0.0 (`Microsoft.EntityFrameworkCore.Relational`)
- Verificar com `dotnet list package --vulnerable`

---

## Estrutura do Source (para debug)

```
src/
├── AuditLog.Abstractions/          # Contratos e builders
├── AuditLog.EntityFrameworkCore/   # Runtime EF Core (interceptor, extensions)
├── AuditLog.Generator/             # Source generator principal
├── AuditLog.Generator.Shared/      # Código compartilhado entre generators
├── AuditLog.EntityFrameworkCore.SoftDelete/ # Runtime soft delete
└── AuditLog.Generator.SoftDelete/  # Source generator soft delete
```

### Arquivos-chave

| Arquivo | Propósito |
|---------|-----------|
| `src/AuditLog.Abstractions/AuditConfigurator.cs` | Builder base |
| `src/AuditLog.EntityFrameworkCore/AuditSaveInterceptor.cs` | Interceptor principal |
| `src/AuditLog.Generator/AuditLogGenerator.cs` | Entry point do generator |
| `src/AuditLog.Generator/ConfiguratorDetector.cs` | Encontra configuradores |
| `src/AuditLog.Generator/ExpressionParser.cs` | Parse de lambdas |
| `src/AuditLog.Generator/RootEntityGenerator.cs` | Gera AuditLog + Descriptor + Map |
| `src/AuditLog.EntityFrameworkCore.SoftDelete/SoftDeleteInterceptor.cs` | Interceptor soft delete |
| `src/AuditLog.Generator.SoftDelete/SoftDeleteGenerator.cs` | Generator soft delete |

### Testes

```
tests/
├── AuditLog.Tests/                # Unitários
├── AuditLog.IntegrationTests/     # Integração EF
├── AuditLog.SoftDelete.Tests/
├── AuditLog.SoftDelete.Reflection.Tests/
└── AuditLog.SoftDelete.Generator.Tests/
```

---

## Pack & Publish

### Pack local

```bash
./pack.sh
# Gera .nupkg em artifacts/packages/
```

### Publicar nova versão (NuGet.org)

1. Incrementar versão e commitar:
```bash
git add . && git commit -m "feat: ..."
```

2. Criar tag e push:
```bash
git tag v{version}  # ex: v0.4.8
git push origin v{version}
```

3. O GitHub Action `publish.yml` dispara automaticamente, executa:
   - `dotnet restore && dotnet build && dotnet test`
   - `dotnet pack` de todos os 5 pacotes
   - Push para NuGet.org via OIDC (login samueldias21)

4. Verificar publicação:
```bash
curl -s "https://api.nuget.org/v3-flatcontainer/AuditLog.Abstractions/index.json"
```

5. Atualizar versão no topo deste skill file

### CI/CD

Workflow: `.github/workflows/publish.yml` — trigger em push de tags `v*`. Usa MinVer para inferir versão das tags.

### MinVer

- Tag `v0.4.7` → versão `0.4.7`
- Tag `v0.5.0-beta1` → versão `0.5.0-beta.1`
- Sem tag → `0.0.0-alpha.{commitCount}`
