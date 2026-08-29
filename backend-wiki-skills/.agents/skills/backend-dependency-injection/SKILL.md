---
name: backend-dependency-injection
description: Use ao criar ou refatorar componentes .NET que dependem de services, repositories, clients ou infraestrutura, mantendo inversão de controle, lifetimes corretos e baixo acoplamento.
---

# Backend Dependency Injection (.NET)

## Quando usar

Use quando:

- uma classe instancia diretamente dependência de infraestrutura;
- surgem muitos `new` para services, clients ou repositories;
- uma classe precisa receber dependências externas;
- há registro ou alteração em `IServiceCollection`;
- é necessário escolher entre `Transient`, `Scoped` e `Singleton`;
- é necessário melhorar testabilidade.

## Objetivo

Usar o container de DI do .NET de forma explícita, com dependências coesas e lifetimes compatíveis, reduzindo acoplamento e facilitando testes.

## Procedimento

1. Identifique quais colaboradores são dependências reais da classe.
2. Prefira injeção por construtor.
3. Registre dependências no composition root já adotado pelo projeto, normalmente `Program.cs` ou métodos de extensão de `IServiceCollection`.
4. Escolha o lifetime conscientemente:
   - `Transient`: instância nova por resolução;
   - `Scoped`: uma instância por escopo/requisição;
   - `Singleton`: uma instância para toda a aplicação.
5. Não injete serviço `Scoped` diretamente em `Singleton`.
6. Para `HttpClient`, prefira `IHttpClientFactory`, typed clients ou named clients quando o projeto já usar esse padrão.
7. Se houver interface, use-a quando ela representar uma abstração útil, não apenas por formalismo.
8. Evite Service Locator, acesso global a `IServiceProvider` e resolução manual dentro da regra de negócio.
9. Mantenha o número de dependências coerente com uma única responsabilidade.

## Preferências

- injeção por construtor;
- referências imutáveis;
- contratos pequenos e coesos;
- lifetimes explícitos e compatíveis;
- `IOptions<T>`/`IOptionsMonitor<T>` para configurações quando apropriado;
- mocks/fakes apenas nas fronteiras necessárias em testes.

## Sinais de alerta

- construtor com dependências demais;
- `IServiceProvider.GetRequiredService` espalhado pela aplicação;
- serviço `Scoped` capturado por `Singleton`;
- dependência opcional sem regra clara;
- ciclos entre services;
- domínio dependendo de ASP.NET Core sem necessidade;
- criação manual de repository/client dentro de regra de negócio.

## Checklist

- [ ] Dependências estão explícitas?
- [ ] Injeção por construtor foi utilizada quando viável?
- [ ] Lifetimes estão corretos?
- [ ] Não há `Scoped` capturado por `Singleton`?
- [ ] Não existe ciclo novo?
- [ ] A classe continua com responsabilidade única?
- [ ] A testabilidade melhorou ou foi preservada?
