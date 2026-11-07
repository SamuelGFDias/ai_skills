# Fundamentos: o que a Anthropic recomenda sobre subagentes

Base das regras 1 e 19. Pesquisado em 2026-11-07. Reler quando for mudar o equilíbrio entre executar e delegar, ou quando uma fonte nova contradisser este resumo.

## Conclusão aplicada ao arquiteto

Nenhuma das fontes recomenda delegar **toda** a execução. Elas recomendam delegar quando a delegação paga e manter o resto na sessão principal, porque o contexto já está carregado ali. Delegar a mesma tarefa não deixa a resposta mais inteligente. O que melhora a qualidade é a revisão por outro agente, com contexto limpo.

Por isso o arquiteto passou de "nunca executa" para **híbrido**: executa direto o que é pequeno, sequencial ou dependente do contexto já carregado, e delega nos quatro casos da regra 1. O modo antigo continua disponível como `--delegar-tudo`.

## O que cada fonte sustenta

| Tema | O que dizem | Fonte |
|---|---|---|
| Custo | Agentes gastam cerca de 4× os tokens de um chat, e sistemas multiagente cerca de 15×. O uso de tokens explica a maior parte da variação de desempenho. | [multi-agent-research-system] |
| Quando delegar | Pergunta-guia: "vou precisar desta saída de novo, ou só da conclusão?". Delegar trabalho com muita saída intermediária descartável. | [session-management] |
| Limiar | Explorar dez ou mais arquivos, ou três ou mais peças de trabalho independentes. | [subagents-in-claude-code] |
| Quando não delegar | Correção rápida ou pergunta focada: o custo da delegação supera o benefício. Também não delegar trabalho sequencial em que o passo 2 precisa da saída inteira do passo 1, nem edições no mesmo arquivo. | [subagents-in-claude-code] |
| Latência | O subagente novo precisa juntar de novo o contexto que a conversa já tinha, e pode acabar mais lento. | [best-practices] |
| Qualidade | Delegar dá paralelismo ou um par de olhos novo, não uma resposta mais inteligente. | [best-practices] |
| Revisor | O revisor que não viu o código ser escrito dá um retorno mais objetivo. Mas um revisor mandado achar problemas sempre acha algum, então o prompt pede para pular estilo. | [best-practices], [subagents-in-claude-code] |
| Código e paralelismo | Tarefas de código têm menos partes de fato paralelizáveis que pesquisa, e agentes ainda coordenam mal entre si. | [multi-agent-research-system] |
| Prompt de delegação | Cada subagente precisa de objetivo, formato de saída, orientação de ferramentas e fontes, e limites claros. Sem isso, duplica trabalho ou deixa lacunas. | [multi-agent-research-system] |
| Retorno | Pedir resumos curtos de volta. | [best-practices] |
| Modelo barato | Haiku serve para subagentes de trabalho simples (achar quem importa um módulo, checar links). Nenhuma fonte mede a perda de qualidade ao rebaixar. | [best-practices], [sub-agents] |
| Menos subagentes | Em vários deployments, um agente único com skills superou o desenho com subagentes em qualidade. Cada handoff devolve um resumo com perda. Manter um subagente só se a versão sem ele piorar de forma medida. | [fold-subagents] |
| Especialistas demais | Evitar agentes especialistas demais. Preferir poucos agentes bem delimitados, e não um organograma. | [subagents-in-claude-code], [fold-subagents] |
| Escala de esforço | Um erro inicial foi disparar dezenas de subagentes para perguntas simples. Fatos simples pedem um agente só. | [multi-agent-research-system] |

## Fontes

- [multi-agent-research-system]: https://www.anthropic.com/engineering/multi-agent-research-system
- [best-practices]: https://code.claude.com/docs/en/best-practices
- [sub-agents]: https://code.claude.com/docs/en/sub-agents
- [subagents-in-claude-code]: https://claude.com/resources/articles/subagents-in-claude-code
- [session-management]: https://claude.com/resources/articles/using-claude-code-session-management-and-1m-context
- [fold-subagents]: https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop

## O que as fontes não cobrem

- Nenhuma fonte trata do padrão exato do arquiteto: um orquestrador que escolhe o modelo mais barato por subtarefa num fluxo de código.
- Não há números de custo monetário nem de latência para comparar "executar direto" com "delegar a haiku". A decisão de rebaixar modelo continua dependendo dos relatórios de `reports/falhas/` (regra 18). A recomendação da Anthropic é medir, mudar uma coisa por vez e manter o que se sustentar.
