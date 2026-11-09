---
name: wikijs
description: Consulta e edita páginas de uma instância Wiki.js (v2.x) pela API GraphQL, com scripts Node prontos — listar, ler, buscar, mover, atualizar, substituir texto e rodar queries ad-hoc. A URL e o token vêm de variáveis de ambiente ou de um cofre, nunca do código. Use quando o usuário pedir para ler, buscar, criar, mover ou corrigir páginas de uma wiki Wiki.js, ou para explorar o schema GraphQL dela.
---

# Skill: wikijs

**Tipo:** internal

## Visão geral

Wiki.js (v2.x) expõe uma **API GraphQL** em `<WIKIJS_URL>/graphql`. O endpoint aceita `POST` com
`Content-Type: application/json` e corpo `{"query": "...", "variables": {...}}`. A introspecção
(`{ __schema { ... } }`, `{ __type(name: "...") { fields { name } } }`) costuma estar habilitada e
serve para descobrir tipos, campos e argumentos.

Esta skill documenta **a ferramenta**. Nada aqui é específico de uma wiki: a instância é escolhida
por configuração.

## Configuração

| Variável | Para quê |
|---|---|
| `WIKIJS_URL` | **Obrigatória.** URL base da instância, sem barra final (ex.: `https://wiki.exemplo.com`). |
| `WIKIJS_TOKEN` | Token de API (maior prioridade). |
| `WIKIJS_TOKEN_REF` | Só a **referência** do segredo num cofre; os scripts chamam `vault-read "$WIKIJS_TOKEN_REF"` (skill `vault-factory`). |

Ordem de busca do token (a primeira fonte preenchida vence):

1. variável de ambiente `WIKIJS_TOKEN`;
2. arquivo local `~/.claude/secrets/wikijs/token` (permissão `600`), gravado a partir do cofre, sem colar o valor no chat;
3. `WIKIJS_TOKEN_REF` + `vault-read`.

```bash
export WIKIJS_URL='https://wiki.exemplo.com'
export WIKIJS_TOKEN_REF='op://<cofre>/<item>/<campo>'   # ou 'pass:<caminho>', só a referência
```

O header enviado é `Authorization: Bearer <token>`. O token é um **API Token** gerado na própria
instância (Administration → API Access) com os escopos necessários (ex.: `read:pages`,
`write:pages`, `manage:pages`, `write:assets`). Nunca exponha o token em saída, log ou arquivo
versionado.

## Scripts (Node 18+, usam `fetch` nativo)

Ficam em `scripts/` desta skill e leem URL e token pela configuração acima. **Prefira-os a montar
`curl` à mão.**

```bash
SCRIPTS="$HOME/.config/ai/skills/wikijs/scripts"
node "$SCRIPTS/list-pages.js"                      # lista páginas (id, pub/draft, path)
node "$SCRIPTS/page.js <id|path>"                  # página completa (conteúdo + tags)
node "$SCRIPTS/search.js <termo>"                  # busca só em título/path (NÃO no conteúdo)
node "$SCRIPTS/find.js <texto>"                    # páginas cujo conteúdo contém o texto
node "$SCRIPTS/move.js <id> <destinationPath>"     # move página
node "$SCRIPTS/update.js <id> [--content <txt>] [--content-file <arq>] [--title <t>] [--published true|false] [--tags '<json>']"
node "$SCRIPTS/replace.js <texto> <substituto> [ids...]"   # substitui texto no conteúdo (todas ou só os ids)
node "$SCRIPTS/gql.js '<query>'"                   # query/mutation ad-hoc (ou arquivo .graphql)
```

Autoteste (uma vez por sessão): `node "$SCRIPTS/list-pages.js"`. Se falhar (token, rede, URL), pare
e informe o usuário.

## Quirks conhecidos do Wiki.js v2

- **`pages.update` exige `content` e `tags` juntos.** Sem um deles o servidor retorna erro
  (`PageEmptyContent 6004`). `update.js` já preenche o que faltar com o valor atual.
- **`pages.update` sem `isPublished` pode despublicar a página** (vira draft). `replace.js` usa
  `pages.update`, então também despublica o que alterar. Depois de editar/substituir em lote,
  republique (`update.js <id> --published true`) e confira o status.
- **`pages.move` pode despublicar e trocar o título** pelo último segmento do path. O
  comportamento não é determinístico: confira título e status após mover e ajuste com `--title`.
- **`pages.create` exige `description` e `isPrivate`** além de `content`/`tags`/`path`/`title`/`locale`.
- **`search.js` não busca no conteúdo:** `pages.search` casa só título/path. Resultado vazio não
  prova ausência; para achar texto no corpo use `find.js` (varre página a página).
- **`singleByPath` exige `locale`** (use o locale da instância, em geral `en`).
- **`pages.tree` pode devolver só o nível superior.** Para enumerar páginas use `pages.list`.
- **Mover página não atualiza links** em outras páginas: corrija com `replace.js antigo novo`.
- **Âncoras de sumário:** o renderizador gera IDs de título com prefixo `h-` (`#h-1-introdução`);
  links `(#1-introdução)` não funcionam. Confira o campo `render` da página.
- **Git Bash/MSYS converte argumentos que começam com `/`** em caminhos do Windows; prefixe com
  `MSYS_NO_PATHCONV=1` ao chamar `replace.js "/x/" "/y/"`.
- **Upload de imagem:** não há mutation GraphQL. O upload é `POST <WIKIJS_URL>/u` (multipart,
  `Authorization: Bearer`, escopo `write:assets`). O `folderId` vai num campo `mediaUpload` com JSON
  (`{"folderId":2}`), **antes** do arquivo, que vai noutro campo também chamado `mediaUpload`. Um
  arquivo por requisição; sucesso é `200` com texto `ok`.
- **Leitura de conteúdo exige token** em instâncias que não são públicas; `pages.list` e
  `pages.search` podem ser públicos, `pages.single*` costuma dar `PageViewForbidden 6013`.

## Exemplos

```graphql
{ pages { list(orderBy: TITLE) { id path title isPublished locale tags { tag } } } }

{ pages { search(query: "termo") { results { id path title } totalHits } } }

{ pages { singleByPath(path: "pasta/pagina", locale: "en") { id title content } } }

mutation {
  pages {
    create(content: "...", description: "...", editor: "markdown", isPublished: true,
           isPrivate: false, path: "pasta/pagina", tags: [], title: "Título", locale: "en") {
      responseResult { succeeded errorCode slug message }
      page { id path title }
    }
  }
}
```

Toda mutation devolve `responseResult { succeeded errorCode slug message }`.

Para descobrir argumentos de qualquer tipo:

```graphql
{ __type(name: "PageQuery") { fields { name args { name type { name kind ofType { name } } } } } }
```

Tipos úteis: `PageQuery`, `PageMutation`, `Page`, `UserQuery`, `GroupQuery`, `AssetQuery`,
`SystemQuery`, `SiteQuery`, `NavigationQuery`.

## Cuidados

- A wiki pode conter informação sensível: não exponha conteúdo restrito nem tokens em saída.
- Antes de qualquer escrita em lote (`replace.js`, `update.js`, `move.js`), confirme o escopo com o
  usuário e prefira testar em uma página.
- Ao descobrir um quirk novo da API, registre-o aqui (sem copiar token nem dados de instância).
