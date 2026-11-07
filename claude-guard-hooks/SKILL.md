---
name: claude-guard-hooks
description: Hooks PreToolUse do Claude Code que tornam determinísticas as regras que não podem falhar — bloqueiam rodapé de atribuição de IA em commit/PR/MR, --no-verify, `op read` ou echo que imprimiria segredo, e segredo escrito em arquivo pelas ferramentas Write/Edit; pedem confirmação antes de comando destrutivo (rm -rf amplo, push --force, reset --hard, clean -f, DROP/TRUNCATE, DELETE sem WHERE). Use ao instalar, ajustar, desligar ou depurar esses hooks, ou quando um comando for bloqueado por eles.
---

# Skill: claude-guard-hooks

**Tipo:** internal

## Quando executar

- Ao instalar os hooks numa máquina nova, ou depois de mudar o `scripts/guard.py`.
- Quando um comando for bloqueado ou pedir confirmação por causa deles, para entender por quê e decidir se a regra deve mudar.
- Ao acrescentar uma regra que hoje está como instrução no CLAUDE.md e continua sendo ignorada.

## Por que hook, e não instrução

O CLAUDE.md é contexto: o modelo lê e pode errar. Hook do tipo `command` é executado pelo harness toda vez. A recomendação da Anthropic é mover para hook a regra que precisa valer sempre, e manter o conjunto pequeno, sem hook para preferência (fontes em `docs/fundamentos.md`).

## O que cada regra faz

| id | ferramenta | decisão | gatilho |
|---|---|---|---|
| `ai-attribution` | Bash | bloqueia | `git commit` (inclusive com `-C`/`-c`), `gh pr create/edit` ou `glab mr create/update` com `Co-Authored-By` de Claude/Anthropic ou "Generated with Claude Code" no próprio segmento do comando, inclusive no arquivo de `-F`/`--body-file` |
| `no-verify` | Bash | bloqueia | `git ... --no-verify` fora de aspas, e `git commit -n` (no `push`, `-n` é dry-run e passa) |
| `secret-print` | Bash | bloqueia | `op read` fora de `$(...)`, ou `echo "$(op read ...)"`; `echo`/`printf`/`printenv`/`cat` de variável com nome de segredo (`*_TOKEN`, `*_SECRET`, `*_PASSWORD`, `*_API_KEY`, `BAMBU_ACCESS_CODE`). Passa quando a saída vai por pipe a um consumidor que não imprime (`\| docker login --password-stdin`) |
| `destructive` | Bash | pede confirmação | `rm -rf` na raiz, home, `.`, `..` ou `*`; `git push --force`/`-f` (não `--force-with-lease`); `git reset --hard`; `git clean -f`; `git checkout/restore` do diretório inteiro; `git branch -D`; push por `+refspec`; `DROP`/`TRUNCATE`/`DELETE` sem `WHERE` só em cliente de banco (`psql`, `mysql`, `sqlcmd`...); `mkfs`/`dd of=/dev/`. Aceita opções globais do git (`git -C dir`) |
| `secret-write` | Write, Edit, MultiEdit | bloqueia | chave privada, token do GitHub/GitLab/Slack, chave da AWS ou de API no conteúdo. Ignora `.env.example`, `.env.sample`, `tests/`, `fixtures/` e `.md` |

"Bloqueia" devolve o motivo ao Claude, que pode corrigir o comando. "Pede confirmação" mostra o pedido de permissão normal ao usuário.

## Instalar

```bash
cd ~/dev/projects/ai_skills                       # ou onde o repo estiver
bin/sync-skills.sh claude                         # cria o symlink da skill para o Claude Code
python3 -I claude-guard-hooks/scripts/test_guard.py
python3 -I claude-guard-hooks/scripts/install.py --dry-run
python3 -I claude-guard-hooks/scripts/install.py  # grava, com backup do settings.json
```

O hook só passa a valer numa sessão nova do Claude Code. Remover: `install.py --uninstall`.

## Desligar uma regra

- Na sessão: `CLAUDE_GUARD_DISABLE=destructive,no-verify claude` (ids da tabela, separados por vírgula).
- De vez: remova o bloco da regra em `scripts/guard.py` e ajuste o teste.

## Limites conhecidos

- **Falha aberto:** JSON inválido ou erro interno do script não bloqueiam nada. É guarda contra deslize, não fronteira de segurança contra um agente hostil: um comando ofuscado passa.
- **Escopo do `secret-write`:** cobre as ferramentas Write e Edit. Segredo gravado por redirecionamento no Bash (`printf ... > .env`, `cat > arquivo <<EOF`) não é detectado.
- **Por padrão de texto:** a regra `destructive` olha o texto do comando. `rm -rf "$DIR"` com variável vazia não é detectado; `DELETE` com `WHERE` falso também não.
- **Custo:** um processo Python por chamada de Bash, Write ou Edit (algumas dezenas de milissegundos).

## Revisão de segurança

Revisado em 2026-11-07 com a skill `security-audit` no modo orientação, por um revisor de contexto limpo: 8 achados confirmados e 4 falsos positivos, todos corrigidos e cobertos em `scripts/test_guard.py` (casos C1–C8 e FP1–FP4).

## Mudar uma regra

1. Edite `scripts/guard.py`.
2. Acrescente casos em `scripts/test_guard.py`: um que deve casar e um parecido que não deve.
3. `python3 -I claude-guard-hooks/scripts/test_guard.py` precisa terminar com todos os casos passando.
4. Como o hook aponta para o symlink, a mudança vale na próxima chamada, sem reinstalar.
