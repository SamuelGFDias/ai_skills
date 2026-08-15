---
name: backend-pagination
description: Use em endpoints e consultas que retornam coleções potencialmente grandes, implementando paginação sob demanda com suporte do banco e da camada de persistência.
---

# Backend Pagination

## Quando usar

Use quando:

- um endpoint retorna coleção sem limite;
- busca pode crescer significativamente;
- existe `Pageable`, `Page`, `Slice` ou equivalente;
- filtros e ordenação precisam ser combinados com paginação;
- o sistema está carregando todos os registros para paginar em memória.

## Diretriz

A paginação deve ocorrer **sob demanda**, usando recursos do banco de dados e da camada de persistência, em vez de carregar toda a coleção em memória.

## Procedimento

1. Identifique a consulta e a cardinalidade esperada.
2. Defina parâmetros de página/tamanho conforme padrão do projeto.
3. Aplique filtros antes da paginação.
4. Aplique ordenação determinística.
5. Execute paginação na query/banco.
6. Evite mapear todos os registros antes de `offset/limit`.
7. Defina limite máximo de página quando o projeto exigir proteção de carga.
8. Retorne metadados coerentes com o contrato atual.

## Regras

- nunca use `findAll()` seguido de paginação em memória para dados grandes;
- ordenação deve ser estável, especialmente entre páginas;
- filtros precisam ser aplicados no banco quando tecnicamente possível;
- avalie custo de `COUNT(*)` em consultas complexas antes de assumir que ele é gratuito;
- não altere o formato de paginação pública sem considerar consumidores existentes.

## Checklist

- [ ] A consulta pagina no banco?
- [ ] Existe ordenação determinística?
- [ ] Filtros são aplicados antes do recorte?
- [ ] O tamanho máximo foi considerado?
- [ ] Não há materialização prematura da coleção?
- [ ] O contrato de resposta é consistente?
