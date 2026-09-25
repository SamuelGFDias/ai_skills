---
name: azuredevops-api
description: Consulta work items (User Stories, Tasks etc.) e exporta documentação de wiki do Azure DevOps via REST API, usando apelidos locais que mapeiam um nome curto de projeto/cliente (ex.: settorj) para {organização, projeto, wiki} — a organização é fixa por credencial, o projeto é variável por apelido. O PAT fica em arquivo local fora do git (nunca versionado, nunca impresso); os scripts .sh fazem o trabalho mecânico de chamar a API e limpar HTML para não gastar tokens do modelo. Use quando o usuário pedir para listar/consultar work items do Azure DevOps por um apelido de projeto, detalhar um work item específico, ou exportar um path de wiki de um projeto Azure DevOps para Markdown local com anexos baixados em assets/.
---

# Skill: azuredevops-api

**Tipo:** internal

## Quando executar

Quando o usuário pedir para:
- Listar/consultar work items (User Stories, Tasks, Bugs...) de um projeto Azure DevOps
  referenciado por um apelido curto (ex.: "pegar as US do settorj").
- Detalhar um work item específico (descrição, critérios de aceitação, estado, responsável).
- Exportar a documentação de um path de wiki de um projeto Azure DevOps para Markdown local,
  com anexos baixados numa pasta `assets/` e referenciados no markdown.
- Cadastrar/atualizar a credencial (PAT) de uma organização Azure DevOps, ou o apelido de um
  projeto novo.

## Modelo de cadastro: credencial (org) e apelido (projeto) são separados

- **Credencial** (`scripts/setup.sh <ORG>`) — cadastra o PAT de uma organização. Uma
  organização só precisa de setup uma vez; fica em
  `~/.claude/secrets/azuredevops/<org-slug>.env` (chmod 600), **fora** do repositório git
  desta skill — nunca é lido com `cat`/`Read`, só é `source`ado dentro do processo dos
  scripts (`lib.sh:ado_load_pat`).
- **Apelido de projeto** (`scripts/aliases.sh add <apelido> --org <ORG> --project <PROJETO>
  [--wiki <WIKI>]`) — mapeia um nome curto para `{org, project, wiki}`. **Não guarda
  segredo**, é seguro versionar: fica em `config/projects.json`, dentro do repositório desta
  skill (mesmo padrão de "realms" da skill `keycloak-api` — cadastro de equipe, sincronizado
  via `git pull` entre máquinas). A organização normalmente é a mesma para todos os apelidos
  de um cliente; o que varia de apelido para apelido é o projeto (e, às vezes, a wiki).

Todo comando de consulta recebe um `<apelido>` já cadastrado — nunca org/projeto crus na
linha de comando (evita repetir string longa e evita esquecer qual credencial usar).

## Princípio de segurança

- **Nunca** peça ao usuário para colar o PAT na mensagem de chat. Se ele fizer isso mesmo
  assim (como aconteceu no design desta skill), use normalmente mas avise que o ideal é
  rotacionar o token depois — ele ficou registrado no histórico da conversa. Delete qualquer
  `.env`/arquivo solto que tenha sido criado como ponte antes desta skill existir, depois de
  confirmar que a credencial já está no lugar certo.
- `scripts/setup.sh` lê o PAT com `read -rsp` (entrada oculta) e nunca ecoa o valor; a
  validação usa o PAT só dentro da própria chamada `curl`, nunca em `echo`.
- Nenhum script desta skill imprime o conteúdo de `~/.claude/secrets/azuredevops/*.env`.
- `config/projects.json` nunca deve ganhar um campo de token/PAT — se algum dia precisar de
  credencial por projeto (em vez de por org), criar uma seção separada, nunca misturar no
  arquivo versionado.

## Primeiro uso (nenhuma credencial/apelido cadastrado ainda)

```bash
scripts/setup.sh "Extreme-Digital"
scripts/aliases.sh add settorj --org "Extreme-Digital" --project "0391.2_RJ_SES_SUSTENTACAO"
```

Depois disso, `settorj` (ou qualquer outro apelido cadastrado) pode ser usado em todos os
comandos de consulta abaixo. Ver apelidos já cadastrados: `scripts/aliases.sh list`.

## Comandos disponíveis

