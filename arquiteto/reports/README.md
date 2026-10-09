# Relatórios de falha de subagentes

Registro versionado das falhas de subagentes do arquiteto (regra 18 em `references/regras.md`).
Serve à **revisão mensal**: com base na incidência de erros por papel/modelo/esforço, decidir se vale
subir (ou descer) o nível do modelo ou do esforço em `cli/<cli>/models.json` ou `models.local.json`.

## Quando registrar

Toda vez que um subagente falhar de forma que o arquiteto constate: resultado errado, critério de pronto
não atingido, achado de revisor `alto`/`medio` sobre o trabalho dele, BLOQUEIO por incapacidade (não por
falta de contexto no prompt), ou re-delegação. Falha causada por prompt mal escrito do próprio arquiteto
também entra, marcada como tal na análise: ela não justifica subir modelo.

## Onde e como

Um arquivo por falha: `reports/falhas/AAAA-MM-DD-<papel>-<slug>.md`. Commitar junto com o trabalho da
sessão. Nunca colocar segredo, token ou dado sensível em solicitação/resposta: mascarar.

## Modelo do arquivo

```markdown
# <papel> — <resumo da falha em uma linha>

- **Data:** AAAA-MM-DD
- **Sessão:** <id da sessão ou caminho do transcript>
- **Papel / modelo / esforço:** <ex.: executor-complexo / claude-sonnet-5-5 / high>
- **Causa provável:** modelo | esforço | prompt do arquiteto | contexto faltando | ambiente

## Solicitação
<prompt delegado, literal ou resumido com ponteiros>

## Resposta
<retorno do subagente, literal ou trecho relevante>

## Análise do erro
<o que deu errado, evidência arquivo:linha, e se um modelo/esforço maior teria evitado>

## Desfecho
<re-delegado a quem, corrigido pelo arquiteto, ou limite documentado>
```

## Revisão mensal

1. Contar os arquivos do mês por papel e por **causa provável**: `ls reports/falhas/AAAA-MM-*`.
2. Considerar só as causas `modelo` e `esforço`; as demais são problema de prompt/contexto/ambiente.
3. Papel com incidência recorrente de `modelo`/`esforço` → subir um nível (esforço primeiro, depois modelo).
4. Papel sem falhas relevantes por um mês em nível alto → candidato a descer um nível para economizar.
5. Registrar a decisão no topo de `reports/decisoes.md` (data, papel, de → para, base da decisão).
