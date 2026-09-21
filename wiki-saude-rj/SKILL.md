---
name: wiki-saude-rj
description: Interage com a API GraphQL do Wiki.js da SES-RJ (https://wiki.saude.rj.gov.br). Consulta páginas, busca conteúdo, lê metadados, e faz operações autenticadas na wiki interna da SES-RJ.
---

# Skill: wiki-saude-rj

## Visão geral

A wiki `https://wiki.saude.rj.gov.br/` é uma instância **Wiki.js** (v2.x). Ela expõe uma **API GraphQL** no endpoint:

```
https://wiki.saude.rj.gov.br/graphql
```

- O **GraphQL Playground** (explorador interativo com schema docs) abre em `https://wiki.saude.rj.gov.br/graphql` no navegador.
- O endpoint aceita requisições `POST` com `Content-Type: application/json` e corpo `{"query": "...", "variables": {...}}`.
- A introspecção de schema (`{ __schema { ... } }` ou `{ __type(name: "...") { fields { name } } }`) está habilitada e pode ser usada para explorar tipos e campos a qualquer momento.

## Autenticação

A API usa token. O cabeçalho a ser enviado é:

```
Authorization: Bearer <API_TOKEN>
```

Formas de obter/definir o token:

1. **API Token (recomendado para máquina-a-máquina):** gerado na wiki em **Administration → API Access**. O token exige escopos de permissão (ex.: `pages:read`, `pages:write`) para cada recurso.
2. **Login via mutation:** as estratégias ativas da instância são `local` e `RHBK` (SSO via Keycloak/Red Hat build of Keycloak). A mutation `authentication.login` devolve um JWT:
   ```graphql
   mutation {
     authentication {
       login(email: "usuario@saude.rj.gov.br", password: "****") {
         responseResult { succeeded message }
         jwt
       }
     }
   }
   ```
   O `jwt` retornado deve ser usado como `Authorization: Bearer <jwt>`.

### Como o agente deve obter o token

- O token desta instância fica no **1Password** (item **Envs kilo Skills**, vault **`Services IA`**, conta Personal; campo `wiki_saude_rj_token`). Os scripts (`lib.js`) buscam automaticamente, nesta ordem: variável de ambiente `WIKI_SAUDE_RJ_TOKEN` → cache local `~/.claude/secrets/wiki-saude-rj/token` (permissão `600`) → `op read "op://Services IA/Envs kilo Skills/wiki_saude_rj_token"` (via integração de CLI do app desktop do 1Password — sem service account; nesta máquina o desbloqueio é por biometria/app). Para materializar manualmente:

  ```bash
  mkdir -p ~/.claude/secrets/wiki-saude-rj
  op read "op://Services IA/Envs kilo Skills/wiki_saude_rj_token" > ~/.claude/secrets/wiki-saude-rj/token
  chmod 600 ~/.claude/secrets/wiki-saude-rj/token
  ```

- Nunca exponha o token em outputs, logs ou arquivos versionados.

## Scripts utilitários (Node.js, recomendado)

Existe um conjunto de scripts prontos em `~/.config/ai/skills/wiki-saude-rj/scripts/` (symlink em `~/.claude/skills/wiki-saude-rj`) que leem o token automaticamente do arquivo de segredos (via `lib.js`). Requer **Node 18+** (usa `fetch` nativo). **Sempre prefira usar esses scripts** em vez de escrever requisições `curl` manualmente.

```bash
SCRIPTS="$HOME/.config/ai/skills/wiki-saude-rj/scripts"
node "$SCRIPTS/list-pages.js"                                   # lista todas as páginas (id, status pub/draft, path)
node "$SCRIPTS/page.js <id|path>"                               # detalhes completos de uma página (conteúdo + tags)
node "$SCRIPTS/page.js 24"
node "$SCRIPTS/page.js desenvolvimento/gitlab/runbook/configurar-ssh"
node "$SCRIPTS/search.js <termo>"                               # busca full-text em páginas
node "$SCRIPTS/move.js <id> <destinationPath>"                  # move página (locale en implícito)
node "$SCRIPTS/update.js <id> [--content <texto>] [--content-file <arquivo>] [--title <titulo>] [--published true|false] [--tags '<json>']"
node "$SCRIPTS/replace.js <texto> <substituto> [ids...]"        # substitui texto no conteúdo das páginas (todas ou só os ids)
node "$SCRIPTS/find.js <texto>"                                 # encontra páginas cujo conteúdo contém o texto
node "$SCRIPTS/gql.js '<query>'"                                # executa query GraphQL ad-hoc (ou arquivo .graphql)
```

Exemplos de uso:

```bash
node "$SCRIPTS/update.js 24 --published true"                      # publicar/despublicar preservando conteúdo e tags
node "$SCRIPTS/update.js 24 --content-file novo.txt"               # substituir conteúdo a partir de arquivo (preserva tags)
node "$SCRIPTS/replace.js desenvovolvimento desenvolvimento"       # corrigir links em todo o conteúdo
node "$SCRIPTS/move.js 18 desenvolvimento/gitlab/runbook/configurar-ssh"
node "$SCRIPTS/gql.js '{ system { info { currentVersion } } }'"
```

**Atenção (descoberto em 2026-08-12):** a mutation `pages.update` exige que `content` **e** `tags` sejam passados juntos — sem um deles o servidor retorna erro (`PageEmptyContent 6004` ou `Cannot read properties of undefined (reading 'map')`). Os scripts `update.js` e `replace.js` já tratam isso automaticamente (lêem os tags atuais e preservam).

**Âncoras de sumário (descoberto em 2026-08-12):** o renderizador desta instância gera IDs de títulos com prefixo `h-` (ex.: `id="h-1-introdução"`). Links de sumário escritos como `(#1-introdução)` **não funcionam** — use `(#h-1-introdução)`. Dica: para conferir as âncoras reais, consulte o campo `render` da página (`node page.js <id>` não mostra; use `node gql.js '{ pages { single(id: 26) { render } } }'`).

**`pages.update` sem `isPublished` despublica a página (descoberto em 2026-08-21):** ao atualizar apenas `content`/`tags` via `pages.update`, o servidor **muda a página para draft** (`isPublished: false`). Sempre conferir o status após atualizar e republicar com `--published true` quando necessário. Ex.: `node update.js 24 --published true`.

**Página nova de runbook ficou draft ao criar com `pages.create` (2026-08-21):** não ocorreu — `pages.create` com `isPublished: true` publicou normalmente. Apenas `pages.update` apresentou o comportamento de despublicar.

**`pages.move` e `replace.js` também despublicam (descoberto em 2026-08-21):** `pages.move` **despublica a página movida** e ainda **troca o título** para o último segmento do path (ex.: mover para `.../runbook` deixa o título como `runbook`). Já `replace.js` (que usa `pages.update` sem `isPublished`) despublica as páginas alteradas. Após migrações/substituições, **sempre republicar** as páginas afetadas (`node update.js <id> --published true`). Também conferir o título após mover e ajustar com `--title`.

**Exceção observada (2026-09-10):** ao mover a página 37 (`desenvolvimento/diretrizes/padrao-documentacao-wiki` → `supinf/diretrizes/padrao-documentacao-wiki`), o `pages.move` **preservou o título original** e manteve a página **publicada** (`isPublished: true`). O comportamento de despublicar/renomear não é determinístico — sempre verificar título e status após mover e republicar por precaução.

**MSYS/Git Bash converte argumentos com `/` no início (descoberto em 2026-08-21):** ao chamar `replace.js` com search/replace começando por `/` (ex.: `/plataforma/openshift/runbooks/`), o Git Bash converte o argumento para um path do Windows (`C:/Program Files/Git/...`), fazendo a substituição não encontrar nada. Prefixar com `MSYS_NO_PATHCONV=1`: `MSYS_NO_PATHCONV=1 node replace.js "/x/" "/y/"`.

**Back-link "Voltar para" no topo das páginas (padrão adotado em 2026-08-21):** toda página da wiki tem, no início do conteúdo, um link HTML alinhado à direita para o índice pai:
`<p align="right"><a href="/<path-do-indice-pai>">← Voltar para <label></a></p>`
O renderizador mantém o `align="right"` e marca o link como `is-valid-page`. A home não leva back-link.

**Breadcrumb e páginas de pasta (descoberto em 2026-08-21):** o breadcrumb do Wiki.js gera um link para **cada segmento de pasta** do path (ex.: para `desenvolvimento/pass/runbook/foo` → `desenvolvimento`, `pass`, `runbook`). O segmento só não dá 404 se **existir uma página no path exato da pasta** — a convenção `<pasta>/home` **não resolve** nesta instância (testado: `/plataforma` continuou 404 com `plataforma/home`). Para resolver, a página de índice deve ter path igual ao da pasta: `pages.move(id, "plataforma")`, `"desenvolvimento"`, `"desenvolvimento/diretrizes"`, `"plataforma/openshift"`, etc. Páginas-folder coexistem com filhos (ex.: página `plataforma/openshift/runbook` + filhos `plataforma/openshift/runbook/*`). Após mover, atualizar referências antigas (`/desenvolvimento/index` → `/desenvolvimento` etc.) com `replace.js` + `MSYS_NO_PATHCONV=1`.


## Automanutenção (obrigatório)

Esta skill **cria seus próprios scripts e se atualiza**. Siga este fluxo em **toda** execução:

### 1. Garantir que os scripts existem (antes de usar a API)

1. Verifique se a pasta `~/.config/ai/skills/wiki-saude-rj/scripts/` existe e contém todos os arquivos listados abaixo (`lib.js`, `list-pages.js`, `page.js`, `search.js`, `move.js`, `update.js`, `replace.js`, `find.js`, `gql.js`).
2. Se faltar algum (ou estiver desatualizado em relação ao código embutido nesta skill na seção "Código-fonte dos scripts"), **recrie o arquivo** usando o `write` tool com exatamente o código embutido abaixo.
3. Crie a pasta com `mkdir -p` se necessário.

### 2. Autoteste (uma vez por sessão)

Antes de executar qualquer operação, confirme que a API está acessível:

```bash
node "$HOME/.config/ai/skills/wiki-saude-rj/scripts/list-pages.js"
```

Se listar as páginas, token e scripts estão OK. Se falhar (token expirado, rede, erro), pare e informe o usuário.

### 3. Auto-atualização (depois de usar a API)

Sempre que, durante o trabalho, você descobrir algo novo sobre a API — e **antes** de encerrar a resposta — atualize **esta SKILL.md** e/ou os scripts:

- **Novos campos/argumentos/queries/mutations** descobertos → adicione/ajuste exemplos nas seções relevantes.
- **Novos erros/quirks** (ex.: `pages.update` exige content+tags) → registre na seção de erros ou nos avisos.
- **Correção/melhoria de script** → atualize o arquivo `.js` **e** o código embutido abaixo, mantendo ambos idênticos.
- **Token/escopos alterados** → registre aqui (nunca copie o valor do token para a skill).
- Atualize a data de qualquer validação feita hoje.

### Código-fonte dos scripts

Fonte canônica (mantenha os arquivos em `scripts\` idênticos a estes blocos):

#### scripts/lib.js
```js
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const TOKEN_PATH = path.join(os.homedir(), '.claude', 'secrets', 'wiki-saude-rj', 'token');
const OP_REF = 'op://Services IA/Envs kilo Skills/wiki_saude_rj_token';
const ENDPOINT = 'https://wiki.saude.rj.gov.br/graphql';

function fetchFrom1Password() {
  try {
    // Depende da integração de CLI do app desktop do 1Password (biometria/desbloqueio),
    // sem service account — é o mecanismo padrão numa estação de trabalho pessoal.
    const token = execSync(`op read "${OP_REF}"`, { encoding: 'utf8' }).trim();
    if (!token) throw new Error('vazio');
    fs.mkdirSync(path.dirname(TOKEN_PATH), { recursive: true });
    fs.writeFileSync(TOKEN_PATH, token + '\n', { mode: 0o600 });
    return token;
  } catch (e) {
    return null;
  }
}

function loadToken() {
  if (process.env.WIKI_SAUDE_RJ_TOKEN) return process.env.WIKI_SAUDE_RJ_TOKEN;
  try {
    return fs.readFileSync(TOKEN_PATH, 'utf8').trim();
  } catch (e) {
    const token = fetchFrom1Password();
    if (!token) {
      console.error(`Token não encontrado em ${TOKEN_PATH}, na env WIKI_SAUDE_RJ_TOKEN nem no 1Password (${OP_REF}). Verifique o item "Envs kilo Skills".`);
      process.exit(1);
    }
    return token;
  }
}

const TOKEN = loadToken();

async function gql(query, variables) {
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + TOKEN },
    body: JSON.stringify({ query, variables })
  });
  const json = await res.json();
  if (json.errors) {
    const msgs = json.errors.map(e => (e.message || JSON.stringify(e))).join('; ');
    throw new Error('GraphQL error: ' + msgs);
  }
  return json.data;
}

