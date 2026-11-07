---
name: dotnet-unit-tests
description: "Use ao escrever ou revisar teste unitário em projeto .NET da SES-RJ — xunit, NSubstitute, mock de interface, teste de service/domínio isolado."
---

# Skill: dotnet-unit-tests

**Tipo:** internal

> **Regra dura, não negociável: projeto de teste sempre em `/tests/` na raiz do repositório,
> nunca dentro de `/src/` junto dos outros projetos.** Ex.: `tests/<NomeDoProjeto>.Application.Tests/`
> — nunca `src/<NomeDoProjeto>.Application.Tests/`. Essa regra vale para toda skill de teste,
> sem exceção. Verifique se a `.slnx`/`.sln` da solução já declara a pasta `<Folder Name="/tests/" />`
> vazia, esperando pelo primeiro projeto de teste — é comum já estar reservada.

Muitos projetos .NET da SES-RJ ainda não têm nenhum projeto de teste unitário no início —
nenhuma referência a "test" em `src/` nem em lugar nenhum do repositório. Esta skill não
documenta código já existente no projeto alvo (como `dotnet-repositories`/`dotnet-service` fazem
para pastas vazias declaradas em `.csproj`); ela documenta o **padrão a seguir quando o
primeiro projeto de teste unitário for criado**, transcrito de um projeto real, maduro e em
produção do mesmo ecossistema SES: `~/dev/ses/back/new-biae/main` (Biae), especificamente
`tests/Biae.Domain.Shared.Tests/`, `tests/Biae.Api.Tests/` e o uso de NSubstitute encontrado em
`tests/Biae.Tests.Integration/AtualizarSituacaoCapacitacaoJobTests.cs`. Todo trecho de código
abaixo foi lido por completo antes de ser transcrito ou adaptado.

## 1. O que é (e o que NÃO é) teste unitário aqui

| É | NÃO é |
|---|---|
| Isola **uma** unidade (service, value object, atributo, filtro) | Não sobe container nenhum |
| Dependências externas (repositório, `IUnityOfWork`, logger, cliente HTTP) são **interfaces mockadas com NSubstitute** | Não abre conexão real com banco, fila ou storage |
| Roda em milissegundos, sem I/O de rede/disco além do próprio processo de teste | Não usa `Testcontainers`, `DatabaseFixture` nem `AppDbContext` real — isso é `dotnet-integration-tests` |
| Testa invariante de domínio pura (value object, entidade) sem nenhum mock, quando a unidade não tem dependência externa | Não testa comportamento de EF Core, migration ou mapeamento — isso também é integração |

Regra prática de decisão: se a unidade sob teste **recebe uma interface no construtor**
(repositório, `IUnityOfWork`, `ILogger<T>`, cliente externo), o teste é unitário e essa
interface é mockada. Se o teste precisa que o EF Core realmente traduza uma query para SQL, ou
que uma constraint de banco realmente dispare, é teste de integração — ver `dotnet-integration-tests`.

## 2. Convenção de nomenclatura — padrão único, em português

> Este é o padrão normativo de nomenclatura de teste para **todo** o projeto — vale igualmente
> para `dotnet-integration-tests` (que referencia esta seção em vez de repetir o conteúdo).
> Convenção adotada nos projetos .NET da SES-RJ, intencionalmente divergente do Biae (que usa
> `Tests` em inglês): aqui o sufixo é `Testes`, em português, sem exceção.

### Classe de teste

Sufixo `Testes` (português), **nunca** `Tests` (inglês) — mesmo o Biae, referência canônica lida
para esta skill, usando `Tests` em todos os seus arquivos (`UnidadeServiceTests`,
`AuditSoftDeleteTests`, `CnesTest`). Para os demais projetos a decisão é deliberadamente diferente:

```
UsuarioServiceTestes
AppDbContextTestes
IoCGeneratedExtensionsTestes
```

### Arquivo

Acompanha o nome da classe: `<ClasseTestada>Testes.cs`. Ex.: classe `ProdutoServiceTestes` mora
em `ProdutoServiceTestes.cs`.

