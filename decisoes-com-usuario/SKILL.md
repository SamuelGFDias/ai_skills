---
name: decisoes-com-usuario
description: Leva as decisões que são do usuário (escopo, escolha entre abordagens, aprovação de escrita em ambiente compartilhado) para uma rodada estruturada de perguntas, usando a skill grilling com a ferramenta de pergunta do agente (AskUserQuestion no Claude Code, equivalente em outros agentes). Use quando houver uma decisão do usuário a tomar antes de agir, quando o usuário pedir para "grill" ou para perguntar antes de executar, ou quando a tarefa depender de uma escolha que você não consegue inferir do pedido.
---

# Skill: decisoes-com-usuario

**Tipo:** internal — aplica a regra do CLAUDE.md global ("Decisões do usuário": perguntar via `AskUserQuestion`, recomendação primeiro, não perguntar o que tem default ou o que se verifica no código).

## Quando executar

Use esta skill quando **a decisão é do usuário**, por exemplo:
- **Escopo:** o que entra e o que fica de fora.
- **Escolha entre abordagens** com trade-off real (arquitetura, ferramenta, formato).
- **Aprovação de escrita em ambiente compartilhado** (push, deploy, envio de mensagem, alteração de recurso que outras pessoas usam).
- **Ação irreversível ou externa**, mesmo que a escolha pareça óbvia.

**Não** use para:
- Algo com default convencional (decida, declare a escolha na resposta final).
- Algo que você consegue verificar no código, no ambiente ou na documentação (busque o fato antes; ver passo 2).
- Edição local reversível dentro do pedido já feito (faça e liste as escolhas tomadas).

## Como executar

1. **Classifique cada dúvida.** Para cada uma, pergunte: é fato que dá para verificar, decisão com default, ou decisão do usuário? Só a terceira vai para perguntas.
2. **Verifique os fatos antes de perguntar.** Se a resposta depende de arquivos, configuração, estado do sistema ou documentação, busque-a. Não transfira para o usuário o que você pode descobrir.
3. **Se houver ramificações, siga a skill `grilling`.** Carregue-a com a ferramenta de skills (`grilling`). Ela organiza as decisões em árvore e as pergunta em rodadas de frontier. Se a decisão for única e sem ramificações, faça uma rodada direta, sem `grilling`.
4. **Pergunte pelo canal do agente:**
   - **Claude Code:** carregue `AskUserQuestion` com `ToolSearch` (`select:AskUserQuestion`) antes do primeiro uso. Máximo 4 perguntas por chamada. Cada pergunta tem `header` curto, `question` terminando em `?` e de 2 a 4 opções mutuamente exclusivas. A **opção recomendada vai primeiro**, com "(Recommended)" no rótulo. Não adicione opção "Other", a ferramenta já oferece.
   - **Outros agentes (ex.: Kilo):** use a ferramenta de pergunta estruturada que o agente expõe. Confirme o nome dela na própria ferramenta disponível, sem presumir. Se não houver nenhuma, faça perguntas numeradas curtas, com a recomendação como opção 1 marcada "(Recomendado)", e **pare e aguarde a resposta**.
5. **Espere as respostas.** Não avance na decisão enquanto o usuário não responder. Depois de cada rodada, recalcule quais perguntas ficaram desbloqueadas.
6. **Confirme o entendimento compartilhado** antes de agir: liste as decisões fechadas em tópicos curtos e pergunte se está correto, quando a ação for irreversível ou compartilhada.
7. **Declare o que foi decidido** na resposta final: decisões do usuário (com a resposta dada) e escolhas defaults que você tomou sozinho.

## Regras

- Nunca decida pelo usuário uma decisão de escopo, de abordagem ou de escrita compartilhada.
- Recomendação sempre primeiro, com "(Recommended)", e fácil de aceitar.
- Uma rodada não invade a próxima: pergunte só o que está no frontier atual.
- Se o usuário responder "decide você", aplique o default convencional, declare a escolha e siga.
- Não use perguntas em texto corrido quando a ferramenta estruturada estiver disponível.