module.exports = { TOKEN, ENDPOINT, gql };
```

#### scripts/list-pages.js
```js
const { gql } = require('./lib');

(async () => {
  const data = await gql('{ pages { list { id path title locale isPublished isPrivate createdAt updatedAt } } }');
  for (const p of data.pages.list) {
    const status = p.isPublished ? 'pub' : 'draft';
    console.log(`${p.id}\t${status}\t${p.path}`);
  }
})();
```

#### scripts/page.js
```js
const { gql } = require('./lib');

(async () => {
  const arg = process.argv[2];
  if (!arg) {
    console.error('Uso: node page.js <id|path>');
    process.exit(1);
  }
  const fields = 'id path title description content tags { tag } isPublished isPrivate locale createdAt updatedAt';
  const data = /^\d+$/.test(arg)
    ? await gql(`{ pages { single(id: ${arg}) { ${fields} } } }`)
    : await gql(`{ pages { singleByPath(path: ${JSON.stringify(arg)}, locale: "en") { ${fields} } } }`);
  const result = /^\d+$/.test(arg) ? data.pages.single : data.pages.singleByPath;
  console.log(JSON.stringify(result, null, 2));
})();
```

#### scripts/search.js
```js
const { gql } = require('./lib');

(async () => {
  const term = process.argv[2];
  if (!term) {
    console.error('Uso: node search.js <termo>');
    process.exit(1);
  }
  const data = await gql(`{ pages { search(query: ${JSON.stringify(term)}) { results { id path title description } totalHits } } }`);
  console.log(`Total de resultados: ${data.pages.search.totalHits}`);
  for (const r of data.pages.search.results) {
    console.log(`${r.id}\t${r.path}\t${r.title}`);
  }
})();
```

#### scripts/move.js
```js
const { gql } = require('./lib');

