---
name: dotnet-integration-tests
description: "Use ao escrever ou revisar teste de integração em projeto .NET da SES-RJ — xunit, Testcontainers, fixture de banco real, DatabaseFixture/DatabaseCollection, teste contra AppDbContext/EF Core de verdade."
---

# Skill: dotnet-integration-tests

**Tipo:** internal

> **Regra dura, não negociável: projeto de teste sempre em `/tests/` na raiz do repositório,
> nunca dentro de `/src/` junto dos outros projetos.** Ex.: `tests/<NomeDoProjeto>.Tests.Integration/`
> — nunca `src/<NomeDoProjeto>.Tests.Integration/`. Mesma regra de `dotnet-unit-tests`, sem exceção.
> Verifique se a `.slnx`/`.sln` da solução já declara a pasta `<Folder Name="/tests/" />` vazia —
> é comum que já esteja lá reservada mesmo antes do primeiro projeto de teste existir.

Muitos projetos .NET da SES-RJ ainda não têm nenhum projeto de teste de integração no início.
Esta skill documenta o padrão a seguir quando o primeiro projeto de teste de integração for
criado, transcrito por completo de `~/dev/ses/back/new-biae/main/tests/Biae.Tests.Integration/`
— projeto real, maduro, em produção, no mesmo ecossistema SES. Os arquivos
`IntegrationTestBase.cs`, `Fixtures/DatabaseFixture.cs`, `Fixtures/DatabaseCollection.cs`, os
três `Fixtures/Fake*.cs` e múltiplos arquivos de teste reais foram lidos por completo antes desta
transcrição. Se o projeto alvo usa **SQL Server** (verifique a configuração de
`DbContextOptionsBuilder`/`UseSqlServer(...)` no registro de infraestrutura), igual ao Biae, o
módulo correto é **`Testcontainers.MsSql`**, não Postgres nem outro banco — adapte o módulo do
Testcontainers ao banco real do projeto quando for diferente.

## 1. O que é (e o que NÃO é) teste de integração aqui

| É | NÃO é |
|---|---|
| Sobe um **container real** de SQL Server via Testcontainers | Não mocka `IProdutoRepository`/repositório nenhum — o repositório real roda contra o banco real |
| Roda contra o `AppDbContext`/EF Core de verdade (`src/<NomeDoProjeto>.Infra.Data/Contexts/AppDbContext.cs`) | Não usa `UseInMemoryDatabase` como substituto de container real (ver nota na seção 4) |
| Verifica comportamento que só existe com banco real: tradução de query, constraint de FK/índice único, soft delete/audit interceptor, migration | Não sobe dependências externas caras/lentas que não são o objeto do teste (S3, fila) — isso é fake, não container (seção 6) |
| Compartilha **um único container** entre uma coleção inteira de classes de teste, resetando dados entre testes | Não sobe um container novo por teste — caro e lento (dezenas de segundos por classe) |

Regra prática de decisão: se o teste precisa que o EF Core realmente gere SQL contra um schema
real (constraint, índice, filtro global de soft delete, interceptor de auditoria), é teste de
integração. Se a unidade sob teste só recebe interfaces injetadas e nenhuma delas precisa ser
"de verdade", é teste unitário — ver `dotnet-unit-tests`.

## 2. Convenção de nomenclatura

Mesmo padrão único definido em `dotnet-unit-tests`, seção 2 — ver lá o detalhamento completo
(classe `Testes`, arquivo `<ClasseTestada>Testes.cs`, método
`<AcaoOuMetodoTestado>_<Cenario>_<ResultadoEsperado>` em português, terceira parte sempre
`Deve...`/`NaoDeve...`, nunca inglês). Aplicado a teste de integração:

```
ResetAsync_AposInserirRegistro_DeveLimparTabelaParaProximoTeste
SoftDelete_AoRemoverEntidade_DeveDefinirIsDeletedEDeletedAt
ConfigureAppServices_AoRegistrarBuilders_DeveRespeitarOrdemPorLevel
```

