# AGENTS.md — AI Skills (Claude Code / Kilo)

Este repositório é a fonte de **skills compartilhadas** dos agentes de IA (Claude Code e Kilo). Ao
trabalhar aqui, siga estas regras para manter o ambiente sem ruído e sem débitos de limpeza.

## Contexto de integração

- **Fonte real:** `~/.config/ai/skills` (este repo, git versionado).
- **Claude Code:** lê de `~/.claude/skills/<nome>` — no Linux/macOS/WSL é **symlink** para a skill
  neste repo; no Windows/Git Bash é **cópia** fiel (ver "Armadilhas no Windows" abaixo pra saber
  por quê). Toda skill nova ou alterada exige rodar o sync (ver "Sincronização" abaixo) para
  recriar o destino; sem isso o Claude Code continua vendo a versão antiga — no modo cópia sempre,
  no modo symlink só quando a skill é renomeada/removida (o conteúdo de uma skill existente já
  propaga sozinho via `git pull`, sem precisar de sync). Os subagentes do `arquiteto` são
  instalados por outro script — mesma seção.
- **Kilo:** lê via `skills.paths` em `~/.config/kilo/kilo.jsonc` → `~/.config/ai/skills`
  (pega automaticamente todo diretório com `SKILL.md`, direto da fonte — sem cópia). O sync com
  alvo `kilo` só garante que esse caminho está configurado; é idempotente e normalmente roda uma
  vez só.
- **Codex:** lê skills de `$HOME/.agents/skills/<nome>` (symlink/cópia, mecanismo nativo de skills
  do Codex CLI) — populado por `bin/sync-skills.sh codex` / `bin/sync-skills.ps1 -Cli codex`.
- **Gemini CLI / Antigravity (`agy`):** descobre skills via *extension* em
  `~/.gemini/extensions/ai-skills/skills/<nome>` e via config em `~/.gemini/config/skills/`,
  mantidos por `bin/sync-skills.sh gemini` / `bin/sync-skills.ps1 -Cli gemini`. Detectado no
  `install.sh` via comando `gemini` ou `agy`.
- **opencode:** não tem destino próprio de skills — lê `~/.claude/skills` nativamente (compat
  documentada com Claude Code). Basta o alvo `claude` do sync já estar em dia; não precisa do
  binário `claude` instalado.

## Sincronização

Duas coisas independentes precisam ser sincronizadas — alterar uma não sincroniza a outra:

| O quê | Fonte | Destino | Script |
|---|---|---|---|
| **Skills** (`<nome>/SKILL.md`) | este repo | `~/.claude/skills/<nome>` (symlink no Linux/macOS/WSL, cópia no Windows) | `bin/sync-skills.sh` / `bin/sync-skills.ps1` |
| **Subagentes do `arquiteto`** | `arquiteto/roles/` + `arquiteto/cli/<cli>/models.json` | `~/.claude/agents/`, `~/.config/kilo/agent/`, `~/.codex/agents/` | `arquiteto/bin/build-agents.py` → `arquiteto/bin/sync-agents.sh` |

`bin/install.sh` / `bin/install.ps1` cobrem as duas linhas da tabela de uma vez só, para cada CLI
detectado na máquina — ver "Caminho recomendado" logo abaixo.

### Caminho recomendado: install.sh / install.ps1

`bin/install.sh` (bash/WSL/Git Bash) e `bin/install.ps1` (PowerShell) detectam quais CLIs de IA
suportados (`claude`, `kilo`, `codex`, `gemini`/`agy`, `opencode`) estão instalados nesta máquina (via
`command -v`/`Get-Command`) e rodam automaticamente, para cada um, o `sync-skills` + `sync-agents`
correspondentes — inclusive para `codex` e `gemini` (e Antigravity `agy`), que antes exigiam passos manuais, e para
`opencode`, que só lê skills (via compat nativa com `~/.claude/skills`) e ganha DeepSeek como
modelo default se ainda não tiver nenhum configurado. Idempotente, pode rodar quantas vezes quiser.
Aceita `--dry-run`/`-DryRun` para só mostrar o que faria.