Interface única: `scripts/ado.sh <subcomando> ...` (ou, após `scripts/init.sh`, só `ado
<subcomando> ...` em qualquer diretório/shell). Por baixo, cada subcomando delega via `exec`
para o script individual em `scripts/`.

### Cadastro

- `ado setup <ORG>` — cadastra/atualiza o PAT da organização (pede confirmação se já existir).
- `ado alias add <apelido> --org <ORG> --project <PROJETO> [--wiki <WIKI>]` — cadastra/edita
  um apelido de projeto.
- `ado alias list` — lista os apelidos cadastrados (apelido, org, projeto, wiki).
- `ado alias remove <apelido>` — remove o cadastro local de um apelido (não afeta nada no
  Azure DevOps).
- `ado alias resolve <apelido>` — imprime `{org, project, wiki}` em JSON (uso interno/depuração).

### Consulta de work items

- `ado work-items <apelido> [--type "User Story"] [--state <estado>] [--title-contains
  <texto>] [--top N] [--json]` — WIQL + batch get, devolve tabela `ID | ESTADO | TÍTULO |
  RESPONSÁVEL` ordenada por alteração mais recente. Tipo padrão `"User Story"`; sem
  `--state`, traz qualquer estado. `--title-contains` filtra por substring do título (WIQL
  `CONTAINS`) — útil para "US sobre X" sem saber os ids de antemão. `--top` limita quantos
  ids entram no batch (padrão 200, teto da API por chamada — projetos com mais de 200 itens
  do tipo/estado pedido precisam de filtro adicional para caber numa chamada só). `--json`
  devolve o payload bruto da API (usar só quando a tabela não for suficiente; custa mais
  tokens).
- `ado work-item <apelido> <id> [--json]` — detalhe de um item: título, tipo, estado,
  responsável, prioridade, link, e Descrição/Critérios de Aceitação convertidos de HTML para
  texto simples (a API devolve esses campos como HTML cheio de `<blockquote>`/`<span>`
  aninhados — não vale a pena o modelo ler isso cru). `--json` devolve o payload bruto.
- `ado tree <apelido> [--type "User Story"] [--feature-contains <texto>]` — mostra a árvore
  real Feature → work item filho (relations da API, não suposição por data/estado) em formato
  de pastas, só para visualizar o que existe **antes de exportar** — não baixa nem grava nada.
  `--feature-contains` filtra pelo título da Feature (mesma sintaxe de `--title-contains`);
  sem filtro, varre todas as Features do projeto (pode ser lento em projetos grandes). Usar
  sempre que `work-items --title-contains` trouxer muitos resultados com título repetido —
  ver caixa de duplicidade de Features logo abaixo.

Exemplo do pedido recorrente do usuário ("pegar as US do settorj"):
```bash
ado work-items settorj --type "User Story"
ado work-item settorj 766254
```

**Atenção a backlog com título duplicado entre Features diferentes.** `--title-contains`
casa por substring, então um termo genérico (ex. "Usuário") pode trazer dezenas de resultados
de Features distintas com o mesmo nome recriadas em datas diferentes (achado real no projeto
`0391.2_RJ_SES_SUSTENTACAO`: rodando `ado tree settorj --feature-contains "Usuário"`, mais de
10 Features distintas chamadas "Usuário"/"Usuários"/"Usuários SES", cada uma com seu próprio
cluster de US com títulos repetidos — mesmo padrão em "Unidade").

**Verificar o `System.Parent` de TODO id antes de exportar em massa — nunca só de uma
amostra.** Erro real cometido no desenho desta skill: ao montar um cluster de 9 ids para
exportar, só o `System.Parent` de 6 deles foi checado; os outros 3 foram incluídos por
estarem adjacentes na mesma janela de data/estado (`Ready`, alterados no mesmo período) — 2
desses 3 pertenciam a Features **diferentes** (um deles a uma Feature isolada de um único
item, quase certamente um item avulso/duplicado, não parte do fluxo). Isso só foi descoberto
depois de já ter exportado e gravado os arquivos, exigindo apagar os dois errados.

