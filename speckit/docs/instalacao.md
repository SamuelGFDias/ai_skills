# Instalação e atualização do `specify` CLI

Referência da skill `speckit`. O `specify` é o CLI Python que instala os slash commands `/speckit.*`
e o esqueleto `.specify/` dentro de um repo. Ele é instalado **uma vez por máquina**; o
`specify init` roda **uma vez por repo**.

## Pré-requisitos

- Python 3.11+
- `uv` (recomendado) ou `pipx`
- Git
- Linux, macOS ou Windows

## Instalar o CLI (uma vez por máquina)

```bash
# via PyPI (mais simples)
uv tool install specify-cli

# ou fixando uma release do repo
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@vX.Y.Z
```

Substitua `vX.Y.Z` por uma tag real (mantendo o `v`).

### Windows (PowerShell)

`uv` ainda não instalado:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
uv tool install specify-cli
```

Depois de instalar, `specify` fica em `%USERPROFILE%\.local\bin`. Se o comando não for encontrado,
o diretório não está no PATH:

```powershell
uv tool update-shell     # adiciona ao PATH do usuário
# feche e reabra o terminal
```

Verificação:

```powershell
specify --version
```

## Inicializar um repo (uma vez por repo)

```bash
# repo existente, integração Claude Code, sem prompt interativo
specify init --here --force --non-interactive --integration claude

# criar projeto novo
specify init meu-projeto --integration claude
cd meu-projeto
```

Flags relevantes:

| Flag | Efeito |
|---|---|
| `--here` | inicializa no diretório atual em vez de criar um novo |
| `--integration <agente>` | `claude`, `copilot`, ... — define onde os comandos são instalados |
| `--force` | sobrescreve diretório não vazio |
| `--non-interactive` | sem prompts (CI, automação, subagente) |
| `--ignore-agent-tools` | pula a checagem das ferramentas do agente |

O que aparece depois do init: `.specify/` (templates + `memory/`), `.claude/commands/` (os slash
commands) e, conforme as features forem criadas, `specs/NNN-*/`.

**Os slash commands só aparecem numa sessão nova do Claude Code.** Depois do `init`, reiniciar a
sessão antes de tentar `/speckit.constitution`.

## Atualizar

```bash
specify self check              # há versão nova?
specify self upgrade --dry-run  # o que mudaria
specify self upgrade            # aplica
specify self upgrade --tag vX.Y.Z   # fixa numa release
```

Um upgrade pode reescrever templates em `.specify/templates/`. Customizações do projeto devem morar
em `.specify/templates/overrides/`, que tem prioridade sobre os templates core e sobrevive ao upgrade.

Ordem de resolução dos templates, da maior para a menor prioridade:

1. `.specify/templates/overrides/` (projeto)
2. `.specify/presets/templates/`
3. `.specify/extensions/templates/`
4. `.specify/templates/` (core do Spec Kit)

## Troubleshooting

| Sintoma | Causa provável | Ação |
|---|---|---|
| `specify: command not found` após instalar | `~/.local/bin` (ou `%USERPROFILE%\.local\bin`) fora do PATH | `uv tool update-shell` e reabrir o terminal |
| `/speckit.*` não aparece no Claude Code | sessão anterior ao `init` | reiniciar a sessão do CLI |
| `init` recusa o diretório | diretório não vazio | `--force` |
| `init` trava esperando input | picker interativo | `--non-interactive` |
| customização de template sumiu após upgrade | editou `.specify/templates/` direto | mover para `.specify/templates/overrides/` |