(async () => {
  const id = process.argv[2];
  const dest = process.argv[3];
  if (!id || !dest) {
    console.error('Uso: node move.js <id> <destinationPath>');
    process.exit(1);
  }
  const data = await gql(`mutation { pages { move(id: ${id}, destinationPath: ${JSON.stringify(dest)}, destinationLocale: "en") { responseResult { succeeded errorCode slug message } } } }`);
  const r = data.pages.move.responseResult;
  console.log(r.succeeded ? `OK: página ${id} movida para ${dest}` : `FALHOU: ${r.message}`);
  process.exit(r.succeeded ? 0 : 1);
})();
```

#### scripts/update.js
```js
const fs = require('fs');
const { gql } = require('./lib');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

(async () => {
  const id = process.argv[2];
  if (!id) {
    console.error('Uso: node update.js <id> [--content <texto>] [--content-file <arquivo>] [--title <titulo>] [--published true|false] [--tags <json>]');
    process.exit(1);
  }
  const cur = await gql(`{ pages { single(id: ${id}) { title content tags { tag } isPublished } } }`);
  const p = cur.pages.single;

  const content = arg('--content') !== undefined
    ? arg('--content')
    : (arg('--content-file') !== undefined ? fs.readFileSync(arg('--content-file'), 'utf8') : p.content);
  const tags = arg('--tags') !== undefined ? JSON.parse(arg('--tags')) : p.tags.map(t => t.tag);

  const fields = { content, tags };
  if (arg('--title') !== undefined) fields.title = arg('--title');
  if (arg('--published') !== undefined) fields.isPublished = arg('--published') === 'true';

  const parts = Object.entries(fields)
    .map(([k, v]) => `${k}: ${JSON.stringify(v)}`)
    .join(', ');

  const data = await gql(`mutation { pages { update(id: ${id}, ${parts}) { responseResult { succeeded errorCode slug message } } } }`);
  const r = data.pages.update.responseResult;
  console.log(r.succeeded ? `OK: página ${id} atualizada` : `FALHOU: ${r.message}`);
  process.exit(r.succeeded ? 0 : 1);
})();
```

#### scripts/replace.js
```js
const { gql } = require('./lib');