### Método de teste

Três partes em português, cada parte em `PascalCase`, separadas por `_`:

```
<AcaoOuMetodoTestado>_<Cenario>_<ResultadoEsperado>
```

Exemplos:

```
ListarUsuarios_QuandoFiltroVazio_DeveRetornarTodos
CriarUsuario_ComEmailJaCadastrado_DeveLancarArgumentException
CriarAsync_ComPrecoZeroOuNegativo_DeveLancarDomainException
```

Regras explícitas:

- **Nunca** usar convenção em inglês (`Should_...`, `When_...Then_...`, `Given_...`) nem
  misturar idioma dentro de um mesmo nome — nem no nome do método, nem no nome da classe.
- A terceira parte (resultado esperado) sempre começa com um verbo que descreve a expectativa:
  `Deve...` ou `NaoDeve...` (ex.: `DeveLancarExcecao`, `DeveRetornarListaVazia`,
  `NaoDeveAlterarOEstado`, `NaoDeveChamarORepositorio`).
- A primeira parte é o método/ação exercitada na unidade sob teste (`CriarAsync`,
  `ListarUsuarios`, `SetMunicipiosIds`), não uma paráfrase livre.
- A segunda parte descreve o cenário/pré-condição relevante (`ComEmailJaCadastrado`,
  `QuandoFiltroVazio`, `SemDependenciasObrigatorias`).

Esse padrão é usado nos exemplos de código da seção 5 abaixo, não fica só como regra abstrata.

## 3. Onde mora o projeto de teste

Convenção de pasta/projeto (adapte `<NomeDoProjeto>` ao nome real da solução; padrão a seguir ao
criar o primeiro projeto de teste):

```
tests/<NomeDoProjeto>.Application.Tests/       # testes de services de Application
tests/<NomeDoProjeto>.Domain.Tests/            # testes de entidades/value objects de Domain
tests/<NomeDoProjeto>.Api.Tests/               # testes de filtros, atributos, helpers da Api
```

Um projeto de teste unitário por camada testada, nomeado `<Camada>.Tests`, sempre dentro de
`tests/` na raiz — nunca dentro de `src/` (seção 0). Mapeia diretamente o padrão real do Biae:
`Biae.Domain.Shared.Tests` (testa `Biae.Domain`/`Biae.Domain.Shared`) e `Biae.Api.Tests` (testa
`Biae.Api`), cada um em `tests/<Nome>/`.

## 4. `.csproj` — estrutura real transcrita do Biae

`tests/Biae.Domain.Shared.Tests/Biae.Domain.Shared.Tests.csproj` (arquivo lido por completo):

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <IsPackable>false</IsPackable>
    <Nullable>enable</Nullable>
    <UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>
    <TestingPlatformDotnetTestSupport>true</TestingPlatformDotnetTestSupport>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="JetBrains.Annotations" />
    <PackageReference Include="xunit.v3" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\..\src\Biae.Domain\Biae.Domain.csproj" />
    <ProjectReference Include="..\..\src\Biae.Domain.Shared\Biae.Domain.Shared.csproj" />
  </ItemGroup>

