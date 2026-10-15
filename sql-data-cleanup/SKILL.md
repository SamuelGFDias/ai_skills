---
name: sql-data-cleanup
description: Framework para scripts SQL de dedupe/limpeza de dados que decidem qual registro duplicado manter por evidência de uso (vínculo/FK > autoria na trilha de auditoria > idade), mantendo casos ambíguos para conferência manual e removendo só dentro de transação revisável. Use ao escrever ou revisar script SQL de remoção de duplicados, limpeza de cadastros ou qualquer DELETE em massa decidido por regra de "quem fica".
---

# Skill: sql-data-cleanup

**Tipo:** internal

Em dedupe/limpeza, a regra de "quem fica" deve vir de evidência de uso real, em precedência documentada. A automação age só nos casos inequívocos; o resto vai para revisão humana.

## Precedência de evidência (da mais forte à mais fraca)

1. **Vínculo/referência (FK):** o registro referenciado por tabelas filhas (vínculos, relacionamentos) é o que está em uso. Contar FKs de todas as tabelas dependentes.
2. **Autoria/atividade na trilha de auditoria:** quem criou/alterou algo. Serve para desempatar quando nenhum candidato tem vínculo (ex.: perfis administrativos, que por design não mantêm vínculos).
3. **Idade:** manter o mais antigo, **somente como último recurso** documentado, nunca como padrão silencioso.

## Autoria mora na auditoria, não na entidade

- Não assumir coluna "criado por" na tabela de domínio; verificar o esquema. Entidades de auditoria costumam ter só `CreatedAt/UpdatedAt/DeletedAt/IsDeleted`.
- A autoria vive nas tabelas de log de auditoria, cujo usuário costuma ser o **id externo** do provedor de identidade (claim do token), e não o `Id` da tabela de usuários.
- Fazer o join pelo **id externo normalizado** (sem hífen, caixa única): `REPLACE(LOWER(x), '-', '')` dos dois lados.
- **Usuários sem id externo** (seed/import) não aparecem na auditoria: ficam **sem sinal** de atividade. Tratar como "evidência ausente", não como "inativo".

## Regra de decisão por grupo de duplicados

Para cada grupo (mesma chave de negócio):

| Situação da evidência | Ação |
|---|---|
| Exatamente 1 candidato com a evidência mais forte | Mantém esse; remove os demais |
| 0 candidatos com evidência, ou >1 com o mesmo peso | **NUNCA remove automaticamente**; vai para a consulta de conferência |
| Nenhuma evidência de uso em nenhum candidato e política "mais antigo" adotada explicitamente | Mantém o mais antigo; registrar que foi desempate por idade |

Por quê: remover por palpite apaga dado em uso; um grupo não decidido custa uma revisão, um DELETE errado custa um restore.

## Estrutura do script

1. **Consulta de conferência (SELECT)** antes de qualquer DELETE: por grupo, candidatos, evidências encontradas, decisão proposta e grupos ambíguos. Revisar a saída.
2. **Transação aberta** (`BEGIN`/`BEGIN TRANSACTION`), DELETE só dos casos inequívocos, `SELECT` de verificação do estado resultante.
3. **`COMMIT` e `ROLLBACK` manuais**: o script termina sem confirmar; quem executa decide. Nunca `COMMIT` automático no fim.
4. Fazer backup/snapshot das linhas a remover (tabela temporária ou export) quando o ambiente for produção.

Esqueleto:

```sql
-- 1) Conferência (somente leitura)
SELECT g.chave, c.id, c.criado_em, c.fks_vinculo, c.atividade_auditoria, c.decisao
FROM candidatos c JOIN grupos g ON g.chave = c.chave
ORDER BY g.chave, c.criado_em;

-- 2) Remoção (transação aberta; finalizar manualmente)
BEGIN;
DELETE FROM tabela WHERE id IN (SELECT id FROM candidatos WHERE decisao = 'REMOVER');
-- conferir contagens aqui
-- COMMIT;   ou   ROLLBACK;
```

## Knobs a documentar no cabeçalho do script

- **Tipo de atividade na auditoria:** apenas criação (`Operacao = 'Added'`) ou qualquer atividade. Criação é mais restritiva e mais fiel a "criou algo"; qualquer atividade conta também logins/edições.
- **Soft-deleted:** incluir ou não registros com `IsDeleted = 1` nos candidatos e nas contagens de vínculo.
- **Política de último recurso:** se o desempate por idade está habilitado ou se grupos sem evidência vão sempre para conferência.

## Checklist

- [ ] Precedência vínculo > autoria > idade escrita no cabeçalho do script?
- [ ] Joins de auditoria usam id externo normalizado nos dois lados?
- [ ] Usuários sem id externo tratados como "sem sinal", sem remoção automática por isso?
- [ ] Grupos com 0 ou >1 candidatos de mesmo peso excluídos do DELETE e listados na conferência?
- [ ] Consulta de conferência roda antes do DELETE e foi revisada?
- [ ] Transação aberta, sem COMMIT automático, com contagem esperada de linhas afetadas?
- [ ] Knobs (tipo de atividade, soft-deleted) documentados e escolhidos conscientemente?
