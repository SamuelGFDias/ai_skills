---
name: backend-pagination
description: Use em endpoints e consultas .NET que retornam coleções potencialmente grandes, implementando paginação no banco com IQueryable/EF Core e evitando materialização prematura.
---

# Backend Pagination (.NET)

## Quando usar

Use quando:

- um endpoint retorna coleção sem limite;
- uma busca pode crescer significativamente;
- existe `IQueryable<T>`, EF Core, `Skip`/`Take` ou abstração equivalente;
- filtros e ordenação precisam ser combinados com paginação;
- o sistema está carregando todos os registros para paginar em memória.

## Diretriz

A paginação deve ocorrer **no banco e sob demanda**, mantendo a consulta como `IQueryable` até a aplicação de filtros, ordenação, projeção e recorte.

## Procedimento

1. Identifique a consulta e a cardinalidade esperada.
2. Defina `PageNumber`/`PageSize`, `Offset`/`Limit` ou padrão já existente no contrato.
3. Valide valores mínimos e limite máximo de página.
4. Aplique filtros antes da paginação.
5. Aplique ordenação determinística antes de `Skip`/`Take`.
6. Projete apenas os campos necessários quando possível.
7. Aplique `Skip` e `Take` antes de `ToListAsync`/materialização.
8. Use `AsNoTracking` em consultas somente leitura quando compatível com o padrão do projeto.
9. Propague `CancellationToken` nas operações assíncronas quando disponível.
10. Execute `CountAsync` somente quando o contrato realmente exigir total de registros; avalie seu custo em consultas complexas.
11. Retorne metadados coerentes com o contrato atual.

## Regras

- nunca use `ToList()`/`ToListAsync()` seguido de paginação em memória para conjuntos grandes;
- não use `AsEnumerable()` antes de filtros/paginação sem necessidade comprovada;
- ordenação deve ser estável, idealmente com critério de desempate único;
- filtros precisam ser traduzidos para SQL quando tecnicamente possível;
- evite funções que forcem avaliação client-side ou impeçam tradução pelo EF Core;
- avalie custo de `COUNT(*)` antes de assumir que ele é gratuito;
- não altere o formato público de paginação sem considerar consumidores existentes.

## Checklist

- [ ] A consulta permanece `IQueryable` até o recorte?
- [ ] A paginação acontece no banco?
- [ ] Existe ordenação determinística?
- [ ] Filtros são aplicados antes do recorte?
- [ ] `Skip`/`Take` ocorre antes da materialização?
- [ ] O tamanho máximo foi considerado?
- [ ] `CountAsync` é realmente necessário?
- [ ] O contrato de resposta é consistente?
