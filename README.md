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
├── bin/validate-skills.sh     # valida skills (SKILL.md, frontmatter, Tipo, segredo, py/sh, README); --staged/--full (só bash)
├── bin/commit-skill.sh        # commit de uma skill com validação; dry-run por padrão, --yes e --push (só bash)
├── bin/install-hooks.sh       # ativa .githooks/ neste clone, opcional por máquina (só bash)
├── .githooks/                 # pre-commit (valida skills staged) e commit-msg (bloqueia atribuição de IA)
├── providers/                 # referência de plataformas (NÃO é skill carregável)
│   ├── gitlab/arquivos.md     # GitLab: host, auth, projetos, labels, GraphQL
│   ├── gitlab/automerge.md    # ferramenta gitlab-auto-merge.sh
│   ├── nexus/arquivos.md      # Nexus: host, TFM bug, armadilhas
│   ├── passbolt/arquivos.md   # Passbolt: CLI, pb find/import/export
│   ├── pass-gopass/arquivos.md# pass/gopass: cofre local GPG
│   └── vault/arquivos.md      # HashiCorp Vault (KV v2): nomes de chaves, ExternalSecret/ArgoCD
├── THIRD_PARTY_NOTICES.md     # licenças das skills adaptadas de terceiros (ECC, Cloudflare; MIT)
├── angular-developer/         # Angular: signals, forms, DI, rotas, SSR, testes (referências em references/) [ECC]
├── api-design/                # design de API REST: recursos, status, paginação, erros, versionamento [ECC]
├── architecture-decision-records/ # ADRs numerados em docs/adr/ [ECC]
├── arquiteto/                 # orquestração híbrida: executa direto o pequeno, delega a subagentes quando paga
│                              # (claude/kilo/codex/gemini/antigravity/opencode)
├── atividade-factory/         # commits → issues por funcionalidade (GitLab)
├── audit-log/                 # biblioteca AuditLog (NuGet)
├── backend-wiki-skills/       # roteador das skills de backend .NET
├── bash-scripting-pitfalls/   # armadilhas de bash (source, set -e)
├── configurar-video-jogos/    # GPU NVIDIA/PRIME e jogos da Steam (Flatpak)
├── azuredevops-api/            # work items + export de wiki Azure DevOps (CLI ado)
├── claude-guard-hooks/        # hooks PreToolUse: bloqueia atribuição de IA, --no-verify, vazamento de segredo; confirma comando destrutivo
├── claude-md/                 # criar, auditar e enxugar CLAUDE.md pelas recomendações da Anthropic
├── claude-mem-project-exclusion/ # excluir pasta e apagar memórias do plugin claude-mem
├── codebase-onboarding/       # guia de onboarding e CLAUDE.md/AGENTS.md inicial de um repo [ECC]
├── commiter/                  # workflow genérico de commit + push
├── context-budget/            # auditoria do consumo de contexto (skills, agentes, MCP, regras) [ECC]
├── csharp-testing/            # testes C#/.NET genéricos: xUnit, FluentAssertions, mocks [ECC]
├── database-migrations/       # migrations seguras e reversíveis, expand-contract, backfill em lotes [ECC]
├── decisoes-com-usuario/      # decisões do usuário via grilling + AskUserQuestion (ou equivalente do agente)
├── dependency-upgrade-spike/  # decidir upgrade de dependência sem confiar no changelog
├── dotnet-backend-architecture/  # padrão arquitetural .NET backend
├── dotnet-patterns/           # idioma C#/.NET: DI, async, nulabilidade, convenções [ECC]
├── dotnet-project-rename/     # renomear projeto .NET sem quebrar o build
├── grilling/                  # grill do usuário sobre plano/decisão/ideia
├── hangfire-setup/            # Hangfire: abstrações + implementação (código em docs/)
├── healthcare-phi-compliance/ # padrões técnicos de proteção de dado de saúde [ECC]
├── headroom/                  # headroom (proxy de contexto)
├── instalacao-appimage-linux/ # instalar AppImage (ícone, atalho, dock GNOME) + scripts/install.sh
├── issue-factory/             # workflow genérico de issues (+ providers/github)
├── keycloak-api/              # Admin REST API Keycloak (CLI kc)
├── lgpd/                      # LGPD na prática de desenvolvimento: dado de saúde, logs, retenção, incidente
├── nuget-factory/             # workflow genérico de pacotes NuGet (+ providers/nexus)
├── ramguard/                  # operação do ramguard (encerra processo pesado com RAM alta)
├── replatforms/               # migração Delphi 7 → .NET + Angular (prompt em docs/)
├── search-first/              # pesquisar fora antes de construir: relatório com fontes (upstream shimo4228, MIT)
├── security-audit/            # auditoria de segurança white-box com verificação independente e relatório [Cloudflare]
├── security-review/           # checklist de segurança (OWASP), regra de evidência e varredura de dependências [ECC]
├── speckit/                   # Spec-Driven Development com GitHub Spec Kit (comandos + instalação em docs/)
├── sql-data-cleanup/          # scripts SQL de dedupe/limpeza decididos por evidência
├── t3-code-acesso-remoto/     # T3 Code: serviço em background, desktop em outro home, acesso mobile via Tailscale (docs/)
├── t3-code-orquestracao/      # T3 Code por dentro da thread: delegar a outro provider, papéis do arquiteto, threads/worktree, clonar pelo nome
├── task-observer/             # observação de skills, sob demanda (/task-observer)
├── tdd-first/                 # TDD: primeiro movimento por tipo de operação, runner, evidência RED/GREEN
├── us-legado-factory/         # US de sistemas legados a partir de código e docs (sob arquiteto; export azuredevops-api)
├── vault-factory/             # abstração de cofres de secrets (+ providers/passbolt, pass-gopass, vault)
├── verification-loop/         # verificação em seis fases antes de PR [ECC]
├── webpush-vapid-factory/     # Web Push VAPID (Angular + .NET)
└── windows-audio-mic/         # diagnosticar/corrigir microfone no Windows (mudo/padrão)
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
| `vault-factory` | `providers/passbolt/arquivos.md`, `providers/pass-gopass/arquivos.md`, `providers/vault/arquivos.md` |

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
