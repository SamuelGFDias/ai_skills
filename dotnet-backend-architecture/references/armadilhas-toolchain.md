# Armadilhas de toolchain .NET

Detalhe por area das armadilhas que custam mais de uma tentativa. Regra e sintoma primeiro; a explicacao
so quando ela evita repetir o erro. Nomes de tipo/pacote sao literalmente os da API .NET; nomes de
projeto devem ser adaptados ao repo atual.

## NuGet com Central Package Management (CPM)

**Versao que so um projeto precisa: `VersionOverride`, nao editar `Directory.Packages.props`.** Com
`ManagePackageVersionsCentrally=true`, `<PackageReference Include="X" Version="Y" />` em csproj folha e
erro de restore NU1008. Em vez de alargar o manifesto central (blast radius = todo o repo) para uma versao
que um projeto atipico precisa:

```xml
<PackageReference Include="X" VersionOverride="Y" />
```

Requer `CentralPackageVersionOverrideEnabled` nao explicitamente desligado — o default e `true`. Sintoma de
que se errou o caminho: NU1008 no restore.

**Alvo mais estreito que o resto do repo nao herda as assemblies de referencia.** Um projeto
`netstandard2.0` nao tem `System.Collections.Immutable` (`ImmutableArray<T>`) nem `IAsyncDisposable`
(`Microsoft.Bcl.AsyncInterfaces`) — os dois aparecem naturalmente em contrato imutavel/async e precisam de
PackageReference explicito.

## Roslyn source generator

**`PrivateAssets="all"` no proprio pacote Roslyn nao atravessa `ProjectReference`.** E o valor correto no
projeto do generator (nao vaza para o consumidor via NuGet), mas o projeto de teste que precisa de fato
dirigir o generator herda so o grafo transitivo antigo. O teste precisa da sua propria referencia
`Microsoft.CodeAnalysis.CSharp` na versao ja pinada pelo CPM e, muito provavelmente,
`Microsoft.CodeAnalysis.CSharp.Workspaces` com `VersionOverride` na mesma versao — sem isso, NU1608 vira
erro sob `TreatWarningsAsErrors=true`, porque o SDK encaminha warnings NU16xx por esse mesmo switch.

**O harness oficial do pacote de teste nao e automaticamente o melhor caminho.** O
`CSharpSourceGeneratorTest<TGenerator, TVerifier>` exige `TVerifier : IVerifier`, vindo de um pacote
companheiro (`...SourceGenerators.Testing.XUnit` ou `...Testing.Verifiers.XUnit`) que frequentemente nao
esta no conjunto de pacotes do repo. Antes de alargar dependencia para caber num harness que nao se
precisa, considere um driver proprio pequeno: `CSharpCompilation` +
`CSharpGeneratorDriver.RunGeneratorsAndUpdateCompilation`, referencias de metadata de
`AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")`, saida = fontes geradas + diagnosticos numa string
unica. Encaixa melhor no snapshot livre do Verify do que o modelo "codigo esperado fixo" do harness.

**Saida do generator nao pode depender de propriedade MSBuild que o generator nao controla.**
`ISymbol.GetDocumentationCommentXml()` devolve string vazia quando a compilacao foi parseada com
`DocumentationMode.None` — modo que o compilador escolhe para qualquer projeto sem
`<GenerateDocumentationFile>true</GenerateDocumentationFile>`, o default em projeto de aplicacao. Se a
cadeia de resolucao depende desse tier, ela falha para TODOS os membros e cai no fallback sem emitir
diagnostico. Fallback: ler a trivia `///` crua. Teste: afirmar saida byte-identica entre
`DocumentationMode.None` e `.Diagnose` — nao so no default `Parse`, que um harness caseiro tende a fixar e
que nunca corresponde a configuracao do consumidor real.

## Diagnostico: valor errado porem plausivel