O que muda de `dotnet-unit-tests` é só o que está sendo testado (comportamento real de
banco/EF Core em vez de interação com mock) — a forma do nome é idêntica nas duas skills.

## 3. Onde mora e `.csproj`

Convenção de pasta/projeto (adapte `<NomeDoProjeto>` ao nome real da solução):

```
tests/<NomeDoProjeto>.Tests.Integration/
```

Um único projeto de integração para a solução inteira — é o padrão real do Biae
(`tests/Biae.Tests.Integration/`, um projeto só, cobrindo services de várias camadas de
domínio), não um projeto por camada como no teste unitário.

`Biae.Tests.Integration.csproj` (lido por completo, `~/dev/ses/back/new-biae/main/tests/Biae.Tests.Integration/Biae.Tests.Integration.csproj`):

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <IsPackable>false</IsPackable>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>
    <TestingPlatformDotnetTestSupport>true</TestingPlatformDotnetTestSupport>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="xunit.v3" />
    <PackageReference Include="Testcontainers.MsSql" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" />
    <PackageReference Include="Microsoft.Extensions.Configuration" />
    <PackageReference Include="NSubstitute" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\..\src\Biae.Api\Biae.Api.csproj" />
    <ProjectReference Include="..\..\src\Biae.Application\Biae.Application.csproj" />
    <ProjectReference Include="..\..\src\Biae.Domain\Biae.Domain.csproj" />
    <ProjectReference Include="..\..\src\Biae.Infra.Data\Biae.Infra.Data.csproj" />
    <ProjectReference Include="..\..\src\Biae.Infra.CrossCutting\Biae.Infra.CrossCutting.csproj" />
  </ItemGroup>

