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

## Como atualizar esta skill

Se os endpoints mudarem, revalidar assim (não confiar em memória — reconsultar sempre que for usar a API para uma tarefa nova):

```bash
curl -s https://cronograma.saude.rj.gov.br/api/docs-json | python3 -m json.tool
```

Comparar `paths` e `components.schemas` com o que está documentado acima e atualizar esta skill (`~/.config/ai/skills/cronograma-saude-rj-api/SKILL.md`) e commitar no repo `ai_skills`.