</Project>
```

Pontos a replicar (adaptando `Biae.*` para `<NomeDoProjeto>.*`, o namespace real da solução):

- **`OutputType=Exe` + `UseMicrosoftTestingPlatformRunner=true` + `TestingPlatformDotnetTestSupport=true`**:
  o Biae usa o **Microsoft Testing Platform** nativo do `xunit.v3` (não o runner clássico
  VSTest). É essa combinação que faz `dotnet run`/`dotnet test` executar os testes.
  `[confirmado]` nos três `.csproj` de teste do Biae — nenhum deles difere nesse ponto.
- **Não referencia `Microsoft.NET.Test.Sdk`** diretamente, apesar de o pacote existir no
  catálogo central (`Directory.Packages.props:49`, versão `18.8.1`) — com o runner MTP do
  `xunit.v3`, o SDK de teste clássico não é necessário no `.csproj`. `[confirmado]`: os três
  `.csproj` de teste do Biae foram lidos e nenhum referencia esse pacote.
- `JetBrains.Annotations` só aparece nos projetos que usam o atributo `[TestSubject(typeof(X))]`
  (Rider) — opcional, não é parte essencial do padrão.
- Cada projeto de teste referencia, via `ProjectReference`, **só os projetos de `src/` que ele
  precisa** — não um `ProjectReference` para a solução inteira.

Versões reais lidas em `~/dev/ses/back/new-biae/main/Directory.Packages.props` — citar como
referência; confirme a versão vigente no `Directory.Packages.props` do projeto alvo antes de
fixar uma versão nova:

| Pacote | Versão | Linha |
|---|---|---|
| `Microsoft.NET.Test.Sdk` | `18.8.1` | `Directory.Packages.props:49` |
| `xunit.v3` | `4.0.0` | `Directory.Packages.props:62` |
| `NSubstitute` | `5.3.0` | `Directory.Packages.props:68` |

Para um projeto `tests/<NomeDoProjeto>.Application.Tests/`, o `.csproj` equivalente adicionaria
`PackageReference Include="NSubstitute"` (o Biae só referencia NSubstitute no projeto de
integração — seção 5 explica por quê isso não muda a recomendação geral).

## 4b. Execução — `dotnet test` funciona, mas exige opt-in no `global.json`

> **Achado operacional confirmado em projetos .NET da SES-RJ** (SDK .NET 10 `10.0.109` + `xunit.v3` `4.0.0`
> estável + `UseMicrosoftTestingPlatformRunner=true`): rodar `dotnet test` sem mais nada **falha**
> — erro genérico `Testing with VSTest target is no longer supported by
> Microsoft.Testing.Platform`. Isso vale mesmo com `TestingPlatformDotnetTestSupport=true` no
> `.csproj` — essa propriedade sozinha **não resolve** o problema. Quem seguir esta skill sem
> saber disso vai rodar `dotnet test`, ver esse erro, e ficar sem pista do que fazer — por isso
> este aviso vem em destaque.
>
> **A causa raiz não é o `.csproj`, é o `global.json`.** A solução é adicionar a chave `test`, no
> mesmo nível de `sdk`:
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
> Com esse opt-in, `dotnet test` volta a funcionar normalmente e roda a suíte inteira via MTP —
> `[confirmado]` em migração real de 4 projetos e 451 testes, 0 falhas. A própria mensagem de erro
> já aponta esse caminho ("you should opt-in to the new dotnet test experience",
> https://aka.ms/dotnet-test-mtp-error).
>
> **Atenção à sintaxe**: com o opt-in ativo, `dotnet test <caminho>/Projeto.csproj` (passando o
> `.csproj` como argumento posicional) **deixa de funcionar** — passa a exigir `--project`:
>
> ```bash
> dotnet test --project tests/<Projeto>.Tests/<Projeto>.Tests.csproj
> ```
>
> `dotnet run` continua funcionando do mesmo jeito de sempre (mesmo runner MTP por trás):
>
> ```bash
> dotnet run --project tests/<Projeto>.Tests/<Projeto>.Tests.csproj
> ```
>
> Para filtrar por classe ou método específico, os dois aceitam os argumentos do runner MTP
> depois de `--`:
>
> ```bash
> dotnet test --project tests/<Projeto>.Tests/<Projeto>.Tests.csproj -- --filter-class '<Namespace>.<ClasseTestada>Testes'
> dotnet run --project tests/<Projeto>.Tests/<Projeto>.Tests.csproj -- --filter-method '<Namespace>.<ClasseTestada>Testes.<NomeDoMetodo>'
> ```
>
> `dotnet build` continua funcionando normalmente para só compilar o projeto de teste sem
> executar nada.
>
> **Scripts de CI/Makefile** que chamem `dotnet test` passando o `.csproj` direto (sem
> `--project`) precisam ser ajustados por causa da mudança de sintaxe acima.
>
> **Pacote e dependências**: hoje existe `xunit.v3` `4.0.0` estável no nuget.org — deixou de ser
> pré-release, ver tabela de versões acima. O pacote sempre traz `xunit.v3.mtp-v2` como
> dependência transitiva, que já define `IsTestingPlatformApplication=true` por conta própria —
> ou seja, **não existe mais "modo VSTest clássico"** apenas evitando as propriedades MTP no
> `.csproj`: o opt-in no `global.json` é necessário de qualquer forma para `dotnet test`
> funcionar. Também requer `Microsoft.Testing.Platform.MSBuild` `>= 2.3.3`.

## 4c. Armadilha: Referências transitivas de projetos com `.esproj` e estruturas complexas

Ao criar um projeto de teste que referencia um projeto que já faz referências complexas —
especialmente quando há `.esproj` (projetos Angular/JavaScript) envolvidos — o MSBuild pode
tentar resolver transitivamente essas referências e falhar com erro como:

```
CSC : error CS0006: Arquivo de origem ".../<NomeDoProjeto>.ClientApp/dist/<NomeDoProjeto>.Client/<NomeDoProjeto>.ClientApp.exe" não pode ser encontrado
```

**Causa real**: `<NomeDoProjeto>.Api.csproj` referencia `<NomeDoProjeto>.ClientApp.esproj` (SDK JavaScript);
quando um terceiro projeto (ex.: `tests/<NomeDoProjeto>.Api.Tests/`) referencia `<NomeDoProjeto>.Api.csproj`,
o MSBuild tenta resolver transitivamente a saída do `.esproj` como se fosse um assembly .NET,
usando um caminho fictício que nunca é gerado (o build Angular real vai para `dist/browser`, não
para esse caminho `*.exe` fantasma). Esse problema **não ocorre ao compilar `<NomeDoProjeto>.Api.csproj`
diretamente** — só aparece quando outro projeto o referencia transitivamente.

**Solução**: Adicionar `<DisableTransitiveProjectReferences>true</DisableTransitiveProjectReferences>`
no `<PropertyGroup>` do `.csproj` do projeto de teste. Com isso desligado, adicione manualmente via
`<ProjectReference>` qualquer referência transitiva que o teste realmente necessite (ex.:
`<NomeDoProjeto>.Core`), em vez de depender da propagação automática.

Exemplo (formato de referência; adapte `<NomeDoProjeto>` ao projeto alvo):

```xml
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
  <OutputType>Exe</OutputType>
  <IsPackable>false</IsPackable>
  <Nullable>enable</Nullable>
  <UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>
  <TestingPlatformDotnetTestSupport>true</TestingPlatformDotnetTestSupport>
  <DisableTransitiveProjectReferences>true</DisableTransitiveProjectReferences>