```bash
cd ~/.config/ai/skills
bin/install.sh              # ou --dry-run para só ver o que faria
```

```powershell
cd $HOME\.config\ai\skills
pwsh bin/install.ps1        # ou -DryRun para só ver o que faria
```

`install.sh`/`install.ps1` NÃO regeneram `arquiteto/dist/` (isso continua manual, passo de
manutenção do repo — ver "Quando rodar o quê" abaixo) e não instalam dependências de skills
individuais (jq, glab, oc etc.).

A sequência abaixo é o que o `install.sh`/`.ps1` roda por baixo dos panos, útil para rodar um
passo isolado ou entender exatamente o que aconteceu:

### Sequência completa (manual)

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
- **Por isso `sync-skills.sh` copia em vez de linkar no Windows.** O script detecta a plataforma via
  `uname -s` (`MINGW*`/`MSYS*`/`CYGWIN*` → cópia; qualquer outra, incluindo Linux/macOS/WSL →
  symlink) e escolhe o modo sozinho — não precisa configurar nada. Pra forçar um modo específico
  (ex.: testar o caminho "Windows" a partir do Linux), defina `FORCE_LINK_MODE=copy` ou
  `FORCE_LINK_MODE=symlink` antes de chamar o script.

## Estrutura de diretórios

- Cada skill é um diretório com `SKILL.md` obrigatório + opcionalmente `scripts/`, `docs/`, `agents/`.
- `providers/` — **referência** de plataformas (host, auth, comandos concretos). **Não** é skill
  (não tem `SKILL.md`); as factories apontam para cá.
- `bin/sync-skills.sh` / `bin/sync-skills.ps1` — recria o destino em `~/.claude/skills` (symlink no
  Linux/macOS/WSL via `.sh`; cópia no Windows, seja via `.sh` no Git Bash ou via `.ps1`) e garante
  a config do Kilo (`-Cli claude|kilo`, default os dois).
- `bin/install.sh` / `bin/install.ps1` — detecta quais CLIs (`claude`, `kilo`, `codex`, `gemini`,
  `opencode`) estão instalados na máquina e roda `sync-skills` + `sync-agents` para cada um
  automaticamente (ver "Caminho recomendado" em "Sincronização").
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

Relação atual: `vault-factory`→passbolt+pass-gopass+vault.

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

A automação cobre os 5 itens acima: `bin/validate-skills.sh` (itens 1 a 3; `--full` acrescenta 4 e 5,
este último quando arquiteto é alvo). Para commitar uma skill, use `bin/commit-skill.sh <skill> -m
"<descrição>"`: é dry-run por padrão, `--yes` commita e `--push` publica. `bin/install-hooks.sh` é
opcional por máquina e ativa `.githooks/` (valida skills staged e bloqueia atribuição de IA na mensagem).
Essas ferramentas são só bash, sem par `.ps1`.

## Padrão de commit

- Mensagem curta e descritiva, sem trailer de coautoria (ver regra 7 acima).
- Ao alterar um skill, atualizar o `README.md` se a lista de skills mudar.

## Skills-chave para consulta

- `arquiteto` — orquestração híbrida: executa direto o que é pequeno e delega a subagentes graduados (modelo/esforço) quando paga.
- `task-observer` — observação de oportunidades de melhoria das skills. Só sob demanda, com
  `/task-observer` (invocação automática desligada para economizar contexto).
- `vault-factory` — leitura de secrets sem expor no chat/histórico.
- `speckit` — Spec-Driven Development (GitHub Spec Kit): qual comando `/speckit.*` rodar a partir do
  estado dos artefatos. Consumida pelo subagente `speckit-master` do `arquiteto`.
