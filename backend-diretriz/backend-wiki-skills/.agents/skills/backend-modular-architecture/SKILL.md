---
name: backend-modular-architecture
description: Use ao criar, reorganizar ou revisar módulos e camadas de uma aplicação backend, buscando baixo acoplamento, responsabilidades claras e evolução independente.
---

# Backend Modular Architecture

## Quando usar

Use esta skill quando a tarefa envolver:

- criação de novo módulo ou domínio;
- reorganização de pacotes/camadas;
- Controller com regra de negócio excessiva;
- Service fazendo acesso técnico demais;
- Repository contendo lógica de aplicação;
- dependências cíclicas;
- necessidade de dividir uma funcionalidade grande em partes independentes;
- revisão arquitetural de backend.

## Objetivo

Preservar uma arquitetura modular na qual funcionalidades sejam divididas em módulos coesos, com fronteiras claras e dependências controladas.

## Procedimento

1. Inspecione a estrutura atual do projeto.
2. Identifique módulos/domínios existentes e seus limites.
3. Classifique cada responsabilidade em pelo menos um destes grupos:
   - entrada/HTTP;
   - aplicação/orquestração;
   - domínio/regra de negócio;
   - persistência/integração;
   - infraestrutura/configuração.
4. Identifique violações de fronteira e dependências circulares.
5. Faça a menor alteração que melhore a modularidade sem reescrever o projeto inteiro.
6. Mantenha contratos públicos estáveis sempre que possível.
7. Valide build e testes.

## Regras

- Controller recebe requisição, valida o contrato HTTP e delega a execução.
- Regra de negócio não deve depender diretamente de detalhes de transporte HTTP.
- Persistência deve ficar atrás de componentes/repositórios apropriados.
- Um módulo não deve acessar detalhes internos de outro módulo sem contrato explícito.
- Evite classes utilitárias genéricas que concentrem responsabilidades não relacionadas.
- Prefira coesão por funcionalidade/domínio a agrupamentos artificiais somente por tipo técnico, quando o projeto já segue abordagem modular.

## Sinais de problema

- classe com muitas dependências de construtor;
- Service com dezenas de métodos não relacionados;
- Controller chamando Repository diretamente sem justificativa arquitetural;
- entidade de persistência vazando como contrato HTTP em toda a aplicação;
- pacote `util` virando depósito de lógica de negócio;
- alteração em um módulo exigindo mudança em vários outros sem necessidade.

## Checklist

- [ ] A responsabilidade nova está no módulo correto?
- [ ] A direção das dependências está clara?
- [ ] A regra de negócio está separada do transporte HTTP?
- [ ] A persistência está encapsulada?
- [ ] Não foi criada dependência circular?
- [ ] A mudança foi incremental e compatível com o projeto?
- [ ] Build/testes continuam válidos?
