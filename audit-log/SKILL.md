---
name: audit-log
description: AuditLog library — NuGet packages, DSL, troubleshooting, pack & publish
---

# AuditLog — Skill

**Tipo:** internal

Biblioteca de auditoria automática para EF Core com Source Generators Roslyn.

**Repositório:** https://github.com/SamuelGFDias/audit_log
**Path local:** /home/samueldias/dev/pessoal/back/audit_log
**Docs:** `README.md` na raiz do repo (fonte mais completa; esta skill é o resumo operacional)

---

## Pacotes NuGet

Última versão: **0.5.0** (tag `v0.5.0`; versão inferida via MinVer a partir da tag — consulte `curl -s https://api.nuget.org/v3-flatcontainer/AuditLog.Abstractions/index.json` para verificar o que está publicado)

| PackageId | Tipo | Descrição |
|-----------|------|-----------|
| `AuditLog.Abstractions` | lib net10.0 | Contratos: `AuditConfigurator<T>`, `IAuditDescriptor<,>`, builders, `AuditOperation` enum, `AuditRegistry` |
| `AuditLog.EntityFrameworkCore` | lib net10.0 | EF Core: `AuditSaveInterceptor`, `AddAuditLogging` |
| `AuditLog.Generator` | analyzer netstandard2.0 | Source generator: gera `*AuditLog`, maps, descriptors, extensions de DI |
| `AuditLog.EntityFrameworkCore.SoftDelete` | lib net10.0 | SoftDelete runtime: `ISoftDeleteEntity`, interceptor, query filters, cascade |
| `AuditLog.Generator.SoftDelete` | analyzer netstandard2.0 | Source generator: handlers tipados de cascade/restrict/set-null |
| `AuditLog.Historico` | lib net10.0 | Transforma as tabelas `*AuditLog` em histórico legível pro usuário final |

### Instalação

```xml
<ItemGroup>
  <!-- Auditoria -->
  <PackageReference Include="AuditLog.EntityFrameworkCore" Version="0.5.0" />
  <PackageReference Include="AuditLog.Generator" Version="0.5.0" OutputItemType="Analyzer" ReferenceOutputAssembly="false" />

  <!-- SoftDelete (opcional) -->
  <PackageReference Include="AuditLog.EntityFrameworkCore.SoftDelete" Version="0.5.0" />
  <PackageReference Include="AuditLog.Generator.SoftDelete" Version="0.5.0" OutputItemType="Analyzer" ReferenceOutputAssembly="false" />

  <!-- Histórico legível (opcional) -->
  <PackageReference Include="AuditLog.Historico" Version="0.5.0" />
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
        For(x => x.Situacao).AlwaysAudit();
    }
}
```

`AuditConfigurator<TEntity>` expõe três pontos de entrada (`src/AuditLog.Abstractions/AuditConfigurator.cs`): `For<TProperty>(...)`, `ForOwned<TOwned>(...)` (duas sobrecargas) e `ForEach<TElement>(...)`.

### Métodos do builder de propriedade (`AuditPropertyBuilder<TEntity, TProperty>`)

Confirmados em `src/AuditLog.Abstractions/AuditPropertyBuilder.cs` e reconhecidos pelo parser do gerador (`ExpressionParser.CollectModifiers`, `src/AuditLog.Generator/ExpressionParser.cs`):

| Método | Descrição |
|--------|-----------|
| `.Key()` | Marca a propriedade como chave da entidade auditada (não gera coluna própria — vira `{Entidade}Id` no `*AuditLog`) |
| `.Ignore()` | Exclui a propriedade da auditoria |
| `.Sensitive()` | Grava o literal `"***"` em vez do valor real |
| `.AlwaysAudit()` | Sempre inclui o campo em `CamposAlteradosJson`, mesmo sem mudança detectada |
| `.WithColumnName(string)` | Define o nome da coluna gerada explicitamente |
| `.HasMaxLength(int)` | Define `HasMaxLength` no `EntityMap` gerado |
| `.IsRequired()` | Define `IsRequired()` no `EntityMap` gerado |

