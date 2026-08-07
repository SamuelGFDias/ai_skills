---
name: dotnet-backend-architecture
description: "Use sempre que a tarefa envolver backend .NET, C#, ASP.NET Core, APIs, services, repositories, Entity Framework, validacao, DDD, Clean Architecture, arquitetura de camadas, revisao de backend ou sugestao de implementacao backend. Aplica um padrao generico inspirado no Sindras: contratos separados, Application como orquestracao, Domain com invariantes, Infra nas bordas, validators/builders dedicados e testes por comportamento."
---

# Skill: dotnet-backend-architecture

Use esta skill como padrao arquitetural para qualquer projeto backend .NET. O estilo foi extraido de um projeto real grande, mas deve ser aplicado de forma generica e adaptado aos nomes, pastas e bibliotecas do repo atual.

## Principio central

Organize o backend em camadas com responsabilidades claras:

- API/Presentation recebe HTTP, autentica/autoriza, converte requests e retorna responses.
- Application Contracts expoe interfaces, DTOs, requests, responses e contratos publicos dos casos de uso.
- Application orquestra casos de uso, validacoes de fluxo, transacoes, builders, mappers, repositories e integracoes.
- Domain concentra entidades, value objects, invariantes, regras centrais, factories e contratos de repositorio.
- Domain Shared/Core guarda tipos compartilhados, enums, exceptions, helpers estaveis e modelos base.
- Infra implementa persistencia, repositories, Entity Framework, storage, identidade, mensageria, clients externos e detalhes tecnicos.
- IoC/Bootstrap registra dependencias, configuracoes e adapters externos.
- Tests espelha as camadas e valida comportamento observavel.

Nao misture responsabilidades para ganhar velocidade local. A mudanca pequena correta ainda deve respeitar a direcao das dependencias.

## Regra de dependencia

Mantenha dependencias apontando para dentro:

- API depende de Application Contracts e configuracao transversal.
- Application depende de Contracts, Domain e abstracoes de Infra quando necessario.
- Domain nao depende de API, EF, HTTP, storage, identity provider, fila, cache ou serializacao.
- Infra depende de Domain/Application Contracts para implementar interfaces e persistir entidades.
- Contracts nao deve conhecer implementacoes concretas de Application ou Infra.

Se uma regra de negocio precisa de EF, HTTP, storage ou um provider externo para existir, provavelmente ela esta na camada errada.

## API e controllers

Controllers devem ser finos:

- Receber dados por `[FromRoute]`, `[FromQuery]`, `[FromBody]` ou `[FromForm]`.
- Extrair contexto de usuario/autorizacao somente quando necessario.
- Converter request de transporte para DTO/command da Application.
- Chamar um service de Application.
- Retornar `Ok`, `CreatedAtAction`, `NoContent`, `File`, `NotFound` ou erro padronizado.

Evite colocar regra de negocio, query complexa, validacao extensa, persistencia ou chamada direta a provider externo no controller.

Para upload multipart, prefira um request dedicado na API e uma conversao explicita para DTO da Application. O DTO da Application nao deve depender de `IFormFile`; modele um tipo neutro quando o projeto ja tiver esse padrao.

## Application

Services de Application sao orquestradores de fluxo:

- Buscar entidades e dados necessarios.
- Chamar validators para validacao de request, arquivo, estado e permissao.
- Chamar metodos ricos do dominio para executar regras centrais.
- Usar builders/factories para construir objetos quando a criacao tiver decisao ou muitos campos.
- Coordenar repositories, unidade de trabalho, transacoes e callbacks de cleanup.
- Mapear entidades para DTOs de saida.
- Encapsular integracoes externas atras de interfaces.

Nao transforme service em entidade anemica gigante. Se a regra altera estado ou protege uma invariante da entidade, mova para o Domain.

## Mediator e handlers

Quando o projeto se beneficia de commands, queries ou handlers, use Wolverine no papel de mediator, mantendo o fluxo de aplicacao simples e explicito:

- Use Wolverine para encaminhar mensagens para handlers e separar casos de uso quando isso reduzir acoplamento ou facilitar testes.
- Mantenha handlers pequenos, focados em um caso de uso, e delegue regras de negocio para entidades, value objects e validators.
- Nao introduza Wolverine apenas para encapsular uma chamada direta que um service ja resolve com clareza.
- Nao use Wolverine como justificativa para mover toda a regra para handlers, criar uma cadeia de handlers sem necessidade ou acoplar o Domain ao framework.
- O Domain, contratos e entidades nao devem depender de Wolverine; a integracao fica em API/Application/IoC conforme o desenho do projeto.

Se o projeto nao precisa de mediator, mantenha services de Application como orquestradores. Nao adicione simultaneamente outro mediator apenas por habito.

## Mapeamentos explicitos

Prefira mapeamento manual sem AutoMapper ou outro pacote de mapeamento automatico:

