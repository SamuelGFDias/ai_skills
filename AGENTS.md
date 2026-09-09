# AGENTS.md — AI Skills (Claude Code / Kilo)

Este repositório é a fonte de **skills compartilhadas** dos agentes de IA (Claude Code e Kilo). Ao
trabalhar aqui, siga estas regras para manter o ambiente sem ruído e sem débitos de limpeza.

## Contexto de integração

- **Fonte real:** `~/.config/ai/skills` (este repo, git versionado).
- **Claude Code:** lê de **cópias** em `~/.claude/skills/<nome>` (não symlink/junction — cópia
  fiel do diretório da skill). Toda skill nova ou alterada exige rodar `bin/sync-skills.sh claude`
  (Linux/macOS/WSL) ou `bin/sync-skills.ps1 -Cli claude` (Windows) para recriar a cópia; sem
  isso o Claude Code continua vendo a versão antiga.
- **Kilo:** lê via `skills.paths` em `~/.config/kilo/kilo.jsonc` → `~/.config/ai/skills`
  (pega automaticamente todo diretório com `SKILL.md`, direto da fonte — sem cópia). O sync
  (`bin/sync-skills.sh kilo` / `bin/sync-skills.ps1 -Cli kilo`) só garante que esse caminho está
  configurado; é idempotente e normalmente roda uma vez só.
- Rodar `bin/sync-skills.sh` / `bin/sync-skills.ps1` sem argumento aplica os dois alvos.
- **Remotes (ambos privados):** GitHub `git@github.com:SamuelGFDias/ai_skills.git`.

## Estrutura de diretórios

- Cada skill é um diretório com `SKILL.md` obrigatório + opcionalmente `scripts/`, `docs/`, `agents/`.
- `providers/` — **referência** de plataformas (host, auth, comandos concretos). **Não** é skill
  (não tem `SKILL.md`); as factories apontam para cá.
- `bin/sync-skills.sh` / `bin/sync-skills.ps1` — recria as cópias em `~/.claude/skills` e garante
  a config do Kilo (`-Cli claude|kilo`, default os dois).
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
```

## Padrão de commit

- Mensagem curta e descritiva, sem trailer de coautoria (ver regra 7 acima).
- Ao alterar um skill, atualizar o `README.md` se a lista de skills mudar.

## Skills-chave para consulta

- `arquiteto` — orquestração com subagentes graduados (modelo/esforço).
- `task-observer` — observação contínua de oportunidades de melhoria das skills (invocar no início
  de sessão orientada a tarefa).
- `vault-factory` — leitura de secrets sem expor no chat/histórico.
