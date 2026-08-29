---
name: backend-api-openapi
description: Use ao criar ou alterar APIs REST em ASP.NET Core, endpoints, contratos HTTP e documentação OpenAPI/Swagger, mantendo contratos claros, consistentes e testáveis.
---

# Backend API + OpenAPI (.NET)

## Quando usar

Use para:

- novos endpoints REST em ASP.NET Core;
- Controllers ou Minimal APIs;
- alteração de request/response;
- mudança de status HTTP;
- documentação OpenAPI/Swagger;
- revisão de contrato público;
- parametrização de route params, query params, filtros ou body.

## Objetivo

Manter a API consistente, tipada e documentada, permitindo que consumidores entendam, integrem e testem o contrato sem depender de detalhes internos da aplicação.

## Procedimento

1. Inspecione endpoints semelhantes já existentes e preserve o estilo adotado pelo projeto: Controllers ou Minimal APIs.
2. Preserve convenções de rota, versionamento, nomes de recursos e serialização JSON.
3. Defina claramente:
   - método HTTP;
   - rota;
   - parâmetros;
   - DTO de entrada;
   - DTO de saída;
   - resposta de sucesso;
   - respostas de erro relevantes.
4. Não exponha diretamente entidades do EF Core ou modelos internos apenas por conveniência.
5. Use DTOs/contracts quando houver fronteira pública relevante.
6. Atualize a descrição OpenAPI usando os mecanismos já adotados pelo projeto, por exemplo:
   - OpenAPI nativo do ASP.NET Core;
   - Swashbuckle;
   - NSwag;
   - atributos/anotações existentes.
7. Quando a lista puder crescer, combine com `backend-pagination`.
8. Quando houver acesso restrito, combine com `backend-security`.
9. Valide model binding, validação de entrada e serialização.
10. Teste o endpoint e valide o documento OpenAPI gerado.

## Regras

- Contrato HTTP não deve depender da entidade de persistência por conveniência.
- Use códigos HTTP coerentes com a operação.
- Preserve `CancellationToken` nas operações assíncronas quando o padrão do projeto utilizar cancelamento.
- Evite bloquear código assíncrono com `.Result`, `.Wait()` ou equivalentes.
- Erros não devem vazar stack trace, segredo ou detalhe interno sensível.
- Documentação deve refletir o comportamento real da implementação.
- Mudança breaking precisa ser tratada como mudança de contrato, não como simples refatoração.
- Não mude Controllers para Minimal APIs, ou o inverso, sem necessidade explícita.

## Checklist

- [ ] Método HTTP e rota estão coerentes?
- [ ] Request e response estão explícitos?
- [ ] DTOs estão separados das entidades quando necessário?
- [ ] Status codes estão corretos?
- [ ] Model binding e validação foram considerados?
- [ ] A documentação OpenAPI foi atualizada?
- [ ] Não há vazamento de dados internos?
- [ ] Compatibilidade com consumidores foi considerada?
- [ ] Endpoint foi testado?
