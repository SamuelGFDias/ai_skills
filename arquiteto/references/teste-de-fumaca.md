# Teste de fumaça do arquiteto (sessão nova)

Valida, numa sessão nova do Claude Code com os papéis instalados:
- modelo efetivo por papel;
- fluxo implementar + revisar;
- contrato com mensagens entre pares;
- revisor reprovando defeito plantado;
- prompts enxutos.

Rodar sempre que mudar `roles/`, `cli/*/models.json` ou o fluxo em `SKILL.md`.

## Pré-requisitos (no shell, fora do Claude)

```bash
cd ~/.config/ai/skills && git pull            # ou merge da branch com as mudanças
arquiteto/bin/sync-agents.sh claude           # cria os symlinks dos papéis novos em ~/.claude/agents
ls ~/.claude/agents | grep -c md              # esperado: 9
env | grep CLAUDE_CODE_ || true               # nenhuma CLAUDE_CODE_EFFORT_LEVEL/SUBAGENT_MODEL definida
```

Abrir uma sessão **nova** (`claude`) num diretório vazio e rodar `/model sonnet`, porque o arquiteto padrão é sonnet (regra 16).

## Prompt a colar

```text
/arquiteto Teste de fumaça do próprio arquiteto. Siga a skill à risca e, no fim, entregue o relatório pedido no item 6.

1. Configuração: confira se os 9 papéis tipados (executor-mecanico/padrao/complexo/critico, investigador-padrao/critico, speckit-master, revisor-padrao/critico) estão disponíveis como subagent_type. Se faltar algum, pare e me diga (não use fallback).

2. Setup (delegado a executor-mecanico): criar um repo git descartável em $CLAUDE_JOB_DIR/tmp/fumaca (ou /tmp/fumaca-$$ se a variável não existir) com commit inicial contendo:
   - precos.py vazio (área A) e carrinho.py vazio (área B);
   - README.md com "# fumaca".

3. Implementação paralela com contrato (regra 14). Tarefa:
   - "precos.py expõe preco_final(valor_centavos: int, cupom: str) -> int: cupom 'DEZ' dá 10% de desconto, 'VIP' dá 25%, qualquer outro cupom = sem desconto; nunca negativo."
   - "carrinho.py expõe total(itens: list[tuple[int, str]]) -> int somando preco_final de cada item."
   - Dois executor-padrao em paralelo, um por área, com contrato gravado antes e endereços repassados depois do disparo.
   - No meio do trabalho, o dono de precos.py deve renomear a função para valor_com_cupom (decisão sua, como arquiteto: inclua no prompt dele) e avisar o par via CONTRATO com cópia para você.
   - Verificação estreita de cada um: python3 -c com asserts da própria área.

4. Revisão (regra 13): revisor-padrao de contexto limpo sobre o diff integrado. Depois, num segundo commit, peça a um executor-mecanico que plante o defeito "cupom desconhecido aplica 25%" em precos.py e altere README.md (fora do touch-list). Rode um revisor-padrao novo só sobre esse commit. Esperado: REPROVADO com os dois achados.

5. Gate (regra 10): você mesmo roda os asserts das duas áreas juntas.

6. Relatório final, em tabela, com evidência conferida por você (não pelo relato dos subagentes):
   a) Modelo efetivo de cada subagente disparado. Extraia do output_file de cada um com: grep -o '"model":"[^"]*"' <output_file> | sort | uniq -c. Esperado: mecanico = haiku, padrao/revisor-padrao = sonnet, nenhum herdando o modelo da sessão.
   b) Mensagens CONTRATO/PRONTO recebidas por você (to: main), e se o par B ajustou o import.
   c) Veredito e achados de cada revisão, com ref:arquivo:linha conferido via Read.
   d) Tamanho, em linhas, de cada prompt que você enviou aos executores tipados, e se eles repetiram o contrato de retorno por extenso (regra 17: não deveriam).
   e) Arquivos tocados fora do touch-list (esperado: só o README do defeito plantado).
   f) O que falhou ou divergiu do esperado.
```

## Critério de aprovação

- Os 9 papéis disponíveis.
- Modelo por papel conforme `cli/claude/models.json`.
- O par B recebeu o `CONTRATO` e ajustou.
- Revisão 1 `APROVADO` ou com ressalvas de severidade `baixo`.
- Revisão 2 `REPROVADO` com o fail-open e o README.
- O gate passou.
- Prompts tipados sem o contrato de retorno por extenso.

Rodar `/tasks` durante o passo 3 também mostra o esforço de cada subagente. O esforço não aparece no transcript, e o haiku não tem esforço.

## Variante Antigravity (`agy`)

Não usa subagentes do Claude: o orquestrador é o próprio `agy`. Detalhes e armadilhas em `antigravity.md`.

```bash
bin/build-agents.py antigravity && bin/sync-agents.sh antigravity
agy agent                              # esperado: os 9 papéis listados
cd ~/.config/ai/skills/arquiteto       # leitura em -p só funciona dentro do workspace
agy --output-format stream-json -p "Use invoke_subagent, em paralelo: investigador-padrao (conte os arquivos de roles/) e revisor-padrao (confira dist/antigravity). Aguarde os retornos."
```

Aprovação: `step_type=subagent` com os dois `type_name`, e o resultado de cada um no `transcript.jsonl` do `log_uri` (como `send_message`). Reprovação típica: `unknown agent` (model fora do tier), `failed to construct executor` (tool fora do registry) ou `user denied permission` (shell em `-p`).