(async () => {
  const search = process.argv[2];
  const replace = process.argv[3];
  if (!search || replace === undefined) {
    console.error('Uso: node replace.js <texto> <substituto> [ids...]');
    console.error('Sem ids, verifica todas as páginas. Com ids, verifica somente as páginas indicadas.');
    process.exit(1);
  }
  const ids = process.argv.slice(4).map(Number);
  let pages;
  if (ids.length) {
    pages = ids;
  } else {
    const data = await gql('{ pages { list { id } } }');
    pages = data.pages.list.map(p => p.id);
  }

  let total = 0;
  for (const id of pages) {
    const data = await gql(`{ pages { single(id: ${id}) { content tags { tag } } } }`);
    const p = data.pages.single;
    const occurrences = (p.content.split(search).length - 1);
    if (occurrences === 0) continue;
    const newContent = p.content.split(search).join(replace);
    const tags = p.tags.map(t => t.tag);
    const upd = await gql(`mutation { pages { update(id: ${id}, content: ${JSON.stringify(newContent)}, tags: ${JSON.stringify(tags)}) { responseResult { succeeded errorCode slug message } } } }`);
    const r = upd.pages.update.responseResult;
    if (!r.succeeded) {
      console.error(`página ${id}: FALHOU - ${r.message}`);
      process.exitCode = 1;
      continue;
    }
    console.log(`página ${id}: ${occurrences} ocorrência(s) substituída(s)`);
    total += occurrences;
  }
  console.log(`Total: ${total} ocorrência(s) substituída(s) em ${pages.length} página(s) verificada(s).`);
})();
```

#### scripts/find.js
```js
const { gql } = require('./lib');