- Coloque mappers na camada Application, em uma pasta como `Mappers`.
- Crie classes estaticas ou classes estaticas de extensao com metodos nomeados de forma explicita, por exemplo `ToDto`, `ToResponse`, `ToEntity` ou `Map`.
- Para mapeamentos simples, use construtores de DTO com os campos explicitamente selecionados.
- Componha mappers: um `NotificacaoMapper` pode chamar `Doenca.ToDto()`, `Paciente.ToDto()` e outros mappers, mantendo cada conversao localizavel e testavel.
- Para colecoes, forneca sobrecargas que usem `Select` e materializem o resultado conforme o contrato (`IList`, `IReadOnlyCollection` etc.).
- Quando uma infraestrutura generica exigir contrato, uma classe fina pode implementar `IManualMapper<TEntity, TDto>` e delegar para o metodo estatico/extensao. O contrato nao deve esconder a regra de conversao.
- Nao retorne entidades diretamente da API e nao coloque mapeamento de DTO dentro das entidades do Domain.
- Evite mapeamento implicito, reflexao ou convencoes que escondam campos, relacionamentos, conversoes de enum e regras de nulabilidade.

Ao criar ou alterar um DTO, procure os mappers existentes e adicione testes unitarios do mapeamento quando houver conversao, composicao ou regra de apresentacao relevante.

## Validators

Centralize validacoes fora dos services quando houver padrao equivalente:

- Request validators para formato, obrigatoriedade e regras de entrada.
- Entity/state validators para garantir existencia, tipo correto, situacao permitida e permissao contextual.
- File validators para tamanho, extensao, content type e obrigatoriedade.
- Validators pequenos e reutilizaveis para regras repetidas.

Use FluentValidation quando o projeto ja usa. Use validators estaticos ou classes dedicadas quando a regra for de dominio/aplicacao e nao couber bem no pipeline de request.

Services podem chamar validators, mas nao devem acumular blocos longos de validacao inline.

## Builders e factories

Use builders ou factories quando a construcao tiver:

- Muitos parametros.
- Conversao de DTO para entidade.
- Estado inicial diferente por caso de uso.
- Chamadas sequenciais de metodos de dominio apos construcao.
- Regras de composicao que se repetem.

Evite `new Entidade { ... }` em services quando houver construtores ricos, builders ou factories. Prefira construtores/metodos que mantenham invariantes e propriedades com setters privados.

## Domain

Entidades devem proteger invariantes:

- Use construtores, metodos de comportamento e propriedades privadas para impedir estado invalido.
- Evite setters publicos para campos que afetam regra de negocio.
- Expresse transicoes com metodos de dominio, por exemplo `Aprovar`, `Cancelar`, `Confirmar`, `Anexar`, `Ativar`, `Inativar`.
- Lance exceptions de dominio/negocio com mensagens claras quando uma invariante for violada.
- Use value objects quando uma propriedade tiver validacoes complexas ou formato proprio, como CPF, email, telefone, dinheiro, documento, periodo, codigo ou faixa de valor.
- Use value objects para isolar um conceito composto que pertence a entidade, mas nao precisa de identidade nem tabela separada, como endereco, contato, coordenada, intervalo ou configuracao embutida.
- Use collections privadas com exposicao read-only quando a entidade controlar itens filhos.

Nao deixe o dominio ser moldado por necessidades de tela, endpoint ou banco.

## Infra e persistencia

Infra implementa detalhes tecnicos:

- Repositories implementam contratos do Domain ou da Application.
- EF Core fica em DbContext, EntityMaps/Configurations, migrations e repositories.
- Mapeamentos EF devem ficar fora das entidades.
- Use `IQueryable` com cuidado: exponha quando o projeto usa composicao de filtros na Application; caso contrario, prefira metodos especificos.
- Use `AsNoTracking`, `Include`, `AsSplitQuery`, paginacao e ordenacao conforme necessidade real.
- Unidade de trabalho deve concentrar `SaveChanges` e transacoes quando existe multiplas escritas.

Para operacoes com arquivo/storage e banco, execute upload/persistencia em transacao logica com cleanup do arquivo remoto em caso de erro, quando o projeto tiver suporte a callback de compensacao.

## Pacotes NuGet sugeridos

Ao propor ou implementar backend .NET, verifique primeiro se o projeto ja usa algum pacote equivalente. Se fizer sentido adicionar dependencia, sugira ou instale a versao compativel com o target framework e com os pacotes ja existentes no projeto.

Pacotes comuns que podem acelerar implementacoes:

- `FluentValidation` para validators de requests, commands e DTOs.
- `Microsoft.EntityFrameworkCore` e provider correspondente, como `Microsoft.EntityFrameworkCore.SqlServer`, `Npgsql.EntityFrameworkCore.PostgreSQL` ou `Pomelo.EntityFrameworkCore.MySql`, para persistencia relacional.
- `Microsoft.EntityFrameworkCore.Design` para migrations e ferramentas EF.
- `WolverineFx` para mediator, commands, queries e handlers quando o projeto realmente se beneficia desse fluxo. Use somente o papel de mediator neste padrao; nao adicione outro mediator em paralelo.
- `Scrutor` para assembly scanning no IoC quando o projeto nao tiver scanner proprio.
- `Serilog.AspNetCore` para logging estruturado.
- `Swashbuckle.AspNetCore` ou `NSwag.AspNetCore` para OpenAPI/Swagger.
- `Polly` para retry, timeout, circuit breaker e resiliencia em clients externos.
- `Refit` para clients HTTP tipados quando o projeto favorece interfaces declarativas.
- `Quartz.Extensions.Hosting` ou `Hangfire` para jobs, escolhendo apenas um conforme necessidade e padrao local.
- `Testcontainers` para testes de integracao com banco, fila ou servico externo real.
- `NSubstitute`, `Moq` ou `FakeItEasy` para doubles em testes unitarios, mantendo o framework ja usado pelo repo.
- `Bogus` para geracao de massa de teste.
- `FluentAssertions` para asserts legiveis quando ja estiver no padrao do projeto.