</PropertyGroup>
```

## 5. Mock de interface com NSubstitute

### 5.1 Onde o NSubstitute é usado de fato no Biae — achado real

Buscando `Substitute.For` em todo `tests/` do Biae, o único ponto de uso real está em
`tests/Biae.Tests.Integration/AtualizarSituacaoCapacitacaoJobTests.cs:969-989` — **não** em
`Biae.Api.Tests` nem em `Biae.Domain.Shared.Tests` (nenhum dos dois referencia o pacote
NSubstitute no `.csproj`, e nenhum uso foi encontrado neles). Isso é uma particularidade da
organização atual do Biae (o teste unitário de um job especificamente mora dentro do projeto de
integração), não uma regra a copiar — em geral, NSubstitute é o pacote de teste unitário
por definição desta skill (mock de interface, sem I/O real), e deve ser referenciado por
`tests/<Camada>.Tests/`.

### 5.2 Exemplo real transcrito, com nomenclatura adaptada à convenção da seção 2

Transcrição literal de `AtualizarSituacaoCapacitacaoJobTests.cs:966-975` (renomeado ao padrão
`Testes`/`Deve...` desta skill):

```csharp
using NSubstitute;
using Xunit;

public sealed class AtualizarSituacaoCapacitacoesJobTestes
{
    [Fact]
    public async Task AtualizarAsync_QuandoJobExecutado_DeveChamarCapacitacaoService()
    {
        var capacitacaoService = Substitute.For<ICapacitacaoService>();
        var jobContext = Substitute.For<IJobContext>();
        var job = new AtualizarSituacaoCapacitacoesJob(capacitacaoService, jobContext);

        await job.AtualizarAsync(TestContext.Current.CancellationToken);

        await capacitacaoService.Received(1)
            .AtualizarSituacaoCapacitacoesAsync(TestContext.Current.CancellationToken);
    }
}
```

Mecânica NSubstitute usada aqui, membro a membro:

- `Substitute.For<TInterface>()` cria um duplo de teste (stub/mock) que implementa a interface
  sem nenhuma implementação real por trás.
- `await capacitacaoService.Received(1).Metodo(args)` verifica que o método foi chamado
  exatamente uma vez com os argumentos informados — falha o teste se não foi chamado, ou se foi
  chamado com argumentos diferentes.
- `TestContext.Current.CancellationToken` é o token de cancelamento do próprio xunit.v3/MTP para
  o teste em execução — usado tanto para passar como argumento quanto para propagar cancelamento
  do próprio framework de teste.
- Em `AtualizarSituacaoCapacitacaoJobTests.cs:1042`, o mesmo arquivo usa
  `Substitute.For<ILogger<CapacitacaoService>>()` para descartar completamente o logging real ao
  montar um service para teste — outro uso comum: mockar dependências "de infraestrutura" que o
  teste não quer exercitar (logger, cliente HTTP, serviço de e-mail).

### 5.3 Exemplo adaptado a um projeto ilustrativo: mockando `IProdutoRepository`/`IUnityOfWork`

`ProdutoService` (padrão documentado em `dotnet-service`, seção 3) recebe três interfaces no
construtor: `IProdutoRepository produtoRepository`, `IQuerySpecApplier querySpecApplier`,
`IUnityOfWork unityOfWork`. É exatamente esse desenho — dependências injetadas como interface
via primary constructor — que torna o service testável por mock:

```csharp
using NSubstitute;
using Xunit;

