---
name: gitlab-auto-merge
description: Documenta e padroniza o uso do script SES gitlab-auto-merge.sh (push do branch atual, criação/atualização de MR, aprovação e configuração de auto-merge no GitLab) sem precisar reler o script. Use quando o usuário pedir para abrir MR, fazer merge na main, subir o branch, usar o gitlab-auto-merge, ou quando o trabalho tiver terminado e precisar ir para a main via merge request em projetos SES-RJ hospedados em gitlab-prod.saude.rj.gov.br.
---

# Skill: gitlab-auto-merge

## Quando executar

- Pedidos como "abre MR", "faz merge na main", "sobe esse branch", "usa o gitlab-auto-merge".
- Quando o trabalho terminou e precisa ir para a main via merge request em projetos SES-RJ
  hospedados em `gitlab-prod.saude.rj.gov.br`.

## Pré-requisitos

- `glab` autenticado no host (`glab auth status -h gitlab-prod.saude.rj.gov.br`) e `jq` instalados.
- Se algum estiver faltando, use a skill `ses-gitlab-deps` (cobre instalação de `jq`/`glab`) em vez
  de instalar manualmente aqui.

## Instalação / atualização do script

O script canônico fica em `~/.scripts/ses/gitlab-auto-merge.sh`. Quando ele não estiver no PATH
nem existir nesse caminho, ou quando o usuário quiser atualizar para a versão mais recente, use
sempre este comando (exige `glab` já autenticado em `gitlab-prod.saude.rj.gov.br`):

```bash
glab api \
  "projects/ses-rj%2Fdesenvolvimento%2Fscripts%2Fscripts/repository/files/install.sh/raw?ref=main" \
  --hostname gitlab-prod.saude.rj.gov.br \
  | bash
```

Esse mesmo comando serve tanto para instalar do zero quanto para atualizar para a versão mais
recente — não há um comando separado de "update".

Checar se já está instalado:

```bash
command -v gitlab-auto-merge
ls ~/.scripts/ses/gitlab-auto-merge.sh
```

## Uso no dia a dia

Fluxo padrão: estar no branch de trabalho com o(s) commit(s) já feito(s) e a working tree limpa,
e rodar o script a partir da raiz do projeto. **O script faz o push sozinho — não é preciso
`git push` antes.**

```bash
~/.scripts/ses/gitlab-auto-merge.sh
```

Com saída detalhada:

```bash
~/.scripts/ses/gitlab-auto-merge.sh -v
```

## Configuração por projeto

`gitlab-auto-merge.sh --init` grava label e milestone em
`<raiz do git>/.scripts/.gitlab-auto-merge.config` (JSON lido via `jq`). Depois de configurado,
não é preciso passar `-l`/`-m` nas chamadas seguintes.

```bash
~/.scripts/ses/gitlab-auto-merge.sh --init
```

Formato do arquivo:

```json
{
  "label": "AIH APAC",
  "milestone": "Agosto/2026"
}
```

Exemplo real: o projeto aih-apac usa `{"label": "AIH APAC", "milestone": "Agosto/2026"}`.

## Flags e variáveis de ambiente

| Flag | Env var | Default | Descrição |
|---|---|---|---|
| `-b`, `--target-branch <branch>` | `SES_TARGET_BRANCH` | `main` | Branch de destino do MR |
| `-l`, `--label <label>` | `SES_LABEL` | — (obrigatório) | Label do MR |
| `-m`, `--milestone <milestone>` | `SES_MILESTONE` | — (opcional) | Milestone do MR |
| `-r`, `--remote <name>` | `SES_REMOTE` | `origin` | Nome do remote |
| `-H`, `--host <hostname>` | `SES_GITLAB_HOST` | `gitlab-prod.saude.rj.gov.br` | Host do GitLab |
| `-p`, `--project-path <dir>` | `SES_PROJECT_DIR` | diretório atual | Diretório do projeto Git |
| `-i`, `--init` | — | — | Inicializa a configuração do projeto (label e milestone) |
| `-v` | — | desligado | Mostra etapas detalhadas |
| `-h`, `--help` | — | — | Exibe ajuda |
| — | `GLAB_USE_OP_PLUGIN` | desligado | Usa o plugin do 1Password (`op plugin run -- glab ...`) para autenticação |

A resolução da label segue esta ordem: `-l`/`--label` → `SES_LABEL` → arquivo de config do
projeto. Se nenhuma delas resolver, o script aborta pedindo `-l <label>`, `export SES_LABEL=<label>`
ou `gitlab-auto-merge.sh --init`. Milestone segue a mesma ordem, mas é opcional.

## O que o script faz (etapas)

1. Verifica dependências (`git`, `jq`, `glab`; `op` se `GLAB_USE_OP_PLUGIN=1`).
2. Verifica autenticação do `glab` no host informado.
3. Valida que está dentro de um repositório Git e que a branch atual é diferente da branch destino.
4. Atualiza a referência `<remote>/<target-branch>` (`git fetch`).
5. Valida que a branch atual tem commits novos em relação ao destino e que a working tree está
   limpa (aborta se houver alterações não commitadas).
6. Identifica o usuário autenticado no GitLab (usado como assignee/reviewer).
7. Faz o push do branch atual (com `-u` se não houver upstream; em caso de rejeição, tenta
   `git pull --rebase` e reenvia).
8. Localiza um MR aberto para a branch, ou cria um novo (`glab mr create --fill --target-branch
   --label --assignee --reviewer --remove-source-branch --yes`, com `--milestone` se definido).
9. Atualiza o MR (label/assignee/reviewer/milestone) e o aprova (`glab mr approve`).
10. Aguarda o status do MR ficar pronto (checa `state`, conflitos, draft e
    `detailed_merge_status`), tentando por até 24 vezes com 5s de intervalo.
11. Configura o auto-merge (`glab mr merge --auto-merge --remove-source-branch --yes`), tentando
    por até 12 vezes com 10s de intervalo, e atualiza as referências locais no final.

## Cuidados

- Ação sensível (push + configura merge automático na branch de destino): **confirmar com o
  usuário antes de rodar**, salvo autorização explícita já dada.
- Label é obrigatória — sem ela o script aborta.
- Não rodar com a working tree suja; o script recusa se houver alterações não commitadas.
- Se o auto-merge não puder ser configurado (ex.: pipeline pendente além do limite de tentativas),
  o script falha ao final e o MR fica aberto aguardando. Nesse caso, **reporte a URL/IID do MR ao
  usuário** em vez de tentar mergear manualmente (`glab mr view <IID> --web`).