Nao adicione pacote por conveniencia se a funcionalidade for pequena, se o projeto ja tiver solucao interna, ou se a dependencia aumentar complexidade sem ganho claro. Quando o usuario nao quiser dependencia externa, ou quando o pacote nao for adequado ao contexto, implemente "na mao" com codigo simples, testavel e aderente aos padroes locais.

## IoC

Registre dependencias de forma previsivel:

- Prefira interfaces por caso de uso ou por repository.
- Use assembly scanning quando o projeto ja tiver marcadores de camada.
- Services, repositories e validators normalmente sao scoped.
- Clients externos, caches e SDKs seguem o lifetime recomendado pela biblioteca.
- Evite registrar concretos espalhados sem motivo; concentre bootstrap em um modulo de IoC/Extensions.

Se o projeto usa marcadores como `IApplicationContracts`, `IApplicationServices`, `IDomain` ou `IInfraData`, mantenha novas interfaces herdando do marcador correto para entrar no scanning.

## Contratos e DTOs

Separe modelos por fronteira:

- Request/Response HTTP pertencem a API.
- DTOs e commands de caso de uso pertencem a Application Contracts.
- Entidades pertencem ao Domain.
- Modelos de provider externo pertencem a Infra da integracao.

Nao retorne entidade de dominio diretamente em controller. Nao injete DbContext em controller. Nao deixe DTO de API atravessar o dominio.

## Consultas

Para telas de consulta, filtros e paginacao:

- Reaproveite infraestrutura compartilhada de query quando existir.
- Mantenha filtros, ordenacao default e paginacao consistentes.
- Evite duplicar includes e regras de acesso em varios services; extraia especificacoes, extensions ou query services quando houver repeticao real.
- Aplique regra de acesso antes de materializar a query.

## Testes

Priorize testes por comportamento:

- Domain tests para invariantes, transicoes de estado e value objects.
- Application tests para orquestracao, validacao de fluxo, uso de repositories e transacoes.
- Infra tests para repository, EF mappings e integracoes tecnicas quando houver risco.
- API tests para binding, status code, autorizacao e contrato HTTP.
- Integration tests para fluxos entre camadas quando o risco justificar.

Ao implementar mudanca de comportamento, escreva ou ajuste teste antes do codigo de producao quando viavel. Execute pelo menos os testes diretamente afetados.

## Como propor uma implementacao

Antes de editar ou sugerir codigo backend .NET:

1. Identifique a camada correta para cada responsabilidade.
2. Procure padroes existentes no repo para nomes, pastas, exceptions, mappers, validators, builders, repositories e testes.
3. Defina o contrato primeiro quando houver novo caso de uso.
4. Planeje teste de comportamento.
5. Implemente de dentro para fora quando a regra for de dominio; implemente de fora para dentro quando o contrato HTTP ja estiver definido.
6. Preserve convencoes locais mesmo que o exemplo generico desta skill use outro nome.

## Checklist de revisao

Antes de concluir, verifique:

- Controller ficou fino?
- Service apenas orquestra ou virou dono de regra de dominio?
- Wolverine esta sendo usado somente quando simplifica o fluxo de mediator/handlers?
- Validacoes repetidas foram para validators?
- Criacao complexa foi para builder/factory?
- Mapeamentos estao explicitos em classes estaticas/metodos `ToDto`/`Map`, sem AutoMapper desnecessario?
- Entidade protege estado invalido?
- Infra nao vazou para Domain?
- DTO/request correto atravessa cada fronteira?
- Transacao e cleanup foram considerados para multiplas escritas ou storage?
- Dependencia nova foi registrada seguindo o padrao local?
- Existe teste cobrindo o comportamento novo ou alterado?

## Sinais de alerta

Revise a solucao se aparecer:

- Controller com query EF, regra de negocio ou chamada direta a repository.
- Service com muitos `if` de validacao que poderiam ser validators ou dominio.
- Entidade com setters publicos para estado critico.
- Domain referenciando ASP.NET, EF Core, storage, cache ou provider externo.
- Repository contendo regra de negocio.
- DTO de API usado diretamente como entidade ou modelo de provider.
- `SaveChanges` espalhado em varios pontos do mesmo caso de uso.
- Upload de arquivo sem validacao centralizada ou sem cleanup em falha posterior.
- Nova abstracao criada sem reduzir duplicacao, acoplamento ou complexidade real.
