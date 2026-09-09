# AGENTS.md — AI Skills (Claude Code / Kilo)

Este repositório é a fonte de **skills compartilhadas** dos agentes de IA (Claude Code e Kilo). Ao
trabalhar aqui, siga estas regras para manter o ambiente sem ruído e sem débitos de limpeza.

## Contexto de integração

- **Fonte real:** `~/.config/ai/skills` (este repo, git versionado).
- **Claude Code:** lê de **cópias** em `~/.claude/skills/<nome>` (não symlink/junction — cópia
  fiel do diretório da skill). Toda skill nova ou alterada exige rodar o sync (ver
  "Sincronização" abaixo) para recriar a cópia; sem isso o Claude Code continua vendo a versão
  antiga. Os subagentes do `arquiteto` são instalados por outro script — mesma seção.
- **Kilo:** lê via `skills.paths` em `~/.config/kilo/kilo.jsonc` → `~/.config/ai/skills`
  (pega automaticamente todo diretório com `SKILL.md`, direto da fonte — sem cópia). O sync com
  alvo `kilo` só garante que esse caminho está configurado; é idempotente e normalmente roda uma
  vez só.
- **Remotes (ambos privados):** GitHub `git@github.com:SamuelGFDias/ai_skills.git` e GitLab SES
  `git@gitlab-prod.saude.rj.gov.br:ses-rj/desenvolvimento/ai/skills.git`. `git push` envia aos dois.

## Sincronização

Duas coisas independentes precisam ser sincronizadas — alterar uma não sincroniza a outra:

| O quê | Fonte | Destino | Script |
|---|---|---|---|
| **Skills** (`<nome>/SKILL.md`) | este repo | `~/.claude/skills/<nome>` (cópia) | `bin/sync-skills.sh` / `bin/sync-skills.ps1` |
| **Subagentes do `arquiteto`** | `arquiteto/roles/` + `arquiteto/cli/<cli>/models.json` | `~/.claude/agents/`, `~/.config/kilo/agent/`, `~/.codex/agents/` | `arquiteto/bin/build-agents.py` → `arquiteto/bin/sync-agents.sh` |

### Sequência completa

bash / WSL / **Git Bash (MINGW64)**:

```bash
cd ~/.config/ai/skills
python3 arquiteto/bin/build-agents.py --check   # exit 0 = dist/ em dia; exit 2 = rode sem --check e commite dist/
bin/sync-skills.sh claude                       # ou 'all' para claude + kilo
arquiteto/bin/sync-agents.sh                    # o caminho é arquiteto/bin/, NÃO bin/
```

PowerShell:

```powershell
cd $HOME\.config\ai\skills
python3 arquiteto\bin\build-agents.py --check
bin\sync-skills.ps1 -Cli claude
bash arquiteto/bin/sync-agents.sh              # barras normais aqui: o argumento é lido pelo bash
```

### Quando rodar o quê

- Mexeu só num `SKILL.md` (ou criou skill nova): basta `sync-skills`.
- Mexeu em `arquiteto/roles/` ou em `arquiteto/cli/<cli>/models.json`: rode `build-agents.py <cli>`
  para os três CLIs, **commite o `dist/` gerado**, e então `sync-agents.sh`.
- Tipo de subagente novo ou alterado **só aparece numa sessão nova do CLI** — o mesmo vale para
  skill nova.

### Armadilhas no Windows

