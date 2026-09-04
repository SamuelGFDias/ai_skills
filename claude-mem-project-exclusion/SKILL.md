---
name: claude-mem-project-exclusion
description: Exclui uma pasta (ex. home, ~/dev) do rastreamento de memória do plugin claude-mem e/ou apaga memórias já gravadas para um projeto específico do banco SQLite dele. Use quando o usuário pedir para parar de gravar/mostrar memórias em uma pasta específica, quando o contexto injetado no SessionStart não tiver relação com a pasta atual, ou quando pedir para "limpar"/"apagar" as memórias de um projeto do claude-mem.
---

# Skill: claude-mem-project-exclusion

**Tipo:** internal

## Quando executar

- O contexto injetado pelo claude-mem no início da sessão (bloco `SessionStart hook additional
  context`) não tem relação com o projeto atual — geralmente porque a sessão foi aberta na home
  (`~`) ou numa pasta "guarda-chuva" (ex. `~/dev`) em vez de dentro do projeto real.
- Pedido para excluir uma pasta específica do claude-mem.
- Pedido para apagar/limpar memórias já gravadas de um projeto específico.

## Como o claude-mem nomeia um projeto

O nome do "projeto" (coluna `project` nas tabelas) é derivado do `cwd` da sessão, **não** do
caminho completo:

- Se o `cwd` (ou algum ancestral) é um repositório git: `basename($(git rev-parse
  --show-toplevel))`.
- Senão: `basename(cwd)`.

Por isso abrir uma sessão direto em `/home/samueldias` vira o projeto `samueldias`, e direto em
`/home/samueldias/dev` vira o projeto `dev` — nomes curtos que podem colidir por coincidência com
outro projeto. **Sempre conferir antes de agir:**

```bash
sqlite3 ~/.claude-mem/claude-mem.db "SELECT project, COUNT(*) FROM sdk_sessions GROUP BY project ORDER BY 2 DESC;"
```

## Parte 1 — Excluir a pasta para o futuro (não gravar nem mostrar mais)

Config em `~/.claude-mem/settings.json`, chave `CLAUDE_MEM_EXCLUDED_PROJECTS` (string, padrões
separados por vírgula). Cada padrão vira um regex **âncorado** (`^padrão$`, via `hJ()` no código
minificado) comparado contra o `cwd` inteiro (com `~` expandido para `$HOME`) **ou** contra o
basename — não é prefixo nem substring. Ou seja:

- `~` exclui só a sessão aberta exatamente na home — não afeta `~/qualquer-coisa`.
- `~/dev` exclui só a sessão aberta exatamente em `~/dev` — não afeta `~/dev/algum-projeto`.
- Use `*`/`**`/`?` (glob) só se quiser abranger mais do que o caminho exato.

Exemplo — excluir home e `~/dev` como raízes, mantendo subpastas normais:

```json
"CLAUDE_MEM_EXCLUDED_PROJECTS": "~,~/dev"
```

Essa checagem (função `Mi()` no worker) cobre **tanto** a gravação de novas observações
(`PostToolUse`/`Stop`/`PreToolUse` hooks) **quanto** a injeção de contexto no `SessionStart` — uma
pasta excluída não grava e não aparece mais no início da sessão.

### Aplicar a mudança (o worker cacheia o settings.json em memória)

O daemon persistente (`~/.claude-mem/worker.pid`, campo `pid`) lê `settings.json` só uma vez e
guarda em cache (`po()`/`Hb` no código). Hooks avulsos (`observation`, etc.) recarregam o arquivo a
cada chamada e já respeitam a mudança na hora — mas o hook de `SessionStart` (o que injeta o
contexto) passa pelo daemon cacheado, então é preciso reiniciá-lo para a exclusão valer já na
próxima sessão:

```bash
PID=$(node -pe "JSON.parse(require('fs').readFileSync(process.env.HOME+'/.claude-mem/worker.pid')).pid")
kill "$PID"; sleep 2
```

O worker sobe sozinho no próximo hook (SessionStart da próxima sessão, ou qualquer PostToolUse
disparado nesta). Para forçar a subida imediata sem esperar um hook:

```bash
V=$(ls -d ~/.claude/plugins/cache/thedotmack/claude-mem/*/ | sort -V | tail -1)
node "${V}scripts/bun-runner.js" "${V}scripts/worker-service.cjs" start
```

## Parte 2 — Apagar memórias já gravadas de um projeto

Schema relevante em `~/.claude-mem/claude-mem.db`:

- `sdk_sessions` tem a coluna `project` direto.
- `observations` e `session_summaries` referenciam `sdk_sessions.memory_session_id` com
  `ON DELETE CASCADE`.
- `user_prompts` referencia `sdk_sessions.id` (coluna `session_db_id`) com `ON DELETE CASCADE`.

Ou seja, `DELETE FROM sdk_sessions WHERE project IN (...)` com `PRAGMA foreign_keys = ON` já limpa
tudo em cascata.

**Armadilha:** o `sqlite3` do sistema costuma faltar o módulo FTS5, e `observations` tem triggers
`AFTER INSERT/DELETE` que sincronizam a tabela virtual `observations_fts` (FTS5). Rodar o `DELETE`
pelo `sqlite3` do SO falha com `Error: in prepare, no such module: fts5`. Use o `bun` (mesmo
runtime do plugin, já tem FTS5 embutido) em vez do `sqlite3` do SO.

Script pronto — `scripts/clear-project.js` (dry-run por padrão, `--yes` para aplicar; faz backup
automático em `~/.claude-mem/backups/` antes de apagar):

```bash
bun ~/.config/ai/skills/claude-mem-project-exclusion/scripts/clear-project.js samueldias dev        # dry-run
bun ~/.config/ai/skills/claude-mem-project-exclusion/scripts/clear-project.js --yes samueldias dev  # apaga
```

### Notas sobre a verificação pós-delete

- `result.changes` de um `DELETE` em cascata com triggers FTS5 fica **muito** maior que o número de
  linhas lógicas apagadas (ex.: 6 sessões geraram `changes = 1148`) — é o SQLite contando também as
  linhas internas das shadow tables do FTS5, não uma indicação de que apagou mais do que devia.
  Confie em `COUNT(*)` por tabela, não em `changes()`.
- Pode já existir um número de `user_prompts` órfãos (`session_db_id` que não existe mais em
  `sdk_sessions`) **antes** da sua operação — resquício de migrações antigas (ver backups tipo
  `claude-mem-pre-project-name-fix-*.db` em `~/.claude-mem/backups/`). Compare a contagem de órfãos
  antes/depois (o script já faz isso e avisa) antes de assumir que a exclusão introduziu o problema.
- Não existe endpoint (`/api/projects` só tem `GET`) nem tool MCP para apagar um projeto — a via
  suportada é mesmo SQL direto no arquivo.

### Índice semântico (Chroma) — não mexer

`~/.claude-mem/chroma/chroma.sqlite3` guarda embeddings num schema próprio (shadow tables tipo
HNSW) que não é seguro editar via SQL cru. Não há necessidade: como a fonte de verdade
(`claude-mem.db`) já não tem mais os IDs apagados, uma busca semântica que ainda tenha um vetor
"fantasma" desses projetos simplesmente não vai conseguir hidratar conteúdo nenhum
(`get_observations` retorna vazio para IDs inexistentes). Efeito residual inofensivo.