</Project>
```

(Omitido acima: `NPOI` e dois `ProjectReference` de módulos específicos do domínio do Biae —
`Biae.Core`, `Biae.Infra.BackgroundJobs`/`.Hangfire` — inclua-os só se o projeto alvo tiver
módulos equivalentes; não fazem parte do padrão mínimo a copiar.)

Pontos a replicar, adaptando `<NomeDoProjeto>.*` ao namespace real da solução:

- Mesmo par `OutputType=Exe` + `UseMicrosoftTestingPlatformRunner`/`TestingPlatformDotnetTestSupport`
  do teste unitário (seção 4 de `dotnet-unit-tests`) — é o mesmo runner MTP em toda a solução.
- `Testcontainers.MsSql` é o pacote que sobe o container real de SQL Server.
- **`NSubstitute` também aparece aqui** — não é exclusividade do projeto de teste unitário. O
  Biae usa `Substitute.For<T>()` dentro do projeto de integração para as dependências que não
  fazem sentido subir de verdade mesmo em um teste de integração (ex.: `ILogger<T>`,
  `ICapacitacaoService` num teste que testa só o job que o chama) — ver `dotnet-unit-tests`,
  seção 5.1, sobre esse achado real.
- `ProjectReference` só para os projetos de `src/` necessários para montar o cenário de teste —
  tipicamente `Infra.Data` (o `AppDbContext`), `Domain`, `Application` e `Infra.CrossCutting`.

Versão real lida em `Directory.Packages.props:67`: `Testcontainers.MsSql` `4.13.0` — citar como
referência — confirme a versão vigente no `Directory.Packages.props` do projeto alvo antes de
fixar uma versão nova.

## 3b. Execução — `dotnet test` funciona, mas exige opt-in no `global.json`

> **Achado operacional confirmado em projetos .NET da SES-RJ com este mesmo runner** (mesma causa e mesma solução de
> `dotnet-unit-tests`, seção 4b — vale igualmente para o projeto de integração): rodar
> `dotnet test` sem opt-in **falha** com o erro genérico `Testing with VSTest target is no longer
> supported by Microsoft.Testing.Platform`, mesmo com `TestingPlatformDotnetTestSupport=true` no
> `.csproj` — essa propriedade sozinha **não resolve** o problema.
>
> **A causa raiz não é o `.csproj`, é o `global.json`.** A solução é a mesma: adicionar a chave
> `test`, no mesmo nível de `sdk`:
>
> ```json
> {
>   "sdk": { ... },
>   "test": {
>     "runner": "Microsoft.Testing.Platform"
>   }
> }
> ```
>
> Com esse opt-in, `dotnet test` funciona normalmente — `[confirmado]` em migração real de 4
> projetos e 451 testes, 0 falhas.
>
> **Atenção à sintaxe**: com o opt-in ativo, `dotnet test <caminho>/Projeto.csproj` (passando o
> `.csproj` como argumento posicional) **deixa de funcionar** — passa a exigir `--project`:
>
> ```bash
> dotnet test --project tests/<NomeDoProjeto>.Tests.Integration/<NomeDoProjeto>.Tests.Integration.csproj
> ```
>
> `dotnet run` continua funcionando do mesmo jeito de sempre (mesmo runner MTP por trás):
>
> ```bash
> dotnet run --project tests/<NomeDoProjeto>.Tests.Integration/<NomeDoProjeto>.Tests.Integration.csproj
> ```
>
> Para filtrar por classe ou método específico, os dois aceitam os argumentos do runner MTP
> depois de `--`:
>
> ```bash
> dotnet test --project tests/<NomeDoProjeto>.Tests.Integration/<NomeDoProjeto>.Tests.Integration.csproj -- --filter-class '<Namespace>.<ClasseTestada>Testes'
> dotnet run --project tests/<NomeDoProjeto>.Tests.Integration/<NomeDoProjeto>.Tests.Integration.csproj -- --filter-method '<Namespace>.<ClasseTestada>Testes.<NomeDoMetodo>'
> ```
>
> `dotnet build` continua funcionando normalmente para só compilar o projeto de teste sem
> executar nada. Lembre que o teste de integração também precisa de Docker disponível para o
> Testcontainers subir o container de SQL Server.
>
> **Scripts de CI/Makefile** que chamem `dotnet test` passando o `.csproj` direto precisam ser
> ajustados para `--project` por causa da mudança de sintaxe. Detalhes sobre a versão estável do
> `xunit.v3` e a dependência transitiva `xunit.v3.mtp-v2` (que já define
> `IsTestingPlatformApplication=true` por conta própria) estão em `dotnet-unit-tests`, seção 4b.

## 4. Padrão de fixture: `DatabaseFixture` + `DatabaseCollection` + `IntegrationTestBase`

Este é o mecanismo central do teste de integração no Biae — resolve dois problemas ao mesmo
tempo: (a) subir um container por *coleção* de testes, não por teste individual (caro), e (b)
garantir que cada teste comece com o banco limpo, mesmo compartilhando o container.

### 4.1 `DatabaseFixture` — sobe/derruba o container, expõe `CreateDbContext()`/`ResetAsync()`

Transcrição literal de `Fixtures/DatabaseFixture.cs` (arquivo lido por completo):

```csharp
public sealed class DatabaseFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _container;
    private AuditSaveInterceptor _auditInterceptor = null!;
    private SoftDeleteInterceptor _softDeleteInterceptor = null!;

    public string ConnectionString => _container.GetConnectionString();

    public DatabaseFixture()
    {
        _container = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest")
            .Build();
    }

    public async ValueTask InitializeAsync()
    {
        await _container.StartAsync();
        // ... monta interceptors reais via DI mínimo (audit/soft delete) ...
        await EnsureDatabaseAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await _container.DisposeAsync();
    }

    public AppDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(ConnectionString)
            .AddInterceptors(_auditInterceptor, _softDeleteInterceptor)
            .Options;

        return new AppDbContext(options);
    }

    /// <summary>
    /// Esvazia todas as tabelas para que cada teste parta de um banco limpo. Sem isso os testes
    /// enxergam dados semeados por testes anteriores, já que a collection compartilha um só container.
    /// </summary>
    public async Task ResetAsync()
    {
        await using var context = CreateDbContext();

        var tabelas = context.Model.GetEntityTypes()
            .Select(tipo => new { Schema = tipo.GetSchema() ?? "dbo", Tabela = tipo.GetTableName() })
            .Where(tipo => !string.IsNullOrEmpty(tipo.Tabela))
            .Select(tipo => $"[{tipo.Schema}].[{tipo.Tabela}]")
            .Distinct()
            .ToArray();

        // As FKs são desabilitadas em bloco para dispensar ordenação topológica entre as tabelas.
        var script = new StringBuilder("SET QUOTED_IDENTIFIER ON;");
        foreach (var tabela in tabelas)
            script.AppendLine($"ALTER TABLE {tabela} NOCHECK CONSTRAINT ALL;");
        foreach (var tabela in tabelas)
            script.AppendLine($"DELETE FROM {tabela};");
        foreach (var tabela in tabelas)
            script.AppendLine($"ALTER TABLE {tabela} WITH CHECK CHECK CONSTRAINT ALL;");

        await context.Database.ExecuteSqlRawAsync(script.ToString());
    }

    private async ValueTask EnsureDatabaseAsync()
    {
        await using var context = CreateDbContext();
        await context.Database.EnsureCreatedAsync();
    }
}
```

Pontos-chave, membro a membro:

- `IAsyncLifetime` (xunit): `InitializeAsync()` roda uma vez, antes de qualquer teste da
  coleção; `DisposeAsync()` roda uma vez, depois do último teste — é isso que garante **um
  container para a coleção inteira**, não um por teste.
- `MsSqlBuilder(...).Build()` + `_container.StartAsync()`: sobe o container real via Docker.
  `ConnectionString` expõe a connection string real gerada pelo Testcontainers (porta mapeada
  dinamicamente).
- `CreateDbContext()`: fábrica de `AppDbContext` real, apontando para o container, com os
  mesmos interceptors (`AuditSaveInterceptor`, `SoftDeleteInterceptor`) que rodam em produção —
  o teste de integração não usa uma versão "capada" do `AppDbContext`.
- `EnsureCreatedAsync()` cria o schema no container a partir do model do EF Core — no Biae isso
  substitui rodar migrations reais para o cenário de teste (mais rápido; não valida a migration
  em si, só o schema resultante).
- `ResetAsync()`: gera um script SQL que desabilita todas as FKs, faz `DELETE FROM` em toda
  tabela do model, e reabilita as FKs — evita ter que calcular ordem topológica de exclusão
  tabela a tabela. Chamado **entre** testes (seção 4.3), não no `InitializeAsync()`.

### 4.2 `DatabaseCollection` — compartilha o fixture entre uma coleção de classes

Transcrição literal de `Fixtures/DatabaseCollection.cs`:

```csharp
[CollectionDefinition("DatabaseCollection")]
public sealed class DatabaseCollection : ICollectionFixture<DatabaseFixture>
{
}
```

`ICollectionFixture<DatabaseFixture>` (xunit) é o mecanismo que faz o xunit instanciar
**um único** `DatabaseFixture` (logo, um único container) e compartilhá-lo entre toda classe de
teste marcada com `[Collection("DatabaseCollection")]` — é isso que evita subir um container por
classe de teste.

### 4.3 `IntegrationTestBase` — classe base abstrata, reset automático entre testes

Transcrição literal de `IntegrationTestBase.cs`:

```csharp
[Collection("DatabaseCollection")]
public abstract class IntegrationTestBase(DatabaseFixture fixture) : IAsyncLifetime
{
    protected DatabaseFixture Fixture { get; } = fixture;