- **Git Bash não é PowerShell nem WSL.** Use barras normais: `\` é escape no bash e cola os
  caminhos em silêncio (`~/.config\ai\skills` vira `.configaiskills`, e o `cd` falha).
- **`sync-skills.ps1` é só PowerShell; `sync-agents.sh` é só bash.** Não há par no outro shell —
  no Git Bash use os dois `.sh`; no PowerShell chame o segundo via `bash`.
- **`ln -s` no Git Bash não cria symlink por padrão.** Sem Developer Mode do Windows o MSYS copia o
  arquivo: o agente funciona, mas perde-se a propriedade de "`git pull` propaga sozinho" — é preciso
  rodar `sync-agents.sh` a cada mudança em `dist/`. Para symlink de verdade:
  `export MSYS=winsymlinks:nativestrict` com Developer Mode ligado.

## Estrutura de diretórios

- Cada skill é um diretório com `SKILL.md` obrigatório + opcionalmente `scripts/`, `docs/`, `agents/`.
- `providers/` — **referência** de plataformas (host, auth, comandos concretos). **Não** é skill
  (não tem `SKILL.md`); as factories apontam para cá.
- `bin/sync-skills.sh` / `bin/sync-skills.ps1` — recria as cópias em `~/.claude/skills` e garante
  a config do Kilo (`-Cli claude|kilo`, default os dois).
- `arquiteto/bin/build-agents.py` — gera `arquiteto/dist/<cli>/` a partir de `roles/` + `models.json`
  (`--check` valida drift). `arquiteto/bin/sync-agents.sh` — instala o `dist/` no diretório de cada CLI.
- Diretório sem `SKILL.md` na raiz é **ruído** — não é carregado por nenhum agente e deve ser
  evitado (ou é provider, ou está no lugar errado).

## Regras ao criar/editar skills

1. Frontmatter obrigatório: `name` (kebab-case) + `description` (com gatilhos de ativação).
2. Primeira linha do corpo: `**Tipo:** internal`.
3. Seção "Quando executar" — quando o agente deve carregar esta skill.
4. `SKILL.md` enxuto (legível em uma passada). Código/detalhe longo → `docs/` referenciado por caminho.
5. Detalhes de plataforma → `providers/<plataforma>/arquivos.md`, nunca no `SKILL.md` da factory.
6. Nunca versionar segredo (senha, token, chave). Segredos vivem em vaults — ver `vault-factory`.
7. Nunca adicionar rodapé de atribuição de IA em commits/PRs (`Co-Authored-By`, "Generated with ...").
   A mensagem termina no conteúdo escrito.

## Arquitetura factory + provider

Skills com workflow genérico + plataforma específica são divididas em:

- **Factory** (`*-factory/`): fluxo reutilizável (ex.: `issue-factory`, `nuget-factory`,
  `vault-factory`, `commiter`).
- **Provider** (`providers/<plataforma>/arquivos.md`): comandos concretos.

Relação atual: `issue-factory`→gitlab, `commiter`→gitlab, `nuget-factory`→nexus,
`vault-factory`→passbolt+pass-gopass.

## Validação antes de commit

```bash
# 1. Toda skill tem SKILL.md + Tipo
for d in */; do [ -f "$d/SKILL.md" ] || echo "SEM SKILL.md: $d"; done
for d in */; do [ -f "$d/SKILL.md" ] && { grep -q 'Tipo:' "$d/SKILL.md" || echo "SEM Tipo: $d"; }; done

# 2. Referências a caminhos usam ~/.config/ai/skills (não ~/.claude/skills)
grep -rn '~/.claude/skills' --include='SKILL.md' . || true

# 3. Nenhum segredo em texto claro (senha/token no corpo da skill)
grep -rniE '(password|secret|token)\s*[:=]\s*["'"'"'][^"'"'"']{6,}' --include='*.md' . || true

# 4. Sync das skills (claude + kilo)
bin/sync-skills.sh all --dry-run

# 5. dist/ dos subagentes em dia com roles/ + models.json (exit 0)
python3 arquiteto/bin/build-agents.py --check
```

## Padrão de commit

- Mensagem curta e descritiva, sem trailer de coautoria (ver regra 7 acima).
- Ao alterar um skill, atualizar o `README.md` se a lista de skills mudar.

## Skills-chave para consulta

- `arquiteto` — orquestração com subagentes graduados (modelo/esforço).
- `task-observer` — observação contínua de oportunidades de melhoria das skills (invocar no início
  de sessão orientada a tarefa).
- `vault-factory` — leitura de secrets sem expor no chat/histórico.
- `speckit` — Spec-Driven Development (GitHub Spec Kit): qual comando `/speckit.*` rodar a partir do
  estado dos artefatos. Consumida pelo subagente `speckit-master` do `arquiteto`.
