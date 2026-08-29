# Ferramenta: gitlab-auto-merge.sh (SES)

Documentação do script SES `gitlab-auto-merge.sh` — push do branch atual + criação/atualização de MR
+ aprovação + configuração de auto-merge no GitLab. **É uma ferramenta**, não um workflow genérico:
o workflow de commit/push genérico está na skill `commiter`, e a autenticação GitLab em
`providers/gitlab/arquivos.md`.

## Quando usar

- O usuário pedir explicitamente para usar o `gitlab-auto-merge` / "abre MR" / "faz merge na main"
  em projetos SES-RJ hospedados em `gitlab-prod.saude.rj.gov.br` que usam esse script.
- Pré-requisitos: `glab` autenticado no host (`glab auth status -h gitlab-prod.saude.rj.gov.br`) e
  `jq`. Se faltarem, skill `ses-gitlab-deps`.

## Instalação / atualização

Script canônico: `~/.scripts/ses/gitlab-auto-merge.sh`. Instalar ou atualizar (mesmo comando serve
para ambos — não há comando separado de update):

```bash
glab api \
  "projects/ses-rj%2Fdesenvolvimento%2Fscripts%2Fscripts/repository/files/install.sh/raw?ref=main" \
  --hostname gitlab-prod.saude.rj.gov.br \
  | bash
```

Checar instalação:

```bash
command -v gitlab-auto-merge
ls ~/.scripts/ses/gitlab-auto-merge.sh
```

## Uso no dia a dia

Fluxo padrão: estar no branch de trabalho com o(s) commit(s) já feito(s) e a working tree limpa, e
rodar a partir da raiz do projeto. **O script faz o push sozinho — não é preciso `git push` antes.**

```bash
~/.scripts/ses/gitlab-auto-merge.sh
~/.scripts/ses/gitlab-auto-merge.sh -v   # saída detalhada
```

## Configuração por projeto

`gitlab-auto-merge.sh --init` grava label e milestone em `<raiz do git>/.scripts/.gitlab-auto-merge.config`
(JSON lido via `jq`). Depois de configurado, não é preciso passar `-l`/`-m` nas chamadas seguintes.

```bash
~/.scripts/ses/gitlab-auto-merge.sh --init
```

Formato:

```json
{ "label": "AIH APAC", "milestone": "Agosto/2026" }
```

## Flags e variáveis de ambiente

| Flag | Env var | Default | Descrição |
|---|---|---|---|
| `-b`, `--target-branch <branch>` | `SES_TARGET_BRANCH` | `main` | Branch de destino do MR |
| `-l`, `--label <label>` | `SES_LABEL` | — (obrigatório) | Label do MR |
| `-m`, `--milestone <milestone>` | `SES_MILESTONE` | — (opcional) | Milestone do MR |
| `-r`, `--remote <name>` | `SES_REMOTE` | `origin` | Nome do remote |
| `-H`, `--host <hostname>` | `SES_GITLAB_HOST` | `gitlab-prod.saude.rj.gov.br` | Host do GitLab |
| `-p`, `--project-path <dir>` | `SES_PROJECT_DIR` | diretório atual | Diretório do projeto Git |
| `-i`, `--init` | — | — | Inicializa a configuração do projeto |
| `-v` | — | desligado | Mostra etapas detalhadas |
| `-h`, `--help` | — | — | Exibe ajuda |
| — | `GLAB_USE_OP_PLUGIN` | desligado | Usa o plugin do 1Password (`op plugin run -- glab ...`) |

Resolução da label: `-l`/`--label` → `SES_LABEL` → arquivo de config do projeto. Sem nenhuma, o
script aborta pedindo `-l <label>`, `export SES_LABEL=<label>` ou `--init`. Milestone segue a mesma
ordem, mas é opcional.

## O que o script faz (etapas)

1. Verifica dependências (`git`, `jq`, `glab`; `op` se `GLAB_USE_OP_PLUGIN=1`).
2. Verifica autenticação do `glab` no host informado.
3. Valida que está dentro de um repositório Git e que a branch atual é diferente da destino.
4. Atualiza `<remote>/<target-branch>` (`git fetch`).
5. Valida commits novos vs destino e working tree limpa (aborta se suja).
6. Identifica o usuário autenticado no GitLab (assignee/reviewer).
7. Push do branch (com `-u` se sem upstream; rejeição → `git pull --rebase` e reenvio).
8. Localiza MR aberto da branch ou cria novo (`glab mr create --fill --target-branch --label
   --assignee --reviewer --remove-source-branch --yes`, `--milestone` se definido).
9. Atualiza o MR (label/assignee/reviewer/milestone) e aprova (`glab mr approve`).
10. Aguarda o status do MR ficar pronto (state, conflitos, draft, `detailed_merge_status`) — até
    24× com 5s.
11. Configura auto-merge (`glab mr merge --auto-merge --remove-source-branch --yes`) — até 12× com
    10s, e atualiza referências locais no final.

## Cuidados

- Ação sensível (push + merge automático): **confirmar com o usuário antes de rodar**, salvo
  autorização explícita.
- Label é obrigatória — sem ela o script aborta.
- Não rodar com working tree suja.
- Se o auto-merge não puder ser configurado (pipeline pendente além do limite de tentativas), o
  script falha ao final e o MR fica aberto. **Reporte a URL/IID do MR ao usuário** em vez de tentar
  mergear manualmente (`glab mr view <IID> --web`).