    public virtual async ValueTask InitializeAsync()
    {
        await Fixture.ResetAsync();
    }

    public virtual ValueTask DisposeAsync() => ValueTask.CompletedTask;

    protected AppDbContext CreateDbContext()
    {
        return Fixture.CreateDbContext();
    }
}
```

- `[Collection("DatabaseCollection")]` na classe base propaga para toda subclasse — não precisa
  repetir o atributo em cada classe de teste concreta.
- `DatabaseFixture fixture` chega via **injeção de construtor do xunit**: como a classe está na
  `DatabaseCollection`, o xunit injeta a mesma instância de `DatabaseFixture` (mesmo container)
  em toda classe de teste da coleção.
- `InitializeAsync()` roda **antes de cada teste individual** (diferente do `InitializeAsync` do
  `DatabaseFixture`, que roda uma vez para a coleção inteira) e chama `Fixture.ResetAsync()` —
  é aqui que o banco limpo por teste é garantido, mesmo com container compartilhado.
- Uma classe de teste concreta só precisa herdar `IntegrationTestBase`, passar o `fixture`
  recebido para o construtor base, e usar `CreateDbContext()` — não repete nenhuma lógica de
  container/reset.

### 4.4 Teste de integração real, adaptado ao projeto alvo e à convenção de nomenclatura

Transcrição adaptada de `AuditSoftDeleteTests.cs:8-41` (renomeado ao padrão `Testes`/`Deve...`
desta skill, entidade trocada por `Produto` como exemplo genérico ilustrativo):

```csharp
public sealed class AuditSoftDeleteTestes : IntegrationTestBase
{
    public AuditSoftDeleteTestes(DatabaseFixture fixture) : base(fixture) { }

