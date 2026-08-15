---
name: backend-dependency-management
description: Use ao adicionar, remover ou atualizar dependências, plugins e versões em Maven ou Gradle, mantendo o build reproduzível e evitando conflitos.
---

# Backend Dependency Management

## Quando usar

Use quando mexer em:

- `pom.xml`;
- `build.gradle` / `build.gradle.kts`;
- BOMs;
- plugins de build;
- versões de bibliotecas;
- dependências transitivas;
- exclusões de dependência.

## Objetivo

Usar Maven ou Gradle como fonte explícita e reproduzível das dependências da aplicação, reduzindo conflitos e dependências desnecessárias.

## Procedimento

1. Descubra se o projeto usa Maven ou Gradle.
2. Verifique se existe BOM/dependency management centralizado.
3. Antes de adicionar biblioteca, procure solução já existente na stack.
4. Use versão compatível com o framework principal.
5. Evite declarar versão individual quando o BOM oficial já a gerencia.
6. Avalie dependências transitivas e conflitos.
7. Remova dependência antiga apenas depois de confirmar que não há uso.
8. Rode build e testes.

## Regras

- Prefira dependências oficiais ou amplamente mantidas.
- Evite duas bibliotecas com a mesma responsabilidade sem motivo concreto.
- Não atualize um conjunto grande de dependências em uma tarefa não relacionada.
- Em upgrade de Spring Boot, trate primeiro a matriz de compatibilidade do framework.
- Dependências de teste não devem vazar para runtime.

## Checklist

- [ ] A dependência é realmente necessária?
- [ ] Já existe recurso equivalente no projeto?
- [ ] A versão é compatível com o framework?
- [ ] O escopo está correto?
- [ ] Não há conflito transitivo conhecido?
- [ ] Build reproduzível continua funcionando?
- [ ] Testes passaram?