**Fluxo correto, use `ado tree` em vez de amostragem:**
```bash
ado tree settorj --feature-contains "Usuário"
```
Isso já agrupa certo (relations reais da API, não suposição por data/estado) — a saída mostra
uma pasta por Feature com seus filhos reais embaixo. Escolha o cluster pelo nome/estado da
Feature (a mais recente e com estado `Active`/todos os filhos `Ready` costuma ser a vigente;
Features antigas do mesmo nome tendem a ser planejamento superado, não limpo do backlog) e
só então rode `export-workitems --ids` com os ids exatos daquele cluster — nunca com
`--title-contains` sozinho quando `ado tree` já revelou mais de uma Feature com nome parecido.

### Exportação de work items para Markdown

- `ado export-workitems <apelido> <destino> --ids <id1,id2,...>` — exporta uma lista
  explícita de ids: um `.md` por item em `<destino>/docs/` (`<id>-<slug-do-título>.md`, com
  título, tipo, estado, responsável, link, Descrição e Critérios de Aceitação já convertidos
  de HTML para texto), e baixa as imagens referenciadas nesses campos (anexos do work item)
  para `<destino>/assets/`, com os links do markdown reescritos para `../assets/<arquivo>`.
  Uso recomendado depois de já ter desambiguado quais ids exportar (ver caixa acima sobre
  título duplicado entre Features).
- `ado export-workitems <apelido> <destino> --title-contains <texto> [--type TIPO] [--state
  ESTADO] [--top N]` — atalho que já resolve os ids via WIQL antes de exportar; só usar
  quando o filtro não for ambíguo (poucos resultados, sem título repetido entre Features
  diferentes).

```bash
ado export-workitems settorj ~/dev/settorj --ids 766254,766255,766256,767274,770363,770364,770365,786581,787627
```

### Exportação de documentação (wiki)

- `ado wikis <apelido>` — lista as wikis do projeto (nome, tipo, repo git). Rodar antes do
  primeiro `export-wiki` para descobrir o valor de `--wiki` (ou cadastrar via `alias add
  ... --wiki <nome>` para não precisar passar toda vez).
- `ado export-wiki <apelido> <path-da-wiki> <destino-local> [--wiki <nome-da-wiki>]` — clona
  (raso) o repositório git por trás da wiki, copia as páginas `.md` cujo caminho bate com o
  prefixo pedido para `<destino>/docs/`, baixa os anexos referenciados (pasta `.attachments`
  do repo) para `<destino>/assets/`, e reescreve os links do markdown para apontar pra lá.
  `<destino-local>` é qualquer caminho na máquina do usuário — normalmente a pasta do projeto
  relacionado, como o próprio usuário decidir no momento do pedido.

```bash
ado wikis settorj
ado export-wiki settorj "Requisitos/Modulo-Usuario" ~/dev/settorj/docs
```

**Limitação conhecida:** a correspondência do path pedido com os nomes de arquivo no
repositório é heurística (sem acento, minúsculo, espaço~hífen — o Azure DevOps normaliza o
título da página pro nome do arquivo). Se não encontrar nada, o script lista as páginas
disponíveis no repositório para ajustar o prefixo. Este comando ainda não foi validado contra
uma wiki real neste ambiente — o projeto usado para desenhar a skill (`0391.2_RJ_SES_SUSTENTACAO`)
não tinha nenhuma wiki provisionada (`ado wikis` retornou vazio); testar contra o primeiro
projeto real que tiver wiki e ajustar o helper (`scripts/export_wiki_helper.py`) se a estrutura
de pastas divergir do esperado.

## Disponibilizar o comando fora da skill

`scripts/init.sh` symlinka em `~/.local/bin` e adiciona alias no `~/.zshrc` **só do `ado`**
(controlado por `scripts/.expose`) — os scripts individuais continuam só como implementação
interna. Idempotente:

```bash
~/.config/ai/skills/azuredevops-api/scripts/init.sh
source ~/.zshrc
```

## Ao apresentar resultados ao usuário

- Preferir `ado work-items`/`ado work-item` sem `--json` — a tabela e o texto já vêm limpos;
  só usar `--json` quando precisar de um campo que a saída padrão não traz.
- Nunca inclua o PAT na resposta final, mesmo que ele apareça num erro de curl (os scripts já
  evitam isso, mas confira antes de colar saída de erro bruta na conversa).
- Se o `<apelido>` não for claro, rode `ado alias list` antes de perguntar ao usuário.