    [Fact]
    public async Task SoftDelete_AoRemoverEntidade_DeveDefinirIsDeletedEDeletedAt()
    {
        var produto = new Produto("Produto Teste", 10);

        await using (var context = CreateDbContext())
        {
            context.Set<Produto>().Add(produto);
            await context.SaveChangesAsync(TestContext.Current.CancellationToken);
        }

        await using (var context = CreateDbContext())
        {
            var carregado = context.Set<Produto>()
                .IgnoreQueryFilters()
                .First(p => p.Id == produto.Id);
            context.Set<Produto>().Remove(carregado);
            await context.SaveChangesAsync(TestContext.Current.CancellationToken);
        }

        await using (var context = CreateDbContext())
        {
            var carregado = await context.Set<Produto>()
                .IgnoreQueryFilters()
                .FirstAsync(p => p.Id == produto.Id, TestContext.Current.CancellationToken);

            Assert.True(carregado.IsDeleted);
            Assert.NotNull(carregado.DeletedAt);
        }
    }
}
```

Notas:

- Cada bloco `await using (var context = CreateDbContext())` abre um `AppDbContext` novo — o
  teste simula requisições/unidades de trabalho separadas, do jeito que produção realmente opera
  (um `DbContext` por escopo), em vez de reaproveitar tracking de um único contexto do início ao
  fim.
- `IgnoreQueryFilters()` é necessário para enxergar a entidade depois do soft delete — o filtro
  global de `IsDeleted` (documentado em `dotnet-domain`) esconde a entidade por padrão, e é
  exatamente esse comportamento real de EF Core que o teste de integração valida (um teste
  unitário com repositório mockado nunca provaria isso).
- `TestContext.Current.CancellationToken` é o mesmo mecanismo do xunit.v3/MTP citado em
  `dotnet-unit-tests`, seção 5.2.

### 4.5 Respawn — reset mais rápido que `DELETE FROM` manual, recomendado a partir de 2026-08-31

> Diferente das seções 4.1-4.4 (transcrição literal do Biae), esta seção **não** é transcrição de
> um projeto legado — é uma recomendação atualizada, validada empiricamente em dois projetos reais
> do ecossistema SES na mesma semana. Use Respawn em vez do script `NOCHECK`/`DELETE`/`CHECK` da
> seção 4.1 sempre que o projeto tiver muitas tabelas (auditoria por `[GenerateAuditLog]` infla
> rápido a contagem — ver `audit-log`) e/ou a suíte for grande o suficiente para o custo por teste
> importar.

**Por que o `DELETE FROM` manual da seção 4.1 fica caro**: o script gera 3 statements por tabela
(`ALTER TABLE ... NOCHECK CONSTRAINT ALL`, `DELETE FROM`, `ALTER TABLE ... WITH CHECK CHECK
CONSTRAINT ALL`) executados a cada teste. Com poucas tabelas (dezenas) o custo é desprezível; num
projeto real com tabelas de auditoria (`*AuditLog`, uma ou mais por entidade com
`[GenerateAuditLog]`), a contagem passa facilmente de 80-100 tabelas, e cada `ALTER TABLE` é uma
operação de metadado com custo de lock de schema — o script cresce para ~300 statements por
teste, executados centenas de vezes (uma vez por teste da suíte).

**Validação empírica** (não é estimativa):
- `~/dev/ses/back/sindras/main`: já usa `Respawn` `7.0.0` em produção
  (`Directory.Packages.props`, `tests/Sindras.Tests.Integration/Common/Extensions/TestScenarioHelper.cs`),
  primeiro precedente do pacote no ecossistema SES. Fixture nesse projeto é `IClassFixture`
  (container por classe), não `ICollectionFixture` — padrão de fixture diferente do documentado
  na seção 4.2 desta skill, citado aqui só como referência de uso da API do Respawn.
- `~/dev/ses/back/estomizados` (2026-08-31): projeto com o **mesmo formato de fixture desta
  skill** (`ICollectionFixture`/`IntegrationTestBase`, seção 4.2-4.3) e com testes batendo em
  endpoints HTTP reais via `WebApplicationFactory` (não `CreateDbContext()` direto como no exemplo
  da seção 4.4) — cenário mais próximo do que um projeto real tende a virar depois que a suíte
  cresce. ~95 tabelas transacionais (66 regulares + ~45 `*AuditLog` − 16 lookup), 428 testes.
  Suíte completa **antes** (script `NOCHECK`/`DELETE`/`CHECK` da seção 4.1): 188,757s (3m08s).
  **Depois** (Respawn, mesma suíte, mesmas 6 falhas pré-existentes não relacionadas, 0 falhas
  novas): ~44s. **Ganho de ~77% no tempo total da suíte.**

**Adaptação ao padrão `ICollectionFixture`/`WebApplicationFactory` desta skill** (diferente do
`DatabaseFixture` simples da seção 4.1 — quando os testes batem em HTTP real via
`WebApplicationFactory`, cada request resolve um `AppDbContext` novo via DI, então o `Respawner`
não pode reaproveitar a conexão interna do EF Core; abra uma `SqlConnection` dedicada):

```csharp
// Adicionar ao .csproj do projeto de teste (mesma versão usada no Sindras):
// <PackageReference Include="Respawn" /> + Directory.Packages.props:
// <PackageVersion Include="Respawn" Version="7.0.0" />