Não existem `.HasOldValue()`, `.HasNewValue()` nem `.HasOperationOn(EntityState)` — não estão na DSL nem são reconhecidos pelo parser. O valor anterior de um campo é obtido em runtime via `AuditLogAnteriorId` (ver "Código gerado automaticamente"), não por um modificador na configuração.

### Collections (`ForEach`)

A API real de coleções é `ForEach`, não `For(...).AsCollection()` (confirmado em `AuditCollectionBuilder.cs` e `ExpressionParser.ParseForEachChain`):

```csharp
ForEach(x => x.Medicamentos)
    .ParentKey(x => x.NotificacaoId)
    .Key(x => x.MedicamentoId)
    .Configure(item =>
    {
        item.For(x => x.MedicamentoUsoContinuo);
        item.For(x => x.OrigemMedicamento);
    });
```

| Método (`AuditCollectionBuilder<TEntity, TElement>`) | Descrição |
|---|---|
| `.ParentKey(x => x.Prop)` | FK do elemento que aponta pro pai. Se omitido, o gerador assume `{ElementoElementName}Id` |
| `.Key(x => x.Prop)` | Chave de negócio do elemento dentro da coleção. Se omitido, o gerador assume `Id` |
| `.AuditLogName(string)` | Renomeia a classe/tabela `*AuditLog` gerada para a coleção |
| `.Configure(item => { ... })` | Dentro do lambda, `item.For(x => x.Prop)` declara as propriedades auditadas do elemento (sem modificadores — `Key`/`Ignore`/`Sensitive`/etc não são parseados dentro de `Configure`) |

Gera `{Elemento}AuditLog`, descriptor e entity map próprios (ver seção seguinte).

### Owned types (`ForOwned`)

O ponto de entrada real é `ForOwned`, **não** `For(...).AsOwned()`. É um método da própria `AuditConfigurator<T>` (irmão de `For`/`ForEach`), não encadeado a partir de `For`:

```csharp
ForOwned(x => x.Endereco, o =>
{
    o.For(x => x.Logradouro).HasMaxLength(200).IsRequired();
    o.For(x => x.Cidade);
    o.For(x => x.Cep).Sensitive().HasMaxLength(8);
});
```

Existe também `ForOwned<TOwned>(expression)` (sem lambda de configuração), que retorna um `AuditOwnedBuilder<TEntity, TOwned>` encadeável — mas **o gerador só interpreta a sobrecarga de 2 argumentos** (`ExpressionParser.ParseForOwnedChain` exige exatamente `navegação` + `lambda de configuração`; menos que isso emite o diagnostic de erro `"ForOwned requires exactly 2 arguments..."`). Use sempre a forma com dois argumentos acima.

Owned aninhado (owned dentro de owned) **não é suportado** pelo parser — dentro do bloco de `ForOwned`, só instruções `o.For(...)` são reconhecidas; qualquer outra chamada é ignorada silenciosamente.

### Código gerado automaticamente

Por `[GenerateAuditLog]` (ver `RootEntityGenerator.cs` para entidade raiz e `CollectionEntityGenerator.cs` para coleções — layout idêntico entre os dois):

- `{Entity}AuditLog` (`partial class`) — colunas fixas em **toda** tabela de auditoria:
  - `Id` (`long`) — PK autoincremento da própria linha de auditoria
  - `{Entidade}Id` (tipo da chave, ex. `Guid`) — para coleções, são duas colunas: `{ParentKey}` e `{ChildKey}`
  - `Operacao` (`AuditOperation`, gravado como `string` via `HasConversion<string>()`)
  - `OcorridoEm` (`DateTimeOffset`)
  - `UsuarioId` (`string?`)
  - `CorrelationId` (`string?`)
  - `CamposAlteradosJson` (`string?`, `nvarchar(max)` — nomes dos campos alterados nessa revisão, serializado em JSON)
  - `AuditLogAnteriorId` (`long?`) + navegação `AuditLogAnterior` — aponta pra revisão anterior da mesma entidade/elemento, resolvida em runtime pelo descriptor
  - uma coluna `string?` por propriedade auditada (via `Helpers.BuildProperties`/`BuildCollectionProperties`)
