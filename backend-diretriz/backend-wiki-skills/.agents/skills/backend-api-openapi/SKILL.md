---
name: backend-api-openapi
description: Use ao criar ou alterar APIs REST, endpoints, contratos HTTP e documentação Swagger/OpenAPI, mantendo contratos claros, consistentes e testáveis.
---

# Backend API + OpenAPI

## Quando usar

Use para:

- novos endpoints REST;
- alteração de request/response;
- mudança de status HTTP;
- documentação Swagger/OpenAPI;
- revisão de contrato público;
- parametrização de filtros, path params ou query params.

## Objetivo

Manter a API consistente e documentada, permitindo que consumidores entendam e testem o contrato.

## Procedimento

1. Inspecione os endpoints semelhantes já existentes.
2. Preserve convenções de rota, versão e nomes de recursos.
3. Defina claramente:
   - método HTTP;
   - rota;
   - parâmetros;
   - body;
   - resposta de sucesso;
   - respostas de erro relevantes.
4. Não exponha diretamente detalhes internos que não façam parte do contrato.
5. Atualize/anote a documentação OpenAPI.
6. Quando a lista puder crescer, combine com `backend-pagination`.
7. Quando houver acesso restrito, combine com `backend-security`.
8. Teste o endpoint e valide o documento OpenAPI gerado.

## Regras

- Contrato HTTP não deve depender de entidade de persistência por conveniência.
- Use códigos HTTP coerentes com a operação.
- Erros não devem vazar stack trace, segredo ou detalhe interno sensível.
- Documentação deve refletir o comportamento real da implementação.
- Mudança breaking precisa ser tratada como mudança de contrato, não como simples refatoração.

## Checklist

- [ ] Método HTTP e rota estão coerentes?
- [ ] Request e response estão explícitos?
- [ ] Status codes estão corretos?
- [ ] A documentação OpenAPI foi atualizada?
- [ ] Não há vazamento de dados internos?
- [ ] Compatibilidade com consumidores foi considerada?
- [ ] Endpoint foi testado?
