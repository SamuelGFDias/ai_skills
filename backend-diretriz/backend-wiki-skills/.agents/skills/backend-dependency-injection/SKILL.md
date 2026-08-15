---
name: backend-dependency-injection
description: Use ao criar ou refatorar componentes que dependem de services, repositories, clients ou outros beans, mantendo inversão de controle e baixo acoplamento.
---

# Backend Dependency Injection

## Quando usar

Use quando:

- uma classe instancia diretamente outra dependência de infraestrutura;
- surgem muitos `new` para services/clients/repositories;
- uma classe precisa receber dependências externas;
- há refatoração de componentes Spring/Quarkus;
- é necessário melhorar testabilidade.

## Objetivo

Aplicar Injeção de Dependência para separar responsabilidades, controlar acoplamento e facilitar testes.

## Procedimento

1. Identifique quais colaboradores são dependências reais da classe.
2. Injete dependências por construtor sempre que a stack/padrão do projeto permitir.
3. Dependências devem representar contratos claros.
4. Evite Service Locator e acesso global a container.
5. Se houver interface, use-a quando ela representar uma abstração útil, não apenas por formalismo.
6. Mantenha a classe com número de dependências coerente com uma única responsabilidade.

## Preferências

- injeção por construtor;
- imutabilidade das referências de dependência;
- contratos pequenos e coesos;
- mocks/fakes apenas nas fronteiras necessárias em testes.

## Sinais de alerta

- construtor com dependências demais;
- dependência opcional sem regra clara;
- ciclo entre services;
- componente de domínio dependendo do framework sem necessidade;
- criação manual de repository/client dentro de regra de negócio.

## Checklist

- [ ] Dependências estão explícitas?
- [ ] Injeção por construtor é viável?
- [ ] Não existe ciclo novo?
- [ ] A classe continua com responsabilidade única?
- [ ] A testabilidade melhorou ou foi preservada?
