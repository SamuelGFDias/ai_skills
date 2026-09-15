---
name: cronograma-saude-rj-api
description: Consulta e integra com a API REST do sistema Cronograma da SES-RJ (https://cronograma.saude.rj.gov.br/api), que gerencia projetos, categorias, atividades, calendário mensal, snapshots e importação de planilhas XLSX. Autenticação é via Keycloak com sessão por cookie (não é Bearer token). Documenta todos os endpoints, parâmetros e a técnica para descobrir campos de DTOs que não vêm documentados no Swagger. Use quando o usuário pedir para consultar, integrar, testar ou automatizar chamadas a essa API.
---

# Skill: Cronograma API (SES-RJ)

**Tipo:** internal

## Quando executar

- Pedidos para consultar, testar ou integrar com `https://cronograma.saude.rj.gov.br/api`.
- Automatizar login, criação/edição de projetos, categorias, atividades ou snapshots nesse sistema.
- Consultar ou gerar código cliente (curl, HTTP client, etc.) para essa API.
- Reanalisar/atualizar esta skill quando a spec do Swagger mudar (ver seção "Como atualizar esta skill").

## Visão geral

- **Base URL:** `https://cronograma.saude.rj.gov.br/api`
- **Título:** Cronograma API — "API do sistema de cronograma" (versão `0.1.0` na última checagem)
- **Docs interativa (Swagger UI):** `/api/docs` (SPA — não dá pra extrair conteúdo via WebFetch/curl, é só a shell HTML)
- **Spec OpenAPI crua (JSON):** `/api/docs-json` — **esta é a fonte confiável**, buscar com `curl`, não com WebFetch (o modelo resumidor do WebFetch trunca/omite os `schemas`). Ex: `curl -s https://cronograma.saude.rj.gov.br/api/docs-json`
- Backend é NestJS (Express por baixo — `x-powered-by: Express`), com `class-validator`/`ValidationPipe` (provavelmente `whitelist: true, forbidNonWhitelisted: true`).

## Autenticação — sessão via cookie, não Bearer token

`POST /api/auth/login` autentica **via Keycloak** e cria uma **sessão de servidor** (não retorna JWT para o cliente usar em header). O servidor devolve um cookie de sessão (`set-cookie`, `HttpOnly; Secure; SameSite=None`, nome do cookie parece ser um hash gerado dinamicamente — não assumir nome fixo).

**Implicações práticas:**
- Ao usar `curl`, sempre usar cookie jar (`-c cookies.txt` no login, `-b cookies.txt` nas chamadas seguintes) — sem isso cada requisição some sem sessão e cai em `401`.
- CORS está configurado com `access-control-allow-credentials: true` e `vary: Origin` — a API valida a origem da requisição. Chamadas de um browser/frontend precisam mandar `Origin` permitido e `credentials: 'include'`.
- **Mesmo `GET /api/ready` exige sessão autenticada** (comportamento incomum para um readiness probe — confirmado por teste direto, retorna `401 {"message":"Não autenticado"}` sem cookie). Só `GET /api/health` é público.
- `LoginDto` (body de `/api/auth/login`) tem os campos:
  ```json
  { "username": "string", "password": "string" }
  ```
  (descobertos via erro de validação, não pelo Swagger — ver técnica abaixo). Login é delegado ao Keycloak, então `username`/`password` são as credenciais do usuário no realm do Keycloak da SES-RJ (ver skill [[keycloak-api]] se precisar inspecionar o realm/client por trás).

### Exemplo de fluxo com curl

> Nota: o exemplo abaixo com usuário/senha direto no `curl` é só ilustrativo do protocolo
> HTTP puro. Para uso real, prefira `setup-login.sh` (cadastra a credencial uma vez, fora do
> git) + `login.sh <alias>` — nunca digite a senha em texto puro na conversa com o assistente.

```bash
# 1. Login (grava cookie de sessão em cookies.txt)
curl -s -c /tmp/cronograma_cookies.txt -X POST \
  https://cronograma.saude.rj.gov.br/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"SEU_USUARIO","password":"SUA_SENHA"}'

# 2. Chamadas autenticadas reaproveitando o cookie
curl -s -b /tmp/cronograma_cookies.txt https://cronograma.saude.rj.gov.br/api/auth/me
curl -s -b /tmp/cronograma_cookies.txt https://cronograma.saude.rj.gov.br/api/projects

# 3. Logout
curl -s -b /tmp/cronograma_cookies.txt -X POST https://cronograma.saude.rj.gov.br/api/auth/logout
```

**Nunca pedir a senha do usuário em texto puro na conversa sem necessidade** — se precisar de credenciais, oriente o usuário a rodar o `curl` de login ele mesmo (ou usar `! curl ...` no prompt) para o cookie de sessão não passar pelo histórico do chat como texto legível junto da senha.

**Fluxo preferido — credencial cadastrada, nunca em texto puro:** rode `setup-login.sh` uma
vez (interativo: pergunta alias, usuário e senha com leitura mascarada) — a credencial fica
salva em `~/.claude/secrets/cronograma/users/<alias>.env` (`chmod 600`, fora do repo git).
Depois disso, use `login.sh <alias>` sempre que precisar de uma sessão nova. Nunca passe
usuário/senha como argumento de linha de comando (fica visível em `ps aux` e no histórico do
shell) nem os digite na conversa com o assistente.

## Limitação conhecida do Swagger: DTOs sem campos documentados

Os schemas em `components.schemas` (`CreateProjectDto`, `UpdateProjectDto`, `CreateCategoryDto`, `CreateActivityDto`, `UpdateActivityDto`, `UpdateNotesDto`, `UpdateActivityDayDto`, `BulkActivityDaysDto`, `CreateSnapshotDto` etc.) aparecem como `{"type":"object","properties":{}}` — ou seja, **o Swagger não documenta os campos dos bodies** (faltam decorators `@ApiProperty` no código-fonte do backend).

**Técnica para descobrir os campos de um DTO sem acesso ao código-fonte:** mandar um body vazio (`{}`) ou com um campo inventado autenticado, e ler a mensagem de erro `400` do `class-validator` — ela lista os campos obrigatórios e seus tipos. Foi assim que se descobriu o `LoginDto`:

```bash
curl -s -X POST https://cronograma.saude.rj.gov.br/api/auth/login \
  -H "Content-Type: application/json" -d '{}'
# => {"message":["username should not be empty","username must be a string",
#                "password should not be empty","password must be a string"],
#     "error":"Bad Request","statusCode":400}
```

Isso também confirma `forbidNonWhitelisted`: mandar um campo que não existe no DTO retorna `"property X should not exist"`.

Para os demais DTOs (Projects, Categories, Activities, ActivityDays, Snapshots), essa técnica exige estar autenticado primeiro — reaproveitar o cookie de sessão do login.

**`UpdateNotesDto`** (body de `PATCH /activities/{id}/notes`) — descoberto via `probe-dto.sh PATCH /activities/<id>/notes '{}'`:
```json
{ "notes": "string (máx. 1000 caracteres)" }
```
Único campo. `forbidNonWhitelisted` confirmado (`"property X should not exist"` em campo inventado).

**`UpdateActivityDayDto`** (body de `PUT /activity-days`) — descoberto via `probe-dto.sh PUT /activity-days '{}'` e variações:
```json
{
  "activityId": "string",
  "date": "string (YYYY-MM-DD)",
  "status": "F | A | C | \"\" (opcional)"
}
```
`activityId` e `date` são obrigatórios (erro no `{}`); `status` é opcional — omitido, a chamada retorna `200 {"success":true}` sem criar/alterar registro (no-op quando não há registro prévio naquela data). O enum de `status` foi revelado mandando um valor inválido (`"status":"X"`): `"status must be one of the following values: F, A, C, "` — os valores são as mesmas siglas visuais do sistema (F = A Fazer, A = Em andamento, C = Concluído) mais string vazia (`""`), que remove o registro do dia (bate com a descrição do endpoint na tabela acima: "Atualizar ou remover um registro").

**Armadilha:** `PUT /activities/{id}` (`update-activity.sh`) faz *replace* completo do registro — inclusive zera `notes` (e `responsible`) para `null`, mesmo eles não fazendo parte do `UpdateActivityDto` enviado. Ao editar descrição **e** notas da mesma atividade, sempre rodar `update-notes.sh` **depois** de `update-activity.sh` (nunca antes), senão o `PUT` sobrescreve as notas recém-gravadas.

**Atenção — nomenclatura de campos na resposta:** os bodies de request (`CreateActivityDto` etc.) usam `camelCase` (`projectId`, `categoryId`), mas os objetos retornados pela API usam `snake_case` (`project_id`, `category_id`). Confirmado batendo direto em `GET /api/activities?projectId=...` e inspecionando as chaves do JSON. Qualquer filtro client-side sobre a resposta precisa usar `category_id`/`project_id`, não `categoryId`/`projectId` — foi exatamente esse descompasso que causava o bug descrito na nota de correção do `list-activities.sh` abaixo.

## Endpoints

Tags conforme a spec (`/api/docs-json`). Todos exigem sessão autenticada exceto `GET /api/health`.

### App / Health
| Método | Path | Descrição | Auth |
|---|---|---|---|
| GET | `/api` | Rota raiz | sim |
| GET | `/api/health` | Healthcheck | **não** |
| GET | `/api/ready` | Readiness probe | sim (!) |

### Auth
| Método | Path | Descrição | Body |
|---|---|---|---|
| POST | `/api/auth/login` | Login via Keycloak, cria sessão | `LoginDto {username, password}` |
| GET | `/api/auth/me` | Usuário da sessão atual | — |
| POST | `/api/auth/logout` | Destrói sessão | — |

### Projects
| Método | Path | Descrição | Params/Body |
|---|---|---|---|
| GET | `/api/projects` | Listar projetos | query `archived` (string, opcional — `"true"` inclui arquivados) |
| POST | `/api/projects` | Criar projeto | body `CreateProjectDto` (campos não documentados — usar técnica de descoberta acima) |
| GET | `/api/projects/{id}` | Buscar por ID | path `id` |
| PUT | `/api/projects/{id}` | Atualizar | path `id`, body `UpdateProjectDto` |
| DELETE | `/api/projects/{id}` | Excluir | path `id` |
| PATCH | `/api/projects/{id}/archive` | Arquivar | path `id` |
| PATCH | `/api/projects/{id}/restore` | Restaurar | path `id` |

### Categories
| Método | Path | Descrição | Params/Body |
|---|---|---|---|
| GET | `/api/categories` | Listar categorias | query `projectId` (opcional, filtra por projeto) |
| POST | `/api/categories` | Criar categoria | body `CreateCategoryDto` |
| GET | `/api/categories/{id}` | Buscar por ID | path `id` |
| PUT | `/api/categories/{id}` | Atualizar | path `id`, body `UpdateCategoryDto` |
| DELETE | `/api/categories/{id}` | Excluir | path `id` |

### Activities
| Método | Path | Descrição | Params/Body |
|---|---|---|---|
| GET | `/api/activities` | Listar atividades | query `projectId` (opcional) |
| POST | `/api/activities` | Criar atividade | body `CreateActivityDto` |
| GET | `/api/activities/{id}` | Buscar por ID | path `id` |
| PUT | `/api/activities/{id}` | Atualizar | path `id`, body `UpdateActivityDto` |
| DELETE | `/api/activities/{id}` | Excluir | path `id` |
| PATCH | `/api/activities/{id}/notes` | Atualizar notas | path `id`, body `UpdateNotesDto` |

### Calendar
| Método | Path | Descrição | Params |
|---|---|---|---|
| GET | `/api/calendar` | Dados do calendário mensal | query `projectId` (obrigatório), `year` (obrigatório, ex `2026`), `month` (obrigatório, **0-indexado**: 0=Janeiro … 11=Dezembro) |

### ActivityDays
| Método | Path | Descrição | Body |
|---|---|---|---|
| PUT | `/api/activity-days` | Atualizar ou remover um registro | `UpdateActivityDayDto` |
| POST | `/api/activity-days/bulk` | Atualização em lote | `BulkActivityDaysDto` |

### Audit
| Método | Path | Descrição | Params |
|---|---|---|---|
| GET | `/api/audit` | Listar auditoria do projeto | query `projectId` (obrigatório), `offset` (number, opcional), `limit` (number, opcional) |

### Snapshots
| Método | Path | Descrição | Params/Body |
|---|---|---|---|
| GET | `/api/snapshots` | Listar snapshots do projeto | query `projectId` (obrigatório) |
| POST | `/api/snapshots` | Criar snapshot | body `CreateSnapshotDto` |
| POST | `/api/snapshots/{id}/restore` | Restaurar snapshot | path `id` |
| GET | `/api/snapshots/{id}/calendar` | Calendário do snapshot | path `id`, query `year`, `month` (mesma semântica de `/api/calendar`) |
| DELETE | `/api/snapshots/{id}` | Deletar snapshot | path `id` |

### Import
| Método | Path | Descrição | Body |
|---|---|---|---|
| POST | `/api/import/xlsx` | Importar planilha XLSX | `multipart/form-data`, campo `file` (binary) |

Exemplo de import:
```bash
curl -s -b /tmp/cronograma_cookies.txt -X POST \
  https://cronograma.saude.rj.gov.br/api/import/xlsx \
  -F "file=@/caminho/para/planilha.xlsx"
```

## Scripts prontos

Em vez de escrever `curl` + `python3 -c "..."` inline a cada uso, use os scripts em
`scripts/` (`~/.config/ai/skills/cronograma-saude-rj-api/scripts/`) — essa é a forma
preferida de interagir com a API. Os exemplos de `curl` das seções acima continuam
valendo como documentação de referência, mas para uso do dia a dia prefira os scripts.

Todos aceitam o caminho do cookie jar via variável de ambiente `CRONOGRAMA_COOKIE_JAR`
(default `$HOME/.cache/cronograma-cookies.txt`) e falham com exit code != 0 (imprimindo
o corpo do erro) se a API responder 4xx/5xx.

| Script | Uso | Descrição |
|---|---|---|
| `setup-login.sh` | `setup-login.sh` | Cadastra/edita (interativo) uma credencial de usuário/senha em `~/.claude/secrets/cronograma/users/<alias>.env` (`chmod 600`, fora do repo git); senha lida com eco mascarado. |
| `login.sh` | `login.sh [alias]` | Faz login (`POST /api/auth/login`) com a credencial cadastrada via `setup-login.sh` (alias padrão: `default`), salva o cookie de sessão no jar e imprime o usuário retornado. |
| `list-projects.sh` | `list-projects.sh [--archived]` | Lista projetos (`GET /api/projects`); com `--archived` inclui os arquivados. |
| `create-category.sh` | `create-category.sh <projectId> <name>` | Cria categoria (`POST /api/categories`); imprime o `id` criado em stdout (para capturar com `$(...)`) e o JSON completo em stderr. |
| `list-categories.sh` | `list-categories.sh <projectId>` | Lista categorias de um projeto (`GET /api/categories?projectId=...`). |
| `create-activity.sh` | `create-activity.sh <projectId> <categoryId> <number> <description>` | Cria atividade (`POST /api/activities`); mesma convenção de saída do `create-category.sh`. |
| `update-activity.sh` | `update-activity.sh <activityId> <categoryId> <number> <description>` | Atualiza atividade (`PUT /api/activities/{id}`) — os 3 campos são obrigatórios juntos, sem `projectId`. |
| `list-activities.sh` | `list-activities.sh <projectId> [categoryId]` | Lista atividades de um projeto; com o segundo argumento, filtra client-side (via `python3`) só as da categoria informada. **Correção aplicada em 2026-09-15:** o filtro comparava `item.get("categoryId")`, mas a API retorna o campo em snake_case (`category_id`) — o filtro nunca casava e sempre retornava `[]`. Corrigido para usar `category_id` (ver nota "Atenção — nomenclatura de campos na resposta" acima). |
| `delete-activity.sh` | `delete-activity.sh <activityId>` | Exclui atividade (`DELETE /api/activities/{id}`). |
| `update-notes.sh` | `update-notes.sh <activityId> <notes>` | Atualiza a observação/nota de uma atividade (`PATCH /api/activities/{id}/notes`) — **rodar sempre depois** de `update-activity.sh` na mesma atividade (ver armadilha acima). |
| `update-activity-day.sh` | `update-activity-day.sh <activityId> <date YYYY-MM-DD> <status>` | Atualiza (ou remove, com `status` vazio) o status de um dia de atividade no calendário (`PUT /api/activity-days`); `status` aceita `F`\|`A`\|`C`\|`""`. |
| `mark-status-range.sh` | `mark-status-range.sh <activityId> <startDate YYYY-MM-DD> <endDate YYYY-MM-DD> <status>` | Marca um intervalo de dias (inclusive nas duas pontas) com o mesmo `status`, chamando `update-activity-day.sh` uma vez por data (gera as datas via `python3`, sem depender de `date -d`); valida `startDate <= endDate` antes de qualquer chamada. Ver seção "Semântica de status por intervalo" abaixo para a regra de negócio por trás disso. |
| `apply-plan.sh` | `apply-plan.sh <projectId> <plan.json> [--dry-run]` | Aplica um "plano" (categorias + atividades, com `notes` opcionais) de uma vez, reaproveitando `create-category.sh`/`create-activity.sh`/`update-notes.sh` na ordem correta (notes sempre depois da criação da atividade). Com `--dry-run`, só valida o `plan.json` e imprime uma prévia, sem tocar a API. Sem `--dry-run`, cria tudo e imprime em stdout um resumo JSON com os ids criados; se algo falhar no meio, para, reporta em stderr o que já foi criado (para limpeza manual) e sai com código != 0 — sem rollback automático. Ver seção "Schema do plan.json" abaixo. |
| `probe-dto.sh` | `probe-dto.sh <METHOD> <path> [json_body]` | Sondagem genérica autenticada — envia `json_body` (default `{}`) ao endpoint informado e imprime a resposta, útil para descobrir campos de DTOs não documentados via erro 400 (ver técnica acima). Ex: `probe-dto.sh POST /projects '{}'`. |

### Schema do `plan.json` (`apply-plan.sh`)

```json
{
  "categories": [
    {
      "name": "Nome da categoria",
      "activities": [
        {
          "number": 1,
          "description": "Descrição da atividade",
          "notes": "Observação opcional (omitir ou string vazia = não seta)"
        }
      ]
    }
  ]
}
```

`categories` é obrigatório e precisa ser uma lista não vazia; cada categoria precisa de `name`
(string não vazia). `activities` é opcional por categoria (default `[]`); cada atividade precisa
de `number` (inteiro) e `description` (string não vazia). `notes` é opcional — omitido, `null` ou
`""` significa que `update-notes.sh` não é chamado para aquela atividade (a atividade fica sem
notas, comportamento padrão da API). O `apply-plan.sh` valida esse schema inteiro (com `python3`,
sem `jq`) antes de fazer qualquer chamada à API, inclusive no modo `--dry-run`.

### Semântica de status por intervalo (`ActivityDays` / calendário)

Regra de negócio: o status de uma atividade no calendário é marcado por dia (`ActivityDay`), mas
quando uma atividade leva N dias corridos até ser concluída, **os dias marcados vão do início até
a conclusão real, todos com o mesmo status final — não há status parcial por dia dentro do
intervalo.** Ex.: se uma atividade começou hoje e levou 5 dias até ser concluída, os 5 dias (hoje +
os 4 seguintes) são marcados com status `C`, não só o último dia. Isso é o que `mark-status-range.sh`
automatiza: ele repete o mesmo `status` em cada dia do intervalo informado, chamando
`update-activity-day.sh` uma vez por data.

Exemplo de fluxo completo:

```bash
export CRONOGRAMA_COOKIE_JAR="$HOME/.cache/cronograma-cookies.txt"

# Uma vez (interativo, credencial fica salva fora do git):
./scripts/setup-login.sh

./scripts/login.sh default
./scripts/list-projects.sh

CATEGORY_ID=$(./scripts/create-category.sh "$PROJECT_ID" "Minha categoria")
ACTIVITY_ID=$(./scripts/create-activity.sh "$PROJECT_ID" "$CATEGORY_ID" 1 "Minha atividade")

./scripts/list-activities.sh "$PROJECT_ID" "$CATEGORY_ID"
./scripts/update-activity.sh "$ACTIVITY_ID" "$CATEGORY_ID" 2 "Descrição atualizada"
./scripts/delete-activity.sh "$ACTIVITY_ID"

# Aplicar um plano inteiro (categorias + atividades + notes) de uma vez:
./scripts/apply-plan.sh "$PROJECT_ID" plan.json --dry-run   # só valida e mostra a prévia
./scripts/apply-plan.sh "$PROJECT_ID" plan.json             # cria de verdade; stdout = JSON com os ids

# Marcar um intervalo de dias com o mesmo status final (ver "Semântica de status por intervalo"):
./scripts/mark-status-range.sh "$ACTIVITY_ID" 2026-09-15 2026-09-19 C
```

## Como atualizar esta skill

Se os endpoints mudarem, revalidar assim (não confiar em memória — reconsultar sempre que for usar a API para uma tarefa nova):

```bash
curl -s https://cronograma.saude.rj.gov.br/api/docs-json | python3 -m json.tool
```

Comparar `paths` e `components.schemas` com o que está documentado acima e atualizar esta skill (`~/.config/ai/skills/cronograma-saude-rj-api/SKILL.md`) e commitar no repo `ai_skills`.