public sealed class ProdutoServiceTestes
{
    [Fact]
    public async Task CriarAsync_ComPrecoZeroOuNegativo_DeveLancarDomainException()
    {
        var repositorio = Substitute.For<IProdutoRepository>();
        var querySpecApplier = Substitute.For<IQuerySpecApplier>();
        var unityOfWork = Substitute.For<IUnityOfWork>();
        var service = new ProdutoService(repositorio, querySpecApplier, unityOfWork);
        var dto = new CriarProdutoDto("Produto Teste", Preco: 0);

        await Assert.ThrowsAsync<DomainException>(() => service.CriarAsync(dto));

        await repositorio.DidNotReceive().AddAsync(Arg.Any<Produto>());
        await unityOfWork.DidNotReceive().SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task CriarAsync_ComDadosValidos_DevePersistirEChamarSaveChanges()
    {
        var repositorio = Substitute.For<IProdutoRepository>();
        var querySpecApplier = Substitute.For<IQuerySpecApplier>();
        var unityOfWork = Substitute.For<IUnityOfWork>();
        var service = new ProdutoService(repositorio, querySpecApplier, unityOfWork);
        var dto = new CriarProdutoDto("Produto Teste", Preco: 10);

        var id = await service.CriarAsync(dto);

        Assert.NotEqual(Guid.Empty, id);
        await repositorio.Received(1).AddAsync(
            Arg.Is<Produto>(p => p.Nome == "Produto Teste"), Arg.Any<CancellationToken>());
        await unityOfWork.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
    }
}
```

Notas sobre o exemplo:

- `Arg.Any<T>()` casa com qualquer valor do tipo; `Arg.Is<T>(predicado)` restringe a verificação
  a instâncias que satisfaçam o predicado — aqui, confirma que o `Produto` persistido tem o
  `Nome` esperado, sem acoplar o teste a todos os campos do objeto.
  `DidNotReceive()` é o inverso de `Received()` — confirma que um método **não** foi chamado
  (útil para provar que uma invariante violada barra a persistência antes do repositório/UoW
  serem tocados).
- Nada aqui toca EF Core, banco ou `AppDbContext` real — `IProdutoRepository` é 100% duplo de
  teste. Se o objetivo fosse verificar que uma query realmente filtra certo no banco, isso vira
  teste de integração (`dotnet-integration-tests`).

### 5.4 Teste de domínio puro, sem nenhum mock

Quando a unidade sob teste não recebe dependência externa nenhuma — um value object, uma
entidade testando sua própria invariante — não há nada para mockar. Transcrição adaptada de
`Biae.Domain.Shared.Tests/ValueObject/CnesTest.cs:11-19` (renomeado ao padrão desta skill):

```csharp
using Xunit;

public class CnesTestes
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Construtor_ComValorNuloOuVazio_DeveLancarDomainException(string? input)
    {
        var ex = Assert.Throws<DomainException>(() => new Cnes(input!));
        Assert.Equal("CNES não pode ser nulo ou vazio.", ex.Message);
    }
}
```

`[Theory]`/`[InlineData]` (xunit) parametriza o mesmo teste para vários valores de entrada —
preferir a `[Fact]` sempre que múltiplos casos exercitam exatamente a mesma asserção com
entradas diferentes.

## 6. Conexão com os padrões já documentados no repositório

- `dotnet-service`: todo service de aplicação recebe suas dependências (repositório,
  `IUnityOfWork`, `IQuerySpecApplier`, etc.) como interface via construtor — é exatamente essa
  lista de parâmetros que um teste unitário de service mocka com `Substitute.For<T>()`.
- `dotnet-repositories`: `IDefaultRepository<TEntity>`/`IUsuarioRepository`
  (`src/<NomeDoProjeto>.Domain/Repositories/`) são as interfaces mockadas quando o teste unitário
  cobre um service que depende de repositório — o teste nunca instancia `AppDbContext` real.
- `dotnet-domain`: entidades e value objects com invariantes (`DomainException` ao violar regra)
  são o alvo natural de teste unitário sem mock nenhum (seção 5.4).

## 7. Checklist de revisão

- [ ] O projeto de teste está em `tests/<Nome>.Tests/` na raiz do repositório, nunca em `src/`?
- [ ] A classe de teste tem sufixo `Testes` (português), e o arquivo se chama
      `<ClasseTestada>Testes.cs`?
- [ ] O nome do método segue `<AcaoOuMetodoTestado>_<Cenario>_<ResultadoEsperado>`, em
      português, com a terceira parte começando por `Deve`/`NaoDeve`?
- [ ] Toda dependência externa da unidade sob teste (interface recebida via construtor) está
      mockada com `Substitute.For<T>()` — nenhuma instância real de repositório, `AppDbContext`,
      cliente HTTP ou logger concreto?
- [ ] Nenhum `Testcontainers`, `DatabaseFixture` ou conexão real de banco aparece neste projeto —
      se aparecer, o teste pertence a `dotnet-integration-tests`, não aqui.
- [ ] Asserções de comportamento usam `Received()`/`DidNotReceive()` para confirmar interação com
      o mock quando relevante, não só o valor de retorno?
- [ ] Testes de invariante de domínio pura (value object/entidade) não mockam nada — só
      instanciam o objeto real e verificam a exceção/estado.

## 8. Skills relacionadas

- `dotnet-service` — desenho de service de aplicação (construtor com interfaces injetadas), o
  alvo mais comum de teste unitário com NSubstitute.
- `dotnet-repositories` — contrato `IDefaultRepository<TEntity>`/repositórios específicos,
  interfaces mockadas nos testes de service.
- `dotnet-domain` — entidades, value objects e invariantes de domínio, o alvo de teste unitário
  sem mock (seção 5.4).
- `tdd-first` — quando a demanda pede implementação orientada a teste, escrever o teste unitário
  (esta skill) antes do código de produção.
- `dotnet-integration-tests` — quando a unidade sob teste depende de comportamento real de banco
  (query traduzida pelo EF Core, constraint, migration), não de uma interface mockável.