**Antes de investigar corrupcao, enumere os fallbacks que o codigo pode produzir legitimamente.** Se o
valor observado e igual a um fallback alcancavel, e branch pulado, nao byte danificado. Caso real:
descricao acentuada que aparece sem acento nao era encoding — a cadeia inteira caia no tier final ("usar o
identificador C#"), e um nome C# nao carrega diacritico. O erro ficou invisivel em 4 de 5 membros porque o
resumo XML deles repetia o proprio identificador, ou seja, valor correto e fallback coincidiam.

Duas consequencias praticas: (1) a massa de teste deve conter valor cujo correto NUNCA coincide com o
fallback (acento, nao-ASCII, string distincta); (2) a prova decisiva e um A/B controlado — compilar o
projeto consumidor real com `EmitCompilerGeneratedFiles=true`, uma vez com e uma vez sem
`GenerateDocumentationFile`, e comparar o arquivo gerado. Encolher a hipotese com um A/B de um unico
artefato custa menos do que inspecionar tres camadas suspeitas.

## EF Core

**`ExecuteSqlRawAsync(sql, object[] parameters)`: slot nulo e `null` literal, nunca `DBNull.Value`.**
`RawSqlCommandBuilder.Build` chama `GetMapping(parameter.GetType(), ...)` por parametro, e `typeof(DBNull)`
nao tem mapeamento relacional — resultado:
`InvalidOperationException: ... no store type mapping for properties of type 'DBNull'`. Referencia nula de
verdade e tratada a parte pelo EF (ele mesmo seta `DbParameter.Value = DBNull.Value`), mas um
`DBNull.Value` ja boxed nao e. Logo `(object?)value ?? DBNull.Value` quebra exatamente o caso que tentava
proteger. `DBNull.Value` pertence a leitura de coluna nula (`reader.IsDBNull`/comparacao), nao a escrita
via raw SQL.

**Seeding de teste nao e transferivel entre provider InMemory e provider relacional real.** Copiar a
construcao de entidade de um teste irmao so e seguro se o irmao roda no mesmo tier de provider.
`UseInMemoryDatabase` nao aplica FK, unique, default nem coluna computada; `Testcontainers.*` aplica.
Sintoma: o mesmo bloco de seeding passa no InMemory e falha no `SaveChangesAsync` com violacao de FK no
banco real, porque o id de pai era `Guid.CreateVersion7()` sem linha correspondente. Antes de copiar o
padrao, confirme qual `DbContext`/provider o exemplo realmente usa (busque `UseInMemoryDatabase` no
arquivo de origem) e semeie as linhas pai de verdade quando o alvo for relacional. Mesmo tipo de entidade
nao e evidencia de mesmo provider.

## PostgreSQL

**`SET`/`SET LOCAL` nao aceita bind parameter no valor** — a gramatica
`SET configuration_parameter { TO | = } value` exige constante literal. `SET statement_timeout = @timeoutMs`
falha em runtime. Interpole o literal ja validado (nunca input externo) e reserve parametro para os
`SELECT`/DML do mesmo fluxo, que aceitam normalmente
(`SELECT pg_advisory_lock(hashtext(@resource)::bigint)`). Nao generalize "tudo e parametrizavel" entre
classes de comando do mesmo banco: DDL e configuracao de sessao divergem de DML.

## Documentacao XML

**Ligar `GenerateDocumentationFile` pela primeira vez num repo maduro expoe CS1574 (cref nao resolvido),
nao apenas CS1591 (doc ausente).** Sao correcoes de natureza diferente — escrever prosa nova vs reparar
referencia existente — e num repo que ja escrevia doc comments por disciplina o segundo grupo costuma
dominar. Triagem: separe por codigo de erro antes de estimar o esforco; nao trate toda linha vermelha como
`<summary>` faltando.

Duas causas tipicas de CS1574: (a) `cref` cruzando fronteira de projeto cujo assembly o projeto atual nao
referencia de proposito — a correcao e virar `<c>` texto plano, seguindo a convencao que o repo ja usa
para esse caso, nunca deixar cref irresolvivel; (b) prefixo de qualificacao que e nome de pasta e nao
segmento de namespace, ou `using` que importa o conteudo do namespace sem tornar o segmento referenciavel
como qualificador.

## Provar RED em working tree compartilhado

**Nao use `git checkout`/`stash`/`reset`/`restore` para reexercitar comportamento antigo** quando a arvore
e compartilhada com outros agentes — mesmo escopado a um arquivo, muta estado git compartilhado e pode
destruir trabalho concorrente. O caminho que so usa leitura do git e as ferramentas de escrita de arquivo:

1. `git show HEAD:<path> > /tmp/<scratch>` — captura o conteudo pre-mudanca (leitura pura).
2. Sobrescreva o arquivo real com esse conteudo pela ferramenta de escrita.
3. Rode build/teste e capture a falha RED como evidencia.
4. Restaure o conteudo final pela ferramenta de escrita (do que ja foi composto, nao relendo o git).

Nenhuma mutacao de working tree nem de index acontece, entao nao ha o que destruir para um processo
concorrente, e o RED fica demonstrado mesmo quando codigo e teste foram escritos na mesma passada.