(async () => {
  const text = process.argv[2];
  if (!text) {
    console.error('Uso: node find.js <texto>');
    process.exit(1);
  }
  const data = await gql('{ pages { list { id path } } }');
  const pages = data.pages.list;
  const hits = [];
  for (const p of pages) {
    const d = await gql(`{ pages { single(id: ${p.id}) { content } } }`);
    const c = d.pages.single.content || '';
    const n = c.split(text).length - 1;
    if (n > 0) hits.push({ id: p.id, path: p.path, occurrences: n });
  }
  console.log(JSON.stringify(hits, null, 1));
})();
```

#### scripts/gql.js
```js
const fs = require('fs');
const { gql } = require('./lib');

(async () => {
  const arg = process.argv[2];
  if (!arg) {
    console.error('Uso: node gql.js "<query>" | node gql.js <arquivo.graphql>');
    process.exit(1);
  }
  const query = fs.existsSync(arg) ? fs.readFileSync(arg, 'utf8') : arg;
  const data = await gql(query);
  console.log(JSON.stringify(data, null, 2));
})();
```

## Acesso público vs. restrito (validação feita em 2026-08-12)

| Query | Público | Observação |
|---|---|---|
| `pages.list` | ✅ Sim | Lista todas as páginas com metadados |
| `pages.search` | ✅ Sim | Busca full-text |
| `authentication.activeStrategies` | ✅ Sim | Estratégias SSO ativas |
| `localization.locales` | ✅ Sim | Locais disponíveis |
| Introspecção `__schema`/`__type` | ✅ Sim | Schema completo |
| `pages.single` / `pages.singleByPath` | ❌ Não | Erro `PageViewForbidden 6013` |
| `site.config`, `navigation.tree`, `system.info`, `groups.list`, `assets.*`, `users.*` | ❌ Não | Erro `Forbidden` |

**Importante:** mesmo para páginas públicas (ex.: `home`), o conteúdo (`content`) **não** é retornado sem token — a instância exige autenticação para leitura de conteúdo via API. Qualquer consulta de conteúdo exige `Authorization: Bearer`.

O locale da instância é `en` (obrigatório em `singleByPath`) e a página inicial está em `path: "home"`.

## Estrutura de caminhos (paths) — convenção da wiki

A wiki organiza as páginas em **paths aninhados** sob pastas de nível superior. Use esta
convenção ao **criar/mover** páginas (validação em 2026-08-20):

```
desenvolvimento/                          # documentação de desenvolvimento (top-level)
├── <ferramenta>/                         # ex.: pass, passbolt, gitlab, template-ses
│   ├── runbook/<nome-do-runbook>         # runbooks (passo a passo)
│   └── kb/<nome>                         # artigos de knowledge base
plataforma/                               # documentação de plataforma (top-level)
└── <ferramenta>/...
```

Exemplos reais:

- `desenvolvimento/pass/runbook/instalacao-configuracao-gopass-pass`
- `desenvolvimento/passbolt/runbook/instalacao-configuracao-passbolt-cli`
- `desenvolvimento/gitlab/runbook/configurar-ssh`
- `plataforma/openshift/runbooks`

Regras observadas:

- **`pages.create`/`pages.move` aceitam paths aninhados** — as pastas intermediárias
  (`desenvolvimento/pass/runbook/...`) são criadas automaticamente quando não existem; não é
  preciso criar pasta antes da página.
- **`pages.tree` retorna apenas os diretórios de nível superior** (`desenvolvimento`,
  `plataforma`, `home`), mesmo com o argumento `path` ou `mode: ALL/FOLDERS` — **não** lista as
  pastas intermediárias (`pass`, `runbook`, etc.). Para enumerar páginas use `pages.list`
  (retorna o `path` completo) ou `pages.search`.
- Ao renomear/mover uma página, links de outras páginas para o path antigo **não** são
  atualizados automaticamente — use `replace.js` (ex.: `node replace.js antigo novo`).

## Exemplos de consulta

### Listar todas as páginas (público)

```graphql
{
  pages {
    list(orderBy: TITLE) {
      id
      path
      title
      description
      contentType
      locale
      isPublished
      isPrivate
      createdAt
      updatedAt
      tags { tag }
    }
  }
}
```

```bash
curl -s -X POST https://wiki.saude.rj.gov.br/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ pages { list { id path title } } }"}'
```

### Buscar páginas (público)

```graphql
{
  pages {
    search(query: "openshift") {
      results { id path title description }
      totalHits
    }
  }
}
```

### Ler conteúdo de uma página (requer token)

Por ID:
```graphql
{
  pages {
    single(id: 3) {
      id
      path
      title
      content
      render
      createdAt
      updatedAt
      tags { tag }
    }
  }
}
```

Por caminho (locale obrigatório):
```graphql
{
  pages {
    singleByPath(path: "plataforma/openshift/runbooks", locale: "en") {
      id
      path
      title
      content
    }
  }
}
```

### Árvore de páginas (requer token; `mode` e `locale` obrigatórios)

> ⚠️ Nesta instância, `pages.tree` retorna **apenas os diretórios de nível superior**
> (depth 1: `desenvolvimento`, `plataforma`, `home`) — não lista pastas intermediárias nem
> páginas aninhadas, mesmo passando `path`. Para listar páginas use `pages.list`/`pages.search`.

```graphql
{
  pages {
    tree(mode: FOLDERS, locale: "en") {
      id
      path
      depth
      title
      isFolder
      isPrivate
      parent { id path }
      pageId
    }
  }
}
```

### Metadados do sistema (requer token)

```graphql
{
  system {
    info {
      currentVersion
      pagesTotal
      usersTotal
      groupsTotal
      dbType
      hostname
    }
  }
  site {
    config { title description host }
  }
}
```

### Grupos e usuários (requer token)

```graphql
{ groups { list { id name isSystem userCount permissions } } }
{ users { list { id name email isActive } } }
```

## Exemplos de mutação (requerem token com escopos de escrita)

### Criar página

> ⚠️ (descoberto em 2026-08-20) A mutation `pages.create` **exige** `description` (String!) e
> `isPrivate` (Boolean!) além de `content`/`tags` — sem eles o servidor retorna
> `Field "create" argument "description" of type "String!" is required`.

```graphql
mutation {
  pages {
    create(
      content: "Conteúdo em Markdown",
      description: "Breve descrição da página",
      editor: "markdown",
      isPublished: true,
      isPrivate: false,
      path: "desenvolvimento/pass/runbook/instalacao-configuracao-gopass-pass",
      tags: ["runbook"],
      title: "Runbook — Gopass e Pass",
      locale: "en"
    ) {
      responseResult { succeeded errorCode slug message }
      page { id path title }
    }
  }
}
```

### Atualizar página

```graphql
mutation {
  pages {
    update(
      id: 3,
      title: "Novo título",
      content: "Novo conteúdo",
      isPublished: true
    ) {
      responseResult { succeeded errorCode slug message }
      page { id path title }
    }
  }
}
```

> ⚠️ A mutation `pages.update` **exige** `content` e `tags` juntos (ver seção "Scripts utilitários"). Se for alterar só um campo, envie o valor atual do outro também.

### Mover página

```graphql
mutation {
  pages {
    move(id: 18, destinationPath: "desenvolvimento/gitlab/runbook/configurar-ssh", destinationLocale: "en") {
      responseResult { succeeded errorCode slug message }
    }
  }
}
```
`move` altera apenas o path da página. Links internos de outras páginas **não** são atualizados automaticamente — use `replace.js` no conteúdo das páginas afetadas (ex.: `node replace.js desenvovolvimento desenvolvimento`).

### Fazer login (para obter JWT)

```graphql
mutation {
  authentication {
    login(email: "usuario@saude.rj.gov.br", password: "****") {
      responseResult { succeeded message }
      jwt
    }
  }
}
```

## Tratamento de erros

Toda mutation retorna um objeto `responseResult` do tipo `ResponseStatus`:

```graphql
type ResponseStatus {
  succeeded: Boolean!
  errorCode: Int!
  slug: String!
  message: String
}
```

Erros comuns encontrados nesta instância:

| Erro | Significado | Ação |
|---|---|---|
| `Forbidden` | Falta token ou token sem escopo | Enviar `Authorization: Bearer` com escopos corretos |
| `PageViewForbidden 6013` | Sem permissão para ver a página | Usar token; verificar permissões de grupo |
| `AuthLoginFailed 1002` | E-mail/senha inválidos no login | Revisar credenciais |
| `AuthGenericError 1001` | Falha inesperada no login | Tentar novamente |
| `GRAPHQL_VALIDATION_FAILED` | Query mal formada / campo inexistente | Consultar a introspecção para corrigir campos/args |
| `argument "description" of type "String!" is required` | `pages.create` sem campos obrigatórios | Enviar `description` e `isPrivate` na mutation (ver "Criar página") |

## Dicas

- Para descobrir campos e argumentos válidos de qualquer tipo, consulte a introspecção:
  ```graphql
  { __type(name: "PageQuery") { fields { name args { name type { name kind ofType { name } } } } } }
  ```
  Tipos úteis: `PageQuery`, `PageMutation`, `Page`, `UserQuery`, `GroupQuery`, `AssetQuery`, `SystemQuery`, `SiteQuery`, `NavigationQuery`.
- Respostas de `pages.list` retornam metadados (sem `content`); para o conteúdo completo use `pages.single`/`singleByPath`.
- As datas vêm em UTC (`createdAt`, `updatedAt`).
- Prefira usar variáveis GraphQL em vez de valores hardcoded em queries complexas.
- Cuidado: a wiki é da SES-RJ e pode conter informações sensíveis; não exponha conteúdo restrito ou tokens em outputs.