private Respawner? _respawner;

public async Task ResetAsync()
{
    // ... lógica de preservar linhas específicas de uma tabela "especial" tipo Usuario,
    // se o projeto tiver esse caso, continua rodando DEPOIS do Respawner.ResetAsync ...

    if (_respawner is null)
    {
        await using var conn = new SqlConnection(_dbContainer.GetConnectionString());
        await conn.OpenAsync();
        _respawner = await Respawner.CreateAsync(conn, new RespawnerOptions
        {
            DbAdapter = DbAdapter.SqlServer,
            // LookupTables = as mesmas tabelas de seed/referência da seção 4.1, mais
            // "__EFMigrationsHistory" se o projeto rodar Database.MigrateAsync() de verdade
            // (em vez de EnsureCreatedAsync()) — essa tabela existe no schema e não pode ser
            // apagada pelo Respawn.
            TablesToIgnore = LookupTables
                .Append("__EFMigrationsHistory")
                .Select(t => (Respawn.Graph.Table)t)
                .ToArray()
        });
    }

    await using var resetConn = new SqlConnection(_dbContainer.GetConnectionString());
    await resetConn.OpenAsync();
    await _respawner.ResetAsync(resetConn);
}
```

Pontos-chave:

- `Respawner` é **cacheado** (campo privado, criado uma única vez na primeira chamada) — recriar
  a cada teste recalcularia o grafo de FK à toa, seria tão caro quanto o script manual.
- `TablesToIgnore` cobre as mesmas tabelas de lookup/seed que a seção 4.1 preserva — reaproveite a
  mesma constante, não duplique a lista.
- Se o projeto aplica migrations reais (`dbContext.Database.MigrateAsync()`, não
  `EnsureCreatedAsync()` como no exemplo da seção 4.1), `__EFMigrationsHistory` entra em
  `TablesToIgnore` também — sem isso o Respawn tenta (e falha, ou apaga) uma tabela de controle do
  próprio EF Core.
- Caso o projeto tenha uma regra de preservação parcial de linhas específicas (ex.: manter um
  usuário semeado no boot + um usuário criado sob demanda pelo mecanismo de autenticação fake do
  teste, apagando o resto) — isso **não é algo que o Respawn resolve**: ele só apaga tabela
  inteira ou ignora tabela inteira. Mantenha esse tipo de lógica como um `DELETE ... WHERE Id NOT
  IN (...)` manual, rodando **depois** de `_respawner.ResetAsync(...)`, exatamente como antes.

**Quando ainda vale manter o `DELETE FROM` manual da seção 4.1**: projeto pequeno (poucas dezenas
de tabelas, suíte pequena) onde o ganho não compensa a dependência extra — nesse caso o script
simples da seção 4.1 continua sendo a opção mais direta, sem pacote adicional.

## 5. Por que não `UseInMemoryDatabase`

O provider `Microsoft.EntityFrameworkCore.InMemory` aparece no `.csproj` de integração do Biae e
é usado em vários arquivos de teste (`UnidadeServiceTests.cs`, `InscricaoEmailNotificacaoTests.cs`),
mas **não substitui** o container real — é usado só nos testes que não dependem de nenhum
comportamento específico de SQL Server (constraint, filtro global traduzido para SQL real, etc.)
e preferem a velocidade do provider em memória. Ao escrever teste novo em qualquer projeto: prefira o
padrão `DatabaseFixture`/Testcontainers (seção 4) sempre que o comportamento sob teste depende de
schema real (soft delete, audit, índice único, FK) — é o único jeito de pegar um bug que só
aparece contra SQL Server de verdade.

## 6. Fakes — quando usar em vez de container real

Nem toda dependência externa de um teste de integração deve subir "de verdade". O Biae mantém
três fakes em `Fixtures/`, um por dependência externa cara/lenta que não é o objeto do teste:

`FakeObjectStoreService.cs` (transcrição literal):

```csharp
public sealed class FakeObjectStoreService : IObjectStoreService
{
    private readonly Dictionary<string, byte[]> _store = new();