- `{Entity}AuditLogDescriptor` — implementa `IAuditDescriptor<TEntity, TAuditLog>`, monta a linha de auditoria a partir do `EntityEntry`
- `{Entity}AuditLogEntityMap` — `IEntityTypeConfiguration<{Entity}AuditLog>` (chave, índice em `{Entidade}Id, OcorridoEm`, `MaxLength`/`IsRequired`/`HasColumnName` por propriedade)
- `GeneratedAuditRegistryExtensions.AddGeneratedAuditConfigurations(this AuditRegistry)` — registra todos os descriptors (entidades raiz + elementos de coleção) no `AuditRegistry`
- `GeneratedAuditModelBuilderExtensions.ApplyGeneratedAuditMaps(this ModelBuilder)` — aplica todos os `EntityMap` gerados
- Para collections: `{Elemento}AuditLog`, descriptor (`internal`), entity map — mesma estrutura acima

**Não existem** `EntidadeId`/`Data` como nomes de coluna (nomes reais: `{Entidade}Id` e `OcorridoEm`), nem `AddGeneratedAuditLogs()` (o método real é `AddGeneratedAuditConfigurations()`, chamado no `AuditRegistry`, não no `IServiceCollection`).

### Registro e interceptor (fluxo completo de ponta a ponta)

```csharp
// 1. Registry: agrega os descriptors gerados
var registry = new AuditRegistry();
registry.AddGeneratedAuditConfigurations();

// 2. DI (opcional — AuditLog.EntityFrameworkCore.AuditLogServiceCollectionExtensions)
services.AddAuditLogging(configureRegistry: r => r.AddGeneratedAuditConfigurations());
// ou, se o registry já foi montado:
services.AddAuditLogging(registry);
// Isso registra AuditRegistry e AuditSaveInterceptor como singletons no container.

// 3. Interceptor no DbContext — recebe o registry (não tem construtor sem parâmetros)
optionsBuilder.AddInterceptors(new AuditSaveInterceptor(registry));
// Sobrecarga com contexto de execução customizado (usuário/correlation id):
new AuditSaveInterceptor(registry, () => new AuditExecutionContext(
    DateTimeOffset.UtcNow, UsuarioId: currentUserId, CorrelationId: correlationId));

// 4. Model builder — aplica os EntityMap gerados
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.ApplyGeneratedAuditMaps();
}
```

`AuditSaveInterceptor(AuditRegistry registry, Func<AuditExecutionContext>? contextFactory = null)` — **exige `registry`**; sem `contextFactory`, usa `DateTimeOffset.UtcNow` com `UsuarioId`/`CorrelationId` nulos (`src/AuditLog.EntityFrameworkCore/AuditSaveInterceptor.cs`).

---

## AuditLog.Historico

Lê as tabelas `*AuditLog` (produzidas por `[GenerateAuditLog]`) e resolve `CamposAlteradosJson` para texto legível — FK vira descrição, enum vira `[Display(Name=...)]`, data ganha formato fixo, booleano vira "Sim"/"Não". Depende só de `AuditLog.Abstractions` (usa `AuditOperation`), sem EF Core.

### `AuditHistoricoMapper<TLog>`

```csharp
var mapper = new AuditHistoricoMapper<ProdutoAuditLog>(cfg =>
{
    cfg.For(x => x.Nome).HasLabel("Nome");
    cfg.For(x => x.CategoriaId).HasLabel("Categoria").ResolveGuidLookup(categoriaPorId);
    cfg.For(x => x.Status).HasLabel("Status").ResolveEnum<StatusProduto>();
    cfg.For(x => x.Ativo).HasLabel("Ativo").ResolveBool();
    cfg.For(x => x.AtualizadoEm).HasLabel("Atualizado em").ResolveData();
    cfg.For(x => x.FotoId).HasLabel("Foto").IsArquivo();
});

IReadOnlyList<AuditHistoricoEntrada<ProdutoAuditLog>> entradas = mapper.Mapear(logs);
```

