---
name: backend-spring-boot-upgrade
description: Use exclusivamente para planejar e executar atualização de versão do Spring Boot e dependências relacionadas, reduzindo risco de incompatibilidade e regressão.
---

# Spring Boot Upgrade

## Quando usar

Use quando a tarefa solicitar:

- atualizar Spring Boot;
- migrar entre versões major/minor relevantes;
- corrigir incompatibilidades após upgrade do Spring;
- revisar dependências afetadas pelo BOM do Spring Boot.

## Objetivo

Executar upgrade de forma controlada, compatível com dependências, segurança, OpenAPI, persistência e runtime.

## Procedimento

1. Registre a versão atual do Spring Boot e do Java.
2. Identifique versão alvo.
3. Verifique requisitos mínimos de Java e mudanças breaking.
4. Atualize primeiro o gerenciamento central de versão/BOM.
5. Remova versões explícitas de dependências que devem ser gerenciadas pelo Boot, quando seguro.
6. Revise áreas frequentemente afetadas:
   - Spring Security;
   - Jakarta namespaces;
   - Spring Data/JPA;
   - configuração de propriedades;
   - OpenAPI/Swagger;
   - Actuator/health checks;
   - testes.
7. Compile após cada conjunto pequeno de mudanças.
8. Execute testes unitários e integração disponíveis.
9. Valide inicialização da aplicação e endpoints críticos.

## Regras

- não misture upgrade grande com refatoração funcional extensa;
- não force versões individuais contra o BOM sem motivo comprovado;
- trate warnings/deprecations relevantes durante a migração;
- preserve comportamento público da API, salvo mudança explicitamente solicitada.

## Checklist

- [ ] Java é compatível com a versão alvo?
- [ ] BOM/dependency management está consistente?
- [ ] Security foi validado?
- [ ] Persistência foi validada?
- [ ] OpenAPI/Swagger continua funcionando?
- [ ] Health checks continuam funcionando?
- [ ] Build e testes passaram?
- [ ] Aplicação inicia corretamente?
