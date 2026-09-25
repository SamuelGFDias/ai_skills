# AI Skills

Repositório de **skills reutilizáveis para agentes de IA** (Claude Code e Kilo), organizadas por
domínio. Cada skill é um diretório com `SKILL.md` (obrigatório) e, quando aplicável, `scripts/` e
`docs/`.

## Estrutura

```text
ai_skills/
├── AGENTS.md                  # arquitetura do ambiente (leia ao trabalhar neste repo)
├── bin/install.sh             # instala tudo que as skills precisam nos CLIs instalados na
│                               # máquina — claude/kilo/codex/gemini/opencode (Linux/macOS/WSL)
├── bin/install.ps1            # idem, para Windows
├── bin/sync-skills.sh         # (re)cria as skills em claude/kilo (Linux/macOS/WSL)
├── bin/sync-skills.ps1        # idem, para Windows
├── providers/                 # referência de plataformas (NÃO é skill carregável)
│   ├── gitlab/arquivos.md     # GitLab: host, auth, projetos, labels, GraphQL
│   ├── gitlab/automerge.md    # ferramenta gitlab-auto-merge.sh
│   ├── nexus/arquivos.md      # Nexus: host, TFM bug, armadilhas
│   ├── passbolt/arquivos.md   # Passbolt: CLI, pb find/import/export
│   └── pass-gopass/arquivos.md# pass/gopass: cofre local GPG
├── arquiteto/                 # orquestração: subagentes graduados por modelo/esforço
├── audit-log/                 # biblioteca AuditLog (NuGet)
├── azuredevops-api/            # work items + export de wiki Azure DevOps (CLI ado)
├── claude-mem-project-exclusion/ # excluir pasta e apagar memórias do plugin claude-mem
├── commiter/                  # workflow genérico de commit + push
├── dotnet-backend-architecture/  # padrão arquitetural .NET backend
├── hangfire-setup/            # Hangfire: abstrações + implementação (código em docs/)
├── headroom/                  # headroom (proxy de contexto)
├── issue-factory/             # workflow genérico de issues
├── keycloak-api/              # Admin REST API Keycloak (CLI kc)
├── nuget-factory/             # workflow genérico de pacotes NuGet (+ providers/nexus)
├── replatforms/               # migração Delphi 7 → .NET + Angular (prompt em docs/)
├── speckit/                   # Spec-Driven Development com GitHub Spec Kit (comandos + instalação em docs/)
├── task-observer/             # observação contínua de skills
└── vault-factory/             # abstração de cofres de secrets (+ providers/passbolt, pass-gopass)
```

## Arquitetura: factory + provider

Skills que misturam **workflow genérico** e **detalhes de plataforma** são divididas:

- **Factory** (`*-factory`): o fluxo reutilizável, independente da tecnologia (ex.: `issue-factory`).
- **Provider** (`providers/<plataforma>/arquivos.md`): comandos, URLs e credenciais concretos
  (ex.: `providers/nexus/arquivos.md`). Arquivos de provider **não têm `SKILL.md`** — são
  referência que as factories apontam.

Relação atual:

| Factory | Provider(s) |
|---|---|
| `nuget-factory` | `providers/nexus/arquivos.md` |
| `vault-factory` | `providers/passbolt/arquivos.md`, `providers/pass-gopass/arquivos.md` |

Regra: se uma skill depende de host/credencial de um sistema específico, o detalhe vai para
`providers/`; a skill mantém o fluxo genérico e aponta para o provider.

## Confidencialidade

**Todas as skills são `internal`** — o repo é privado (GitHub). Todo `SKILL.md` deve
carregar `**Tipo:** internal`. Nenhum segredo deve ser versionado (senhas, tokens, chaves) — segredos
vivem em vaults (`vault-factory`).

## Convenções ao criar/editar skills

1. Diretório em `kebab-case`; obrigatório `SKILL.md` com frontmatter (`name`, `description`).
2. Primeira linha do corpo: `**Tipo:** internal`.
3. Seção "Quando executar" com gatilhos claros de ativação.
4. `SKILL.md` enxuto (legível em uma passada); código/detalhe longo vai para `docs/` referenciado
   por caminho (ver `hangfire-setup`).
5. Detalhes de plataforma vão para `providers/` (nunca no `SKILL.md` da factory).
6. Prefira `kebab-case`, sem duplicar instruções de outras skills.
7. Após criar, rode o sync — sequência completa e armadilhas de Windows/Git Bash em
   `AGENTS.md`, seção "Sincronização". Em resumo: `bin/sync-skills.sh` (bash/WSL/Git Bash) ou
   `bin/sync-skills.ps1` (PowerShell) para
   expor a skill aos CLIs. Sem argumento, sincroniza claude + kilo; use `claude` ou `kilo` para um
   alvo só. Para o Claude Code, a skill vira **symlink** em `~/.claude/skills/<nome>` no
   Linux/macOS/WSL, ou é **copiada** no Windows/Git Bash — o destino é recriado a cada run em
   ambos os casos. Para o Kilo, o script só garante que o caminho do repo esteja em
   `skills.paths` de `~/.config/kilo/kilo.jsonc` — ele lê os `SKILL.md` direto da fonte, sem
   cópia nem symlink (ver `AGENTS.md`). Atalho: `bin/install.sh` / `bin/install.ps1` (sem
   argumento) já cobre isso para todos os CLIs detectados na máquina, sem precisar escolher o
   alvo manualmente.

## Publicação

O repo tem remote privado no GitHub (`git@github.com:SamuelGFDias/ai_skills.git`).

```bash
git pull --rebase origin main
git add .
git commit -m "feat: descrição"
git push
```