`TLog` precisa seguir a convenção fixa de um `*AuditLog` gerado (`Id`, `Operacao`, `OcorridoEm`, `UsuarioId`, `CorrelationId`, `CamposAlteradosJson`, `AuditLogAnteriorId`) — o construtor do mapper falha cedo, com mensagem indicando a propriedade faltante, se `TLog` não seguir a convenção (`AuditHistoricoMapper.cs`, `PropriedadeObrigatoria`).

`Mapear` espera o lote completo de revisões relevantes: a "anterior" de cada log é resolvida via `AuditLogAnteriorId` dentro do próprio lote, sem consulta adicional. Só `Operacao == AuditOperation.Modified` preenche `CamposAlterados`.

### `AuditHistoricoConfigurator<TLog>` / `AuditCampoBuilder<TLog>`

`cfg.For<TProp>(x => x.Campo)` é o ponto de entrada — mesma pegada do `AuditConfigurator<T>.For`. Métodos do `AuditCampoBuilder<TLog>` retornado (`src/AuditLog.Historico/AuditCampoBuilder.cs`):

| Método | Efeito |
|---|---|
| `.HasLabel(string)` | Rótulo exibido. Sem isso, usa o nome cru da propriedade |
| `.IsArquivo()` | Marca o campo como referência a arquivo (ex. Id de upload), não texto pra exibir cru |
| `.ResolveWith(Func<string?, string?>)` | Resolve o valor cru com uma função arbitrária |
| `.ResolveEnum<TEnum>()` | Resolve `Enum.ToString()` pro `[Display(Name=...)]` do membro; fallback `[Description]`; sem nenhum, valor cru |
| `.ResolveLookup(IReadOnlyDictionary<string,string>)` | Dicionário simples valor→rótulo. Chave ausente mantém valor cru |
| `.ResolveGuidLookup(IReadOnlyDictionary<Guid,string>)` | FK persistida como Guid (string) → descrição, via dicionário Id→descrição. Sem match, mantém valor cru |
| `.ResolveBool(string verdadeiro = "Sim", string falso = "Não")` | `"True"/"False"` → rótulo. Qualquer outro valor passa direto |
| `.ResolveData()` | `Convert.ToString(...)` de data/hora → `dd/MM/yyyy` (ou com `HH:mm:ss` se houver horário). Usa `DateResolver.ToDisplayDate`; não parseável mantém valor cru |

### Tipos de saída

- `AuditHistoricoEntrada<TLog>(long Id, AuditOperation Operacao, DateTimeOffset OcorridoEm, string? UsuarioId, string? CorrelationId, IReadOnlyList<AuditHistoricoCampo> CamposAlterados, TLog Log)`
- `AuditHistoricoCampo(string Campo, string? ValorAnterior, string? ValorNovo, bool EhArquivo)`

### Resolvers internos (não expostos diretamente, usados pelos métodos `Resolve*`)

- `DateResolver.ToDisplayDate` — parse sob a `CultureInfo.CurrentCulture` vigente na leitura (mesma premissa da gravação, já que nem `AuditSaveInterceptor` nem este resolver fixam cultura explícita)
- `EnumDisplayResolver.ToDisplayName` — `[Display(Name=...)]` → `[Description]` → valor cru

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

## Duas armadilhas conhecidas

### A) `ForEach(...).Key(...)` apontando para uma propriedade chamada `Id`