    public void Semear(string key, byte[] bytes) => _store[key] = bytes;

    public Task<Stream> GetAsync(string objectKey, CancellationToken cancellationToken = default)
    {
        if (_store.TryGetValue(objectKey, out var bytes))
            return Task.FromResult<Stream>(new MemoryStream(bytes));
        throw new FileNotFoundException($"Key '{objectKey}' not found in fake store.");
    }

    public Task<string> UploadAsync(Stream fileStream, string fileName, string? contentType = null,
        CancellationToken cancellationToken = default)
    {
        using var ms = new MemoryStream();
        fileStream.CopyTo(ms);
        _store[fileName] = ms.ToArray();
        return Task.FromResult(fileName);
    }

    public Task DeleteAsync(string objectKey, CancellationToken cancellationToken = default)
    {
        _store.Remove(objectKey);
        return Task.CompletedTask;
    }
}
```

`FakeBackgroundJobService.cs` (transcrição literal): implementa `IBackgroundJobService`
gravando os jobs enfileirados/recorrentes em listas em memória (`JobsEnfileirados`,
`JobsRecorrentes`) em vez de realmente agendar nada — o teste depois faz
`Assert.Contains(nomeDoJob, fake.JobsEnfileirados)`.

`FakeUserContext.cs` (transcrição literal): implementação mínima de `IUserContext` com
`UsuarioId`/`IsAdmin` fixos, passados no construtor — usada para simular "usuário logado" sem
precisar de autenticação real no teste.

### Fake vs. container real — critério de decisão

| Situação | Escolha |
|---|---|
| Banco de dados (queries, constraints, soft delete, audit) | **Container real** (`Testcontainers.MsSql`) — é o próprio objeto do teste de integração |
| Storage de objetos (S3/similar), fila/job em background, contexto de usuário autenticado | **Fake em memória** — dependência externa cara/lenta cuja implementação real não é o que está sob teste; um fake com `Dictionary`/lista em memória é suficiente para verificar a interação |
| Serviço HTTP de terceiro (API pública) | **Fake/stub dedicado**, implementando a interface do cliente (ver `dotnet-service`) — nunca chamar a API real em teste |

Regra prática: container real é para a dependência que **é o assunto do teste de integração**
(o próprio banco). Toda outra dependência externa cara ou lenta que só precisa "participar" do
cenário, sem ser verificada em si, ganha um fake dedicado em `Fixtures/`.

## 7. Checklist de revisão

- [ ] O projeto de teste está em `tests/<NomeDoProjeto>.Tests.Integration/` na raiz, nunca em `src/`?
- [ ] A classe de teste tem sufixo `Testes` e segue `<AcaoOuMetodoTestado>_<Cenario>_<ResultadoEsperado>`
      em português (mesma regra de `dotnet-unit-tests`, seção 2)?
- [ ] A classe de teste herda `IntegrationTestBase` e está implicitamente na
      `DatabaseCollection` (via classe base) — não sobe um `MsSqlContainer` próprio?
- [ ] Usa `CreateDbContext()` da fixture em vez de instanciar `AppDbContext` manualmente com uma
      connection string hardcoded?
- [ ] Não depende de estado deixado por outro teste — `ResetAsync()` roda antes de cada teste via
      `IntegrationTestBase.InitializeAsync()`, então nenhuma ordem entre testes deveria importar?
- [ ] Dependências externas caras/lentas que não são o assunto do teste (storage, fila,
      contexto de usuário) usam fake dedicado, não a implementação real nem `Substitute.For<T>()`
      solto sem verificação de interação?
- [ ] O teste realmente precisa de banco real — se não precisa de nenhum comportamento
      específico de SQL Server, considerar se não deveria ser teste unitário (`dotnet-unit-tests`)?
- [ ] `IgnoreQueryFilters()` usado explicitamente quando o teste precisa enxergar entidade
      soft-deleted?

## 8. Skills relacionadas

- `dotnet-repositories` — `AppDbContext`, `EntityMap`, `UnityOfWork`; é contra essas peças reais
  que o teste de integração roda, sem nenhum mock de repositório.
- `dotnet-service` — services de aplicação exercitados de ponta a ponta (banco real) num teste
  de integração, em vez de com dependências mockadas (`dotnet-unit-tests`).
- `dotnet-ioc-startup` — composition root; um teste de integração pode validar que o wiring de DI
  realmente resolve um service/registry (ex.: `ConfigureAppServices_...` na seção 2).
- `tdd-first` — quando a demanda pede implementação orientada a teste envolvendo comportamento
  real de banco, o teste de integração desta skill vem antes do código de produção.
- `dotnet-unit-tests` — convenção de nomenclatura completa (seção 2 lá), e quando preferir mock
  de interface a container real.
- `audit-log` — tabelas `*AuditLog` geradas por `[GenerateAuditLog]` são o principal motivo da
  contagem de tabelas inflar num projeto real (seção 4.5).
