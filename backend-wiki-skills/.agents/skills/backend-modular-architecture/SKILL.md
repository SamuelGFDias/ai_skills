---
name: backend-modular-architecture
description: Use ao criar, reorganizar ou revisar projetos, módulos e camadas de uma aplicação .NET backend, buscando baixo acoplamento, responsabilidades claras e evolução independente.
---

# Backend Modular Architecture (.NET)

## Quando usar

Use esta skill quando a tarefa envolver:

- criação de novo módulo ou domínio;
- reorganização de projetos, namespaces ou camadas;
- Controller/endpoint com regra de negócio excessiva;
- Application Service fazendo acesso técnico demais;
- Repository contendo lógica de aplicação;
- dependências cíclicas entre projetos;
- necessidade de dividir funcionalidade grande em partes independentes;
- revisão arquitetural de backend .NET.

## Objetivo

Preservar uma arquitetura modular na qual funcionalidades sejam divididas em módulos coesos, com fronteiras claras e dependências controladas, sem impor uma arquitetura nova ao repositório.

## Procedimento

1. Inspecione a `.sln`, os `.csproj`, namespaces e estrutura atual.
2. Identifique módulos/domínios existentes e seus limites.
3. Classifique responsabilidades conforme a arquitetura já adotada, normalmente entre:
   - entrada/HTTP;
   - aplicação/orquestração;
   - domínio/regra de negócio;
   - persistência/integração;
   - infraestrutura/configuração.
4. Identifique violações de fronteira, dependências circulares e referências entre projetos que invertam a direção arquitetural existente.
5. Faça a menor alteração que melhore a modularidade sem reescrever o projeto inteiro.
6. Preserve contratos públicos e namespaces públicos quando possível.
7. Evite introduzir interfaces, handlers, repositories ou camadas apenas por formalismo.
8. Valide build e testes.

## Regras

- Controller/endpoint recebe requisição, trata aspectos HTTP e delega a execução.
- Regra de negócio não deve depender diretamente de `HttpContext`, Controller ou detalhes de transporte sem necessidade.
- Persistência deve ficar atrás da abstração já adotada pelo projeto; não force Repository Pattern se o projeto usa `DbContext` diretamente na camada adequada.
- Um módulo não deve acessar detalhes internos de outro sem contrato explícito.
- Evite classes `Utils`, `Helpers` ou serviços genéricos que concentrem responsabilidades não relacionadas.
- Prefira coesão por funcionalidade/domínio quando isso estiver alinhado ao projeto existente.
- Não transforme uma tarefa localizada em migração completa para Clean Architecture, CQRS ou outro padrão sem solicitação explícita.

## Sinais de problema

- classe com muitas dependências de construtor;
- service com dezenas de métodos não relacionados;
- Controller acessando banco diretamente sem justificativa arquitetural;
- entidade EF Core vazando como contrato HTTP em toda a aplicação;
- projeto `Common`/`Shared` virando depósito de lógica de negócio;
- referência circular entre `.csproj`;
- alteração em um módulo exigindo mudança em vários outros sem necessidade.

## Checklist

- [ ] A responsabilidade nova está no módulo/projeto correto?
- [ ] A direção das dependências está clara?
- [ ] A regra de negócio está separada do transporte HTTP?
- [ ] A persistência está encapsulada conforme o padrão atual?
- [ ] Não foi criada referência circular?
- [ ] Não foi introduzida arquitetura nova sem necessidade?
- [ ] A mudança foi incremental e compatível com o projeto?
- [ ] Build/testes continuam válidos?