O `{Elemento}AuditLog` gerado já declara seu próprio `public long Id` (PK autoincremento da linha de auditoria). Se o `ChildKey`/`ParentKey` escolhido resolve para o nome literal `Id` (ou para qualquer outro nome já reservado pela classe — `Operacao`, `OcorridoEm`, `UsuarioId`, `CorrelationId`, `CamposAlteradosJson`, `AuditLogAnteriorId`, `AuditLogAnterior`), o gerador **não falha mais com CS0102**: `Helpers.ResolveSafeColumnName` (`src/AuditLog.Generator/Helpers.cs`) detecta a colisão e renomeia a coluna gerada inserindo `Entity` antes do `Id` final (`Id` → `EntityId`, `UsuarioId` → `UsuarioEntityId`) — esse fix está em v0.5.0, coberto pelo teste de regressão `UsuarioAuditLog_should_disambiguate_own_key_from_context_UsuarioId`.

Isso significa que o código compila, mas a coluna gerada **não se chama como a propriedade original** — vira `EntityId` (ou `{Nome}EntityId`) de forma silenciosa, o que é surpreendente ao consultar a tabela diretamente ou referenciar a propriedade em outro código gerado/consumidor. **Prefira sempre um identificador de negócio explícito do filho** (ex. `MedicamentoId`, não `Id`) em `.Key(...)`/`.ParentKey(...)` — o nome da coluna fica previsível e não depende da lógica de desambiguação.

### B) Tamanho das colunas de snapshot

As colunas de snapshot geradas para cada propriedade auditada são `string?` sem tipo de coluna explícito — o `EntityMap` só emite `.HasMaxLength(n)` quando o configurador chamou `.HasMaxLength(n)` (`Helpers.BuildEntityMapProperties`). Sem isso, a coluna cai na convenção default de string do consumidor (ex. `Properties<string>().HaveMaxLength(255)` no `DbContext`). Se a entidade de origem permitir um valor mais longo que esse default, salvar esse valor estoura a coluna de auditoria e **derruba o `SaveChanges` da operação de negócio inteira**, não só o log — o erro aparece como "String or binary data would be truncated" apontando pra tabela `*AuditLog`.

**Convenção recomendada:** todo `.For(x => x.Prop)` de tipo string espelha o `HasMaxLength` do mapeamento da entidade de origem. Para campos `.Sensitive()` isso é irrelevante — o valor gravado é sempre o literal `"***"` (3 caracteres), independente do tamanho do dado original.

Exceção: `CamposAlteradosJson` já sai do gerador com `HasColumnType("nvarchar(max)")` fixo — essa coluna específica é imune a esse problema.

---

## Erros Comuns e Diagnóstico

### Source generator não gera nada

- Verificar `OutputItemType="Analyzer"` e `ReferenceOutputAssembly="false"` no csproj
- Configurador precisa ser `public`, herdar de `AuditConfigurator<T>`, decorado com `[GenerateAuditLog]`
- `ForOwned` com menos de 2 argumentos gera um diagnostic de erro em vez de código — usar sempre a forma `ForOwned(nav, config)`
- SoftDelete: DbContext precisa de `[GenerateSoftDelete]` + entidades `ISoftDeleteEntity`
- Rodar `dotnet clean && dotnet build`

### AuditSaveInterceptor não salva

- `AddGeneratedAuditConfigurations()` foi chamado no `AuditRegistry`?
- `ApplyGeneratedAuditMaps()` foi chamado no `OnModelCreating`?
- Interceptor adicionado via `AddInterceptors(new AuditSaveInterceptor(registry))`?
- Se não há configuradores `[GenerateAuditLog]`, nada é auditado

### CS0102 em `{Entidade}AuditLog` ou `{Elemento}AuditLog`

- Ver armadilha A acima — corrigido em v0.5.0 via renomeação automática (`EntityId`), mas prefira uma chave de negócio explícita pra manter o nome da coluna previsível

### "String or binary data would be truncated" na tabela `*AuditLog`

