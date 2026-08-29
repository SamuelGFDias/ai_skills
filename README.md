# AI Skills

Repositório de **skills reutilizáveis para agentes de IA** (Claude Code e Kilo), organizadas por
domínio. Cada skill é um diretório com `SKILL.md` (obrigatório) e, quando aplicável, `scripts/` e
`docs/`.

## Estrutura

```text
ai_skills/
├── AGENTS.md                  # arquitetura do ambiente (leia ao trabalhar neste repo)
├── bin/sync-symlinks.sh       # sincroniza symlinks em ~/.claude/skills
├── providers/                 # referência de plataformas (NÃO é skill carregável)
│   ├── gitlab/arquivos.md     # GitLab: host, auth, projetos, labels, GraphQL
│   ├── gitlab/automerge.md    # ferramenta gitlab-auto-merge.sh
│   ├── nexus/arquivos.md      # Nexus: host, TFM bug, armadilhas
│   ├── passbolt/arquivos.md   # Passbolt: CLI, pb find/import/export
│   └── pass-gopass/arquivos.md# pass/gopass: cofre local GPG
├── arquiteto/                 # orquestração: subagentes graduados por modelo/esforço
├── audit-log/                 # biblioteca AuditLog (NuGet)
├── commiter/                  # workflow genérico de commit + push
├── dotnet-backend-architecture/  # padrão arquitetural .NET backend
├── hangfire-setup/            # Hangfire: abstrações + implementação (código em docs/)
├── headroom/                  # headroom (proxy de contexto)
├── issue-factory/             # workflow genérico de issues
├── keycloak-api/              # Admin REST API Keycloak (CLI kc)
├── nuget-factory/             # workflow genérico de pacotes NuGet (+ providers/nexus)
├── replatforms/               # migração Delphi 7 → .NET + Angular (prompt em docs/)
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
7. Após criar, rode `bin/sync-symlinks.sh` para expor ao Claude Code.

## Publicação

O repo tem remote privado no GitHub (`git@github.com:SamuelGFDias/ai_skills.git`).

```bash
git pull --rebase origin main
git add .
git commit -m "feat: descrição"
git push
```
