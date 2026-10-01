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

**Fluxo obrigatório (nunca exportar sem escolher o Epic):**
1. `ado epics <apelido>` — lista os Epics (`ID | ESTADO | TÍTULO | nº de US`). Um projeto Azure
   DevOps costuma reunir vários sistemas, cada um um Epic.
2. **Perguntar ao usuário qual Epic exportar**, mostrando a lista. Nunca inferir o Epic sozinho
   nem exportar o projeto inteiro por padrão — só com `--all`, se o usuário pedir. (Erro real:
   foram exportadas 776 US de todos os sistemas quando o usuário só queria as 143 do Settorj.)
3. (Opcional) `--dry-run` para ver pastas e contagens antes de baixar.
4. `ado export-workitems <apelido> <destino> --epic <id> --layout docs --clean`.

`ado export-workitems <apelido> <destino> <seletor> [opções]` — sem seletor o comando não
exporta: lista os Epics e sai com erro.

- **Seletores:** `--epic <id>` (todas as US descendentes; a pasta do Epic é omitida, o destino
  já é o Epic); `--ids <id1,id2,...>` (lista explícita, depois de desambiguar com `ado tree`);
  `--title-contains <texto>` (só se o filtro não for ambíguo); `--all`. `--type`/`--state`
  restringem; padrão `--type "User Story"`. O `<destino>` relativo é resolvido a partir do
  diretório onde o comando foi chamado.
- **Hierarquia de pastas do Azure:** `<destino>/<Epic>/<Feature>/<id>-<slug>.md` (pais via
  `System.Parent`; irmãos com título igual ganham ` (<id>)`; item sem pai vai para
  `Sem Feature/`). Com `--epic` a pasta do Epic some: `<destino>/<Feature>/...`.
- **Ordem = a do backlog do Azure:** cada pasta recebe índice `NNN_` pelo `StackRank` (mesma
  ordem da tela de backlog, desempate por id; numeração contígua entre as pastas exportadas,
  Features sem item exportado não ocupam número). `--no-order-prefix` desliga. Os arquivos
  dentro da Feature seguem a ordem do id no nome, não a do backlog.
- **`--layout docs`:** `.md` em `<destino>/docs/<Feature>/`, assets em `<destino>/assets/`
  (padrão `flat`: `.md` direto em `<destino>/`). Os links de imagem são relativos ao arquivo
  (`../../assets/<arquivo>`, conforme a profundidade).
- **`--clean`:** remove o que o export anterior gravou e este não regravou (US renomeada,
  movida ou removida), via manifesto `<destino>/.ado-export.json`.
- **`--dry-run`:** mostra pastas e contagens (itens, imagens) sem baixar anexos nem gravar.
- **Conteúdo:** título, tipo, estado, responsável, link, Descrição e Critérios de Aceitação.
  O HTML é convertido por `scripts/html_md.py` (parser real, não regex): listas aninhadas com
  numeração **hierárquica por caminho** (`1.` na raiz, `- 1.1`, `- 1.1.1`...), negrito, itálico,
  links, quebras de linha e tabelas Markdown. O `list-style` do Azure (`a.`/`i.`/`1.`) é
  ignorado de propósito: letras e romanos não ordenam nem se citam bem em texto; o caminho
  numérico sim. O HTML do Azure põe `<ol>` direto dentro de `<ol>` (depois do `</li>`) —
  tratado como sublista do item anterior, herdando o caminho dele.
- **Validação ao fim:** confere todos os links de imagem locais (`N links, 0 quebrados`) e lista
  os anexos não baixados. Anexo de **outra organização** (ex.: `dev.azure.com/SES-RJ/...` em
  item migrado) dá 401 com o PAT da organização do apelido; o link original é mantido no `.md`.
- **Busca em lote:** itens vêm por `workitemsbatch` (200 por chamada), não um GET por item. O
  GET simples de um work item **não** traz `System.Parent` em `fields`; só o batch com
  `fields` explícito traz.

**Armadilha WIQL já tratada:** a consulta de descendentes (`WorkItemLinks ... MODE
(Recursive)`) devolve também os nós intermediários (Features), mesmo filtrando o tipo no
`WHERE`. `--epic` e a contagem do `ado epics` filtram o `System.WorkItemType` depois, em lote.
Sintoma de regressão: `.md` de `Tipo: Feature` soltos na raiz do destino, com o mesmo nome das
pastas de Feature, e contagem de US maior que a real. Conferir com `grep -L 'Tipo: User Story'`
nos `.md` exportados.

**Tetos:** `ado work-items` corta em `--top` (200) **com aviso** (`--all` traz tudo);
`ado tree` não tem mais teto de Features.

```bash
ado epics settorj
ado export-workitems settorj US --epic 765941 --layout docs --dry-run
ado export-workitems settorj US --epic 765941 --layout docs --clean
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