- Ver armadilha B acima — faltou `.HasMaxLength(n)` espelhando a entidade de origem

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
├── AuditLog.Generator.SoftDelete/  # Source generator soft delete
└── AuditLog.Historico/             # Histórico legível a partir das tabelas *AuditLog
```

### Arquivos-chave

| Arquivo | Propósito |
|---------|-----------|
| `src/AuditLog.Abstractions/AuditConfigurator.cs` | `For`/`ForOwned`/`ForEach` — pontos de entrada da DSL |
| `src/AuditLog.EntityFrameworkCore/AuditSaveInterceptor.cs` | Interceptor principal |
| `src/AuditLog.EntityFrameworkCore/AuditLogServiceCollectionExtensions.cs` | `AddAuditLogging` (DI) |
| `src/AuditLog.Generator/AuditLogGenerator.cs` | Entry point do generator |
| `src/AuditLog.Generator/ConfiguratorDetector.cs` | Encontra configuradores |
| `src/AuditLog.Generator/ExpressionParser.cs` | Parse de lambdas — `CollectModifiers` é a lista definitiva de modificadores reconhecidos |
| `src/AuditLog.Generator/Helpers.cs` | Geração de propriedades/colunas + `ResolveSafeColumnName` (desambiguação CS0102) |
| `src/AuditLog.Generator/RootEntityGenerator.cs` | Gera `{Entity}AuditLog` + Descriptor + Map |
| `src/AuditLog.Generator/CollectionEntityGenerator.cs` | Gera `{Elemento}AuditLog` + Descriptor + Map |
| `src/AuditLog.Generator/ExtensionGenerator.cs` | Gera `AddGeneratedAuditConfigurations`/`ApplyGeneratedAuditMaps` |
| `src/AuditLog.Historico/AuditHistoricoMapper.cs` | Monta o histórico legível a partir de um `*AuditLog` |
| `src/AuditLog.EntityFrameworkCore.SoftDelete/SoftDeleteInterceptor.cs` | Interceptor soft delete |
| `src/AuditLog.Generator.SoftDelete/SoftDeleteGenerator.cs` | Generator soft delete |

### Testes

```
tests/
├── AuditLog.Tests/                        # Unitários (generator + runtime)
├── AuditLog.IntegrationTests/             # Integração EF (SQL Server via Testcontainers)
├── AuditLog.SoftDelete.Tests/
├── AuditLog.SoftDelete.Reflection.Tests/
└── AuditLog.SoftDelete.Generator.Tests/
```

`tests/AuditLog.Tests/AuditLogGenerationTests.cs`, `NotificacaoAuditConfigurator.cs`, `PacienteAuditConfigurator.cs` e `UsuarioAuditConfigurator.cs` são a melhor referência de uso real da DSL (`ForEach`, `ForOwned`, desambiguação de nome).

---

## Pack & Publish

### Pack local

```bash
./pack.sh
# Gera .nupkg em artifacts/packages/ (6 pacotes: Abstractions, EntityFrameworkCore, Generator, EntityFrameworkCore.SoftDelete, Generator.SoftDelete, Historico)
```

### Publicar nova versão (NuGet.org)

1. Incrementar versão e commitar:
```bash
git add . && git commit -m "feat: ..."
```

2. Criar tag e push:
```bash
git tag v{version}  # ex: v0.5.1
git push origin v{version}
```

3. O GitHub Action `publish.yml` dispara automaticamente, executa:
   - `dotnet restore && dotnet build`
   - `dotnet test` (`AuditLog.Tests`, `AuditLog.IntegrationTests`, `AuditLog.SoftDelete.Generator.Tests`, `AuditLog.SoftDelete.Reflection.Tests`)
   - `dotnet pack` dos 6 pacotes
   - Push para NuGet.org via OIDC (login samueldias21)

4. Verificar publicação:
```bash
curl -s "https://api.nuget.org/v3-flatcontainer/AuditLog.Abstractions/index.json"
```

5. Atualizar versão no topo deste skill file

### CI/CD

Workflow: `.github/workflows/publish.yml` — trigger em push de tags `v*`. Usa MinVer para inferir versão das tags.

### MinVer

- Tag `v0.5.0` → versão `0.5.0`
- Tag `v0.5.1-beta1` → versão `0.5.1-beta.1`
- Sem tag → `0.0.0-alpha.{commitCount}`
