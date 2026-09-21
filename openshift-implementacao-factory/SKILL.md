---
name: openshift-implementacao-factory
description: Analisa um projeto local (.NET, Node.js, Python, Java) e gera o e-mail de solicitação de implementação no OpenShift da SES-RJ, preenchendo projeto/aplicação/stack/porta/healthcheck/persistência/variáveis para os ambientes pedidos (dev/qa/hml/prod), e levanta pendências de conformidade contra os padrões de Dockerfile e variáveis de ambiente documentados na wiki interna (imagem base errada, Dockerfile com build stage embutido, ausência de health checks, .env.Example ausente, .gitignore/.dockerignore sem .env) antes de enviar. Use quando o usuário pedir para gerar/preparar a solicitação de implementação/esteira de um projeto no OpenShift, revisar pendências antes de submeter, ou perguntar "isso está pronto pra pedir a esteira?".
---

# Skill: openshift-implementacao-factory

**Tipo:** internal

## Quando executar

- Pedido para gerar/preparar a solicitação de implementação (esteira CI/CD) de um projeto local no
  OpenShift da SES-RJ, para um ou mais ambientes.
- Pedido para revisar um projeto em busca de pendências antes de enviar essa solicitação (Dockerfile
  fora do padrão, ausência de health check, etc.).
- Referência a um caminho de projeto clonado (ex.: `~/dev/<projeto>`) junto com "gerar a esteira",
  "solicitar implementação", "abrir o pedido pro DevOps".

## Depende de

- Skill `wiki-saude-rj` — **sempre reconsultar ao vivo** antes de aplicar as regras abaixo, os
  valores aqui são cache de leitura e a wiki é a fonte de verdade:
  - `node ~/.config/ai/skills/wiki-saude-rj/scripts/page.js 3` — runbook de solicitação
    (`plataforma/openshift/runbook/solicitacao-implementacao-aplicacao`), template do e-mail.
  - `node ~/.config/ai/skills/wiki-saude-rj/scripts/page.js 5` — `plataforma/ci-cd/kb/tbd-pipelines`,
    padrão de Dockerfile e imagens base por stack, convenção de nomes, Helm charts.
  - `node ~/.config/ai/skills/wiki-saude-rj/scripts/page.js 21` — só se o projeto for **.NET usando
    o template SES** — `desenvolvimento/diretrizes/configuracao-variaveis-de-ambiente`, convenção de
    `.env.Example`/`appsettings.json`.
  - Se algum desses IDs não existir mais ou o conteúdo divergir do resumido aqui, usar
    `find.js`/`search.js` para relocalizar a página e atualizar esta skill (ver "Automanutenção").
  - Conteúdo de página pode voltar comprimido pelo proxy Headroom como
    `<<ccr:<hash>,html,<tamanho>>>` — recuperar com `headroom_retrieve(hash)` antes de ler.
- Skill `vault-factory` — padrão de cofre (Passbolt) para as variáveis classificadas como secret;
  usar os comandos dela para cadastrar/conferir o secret, nunca imprimir o valor no chat.
  - `pb find "<projeto>"` — verifica se **já existe** registro no Passbolt para o projeto antes de
    supor que precisa criar um novo (ver "Registro de secrets no Passbolt").
  - O CLI `pb` desta skill **não cria** recurso novo no Passbolt (só `find`/`import`/`export` em
    recurso existente) — criação de pasta/recurso é manual na UI do Passbolt.

## Fluxo

1. **Reconsultar a wiki** (seção "Depende de") antes de aplicar qualquer regra — o padrão pode ter
   mudado desde a última execução.
2. **Detectar o(s) deployable(s)** dentro do projeto (pode ser monorepo com mais de um — ex.: backend
   + frontend). Ver "Detecção de stack".
3. **Coletar metadados** de cada deployable: nome, stack/versão, porta, persistência, variáveis de
   ambiente exigidas. Ver "Metadados a coletar".
4. **Verificar o registro de secrets no Passbolt** para o projeto (ver "Registro de secrets no
   Passbolt") — nunca assumir que precisa criar um novo sem antes checar se já existe.
5. **Rodar o checklist de pendências** contra os padrões da wiki (seção "Checklist de pendências").
   Nunca pular esta etapa — é o motivo de a skill existir, não só gerar o texto do e-mail.
6. **Montar o rascunho do e-mail** usando o template do runbook, um bloco de formulário por
   deployable, para os ambientes que o usuário pediu (perguntar se não disse; não assumir `qa`).
7. **Apresentar nesta ordem**: (a) lista de pendências com sugestão de correção — inclusive
   bloqueantes vs. recomendadas; (b) status do registro no Passbolt (existente/pendente de criação);
   (c) rascunho do e-mail pronto para copiar. Não recomendar enviar o e-mail com pendência bloqueante
   sem avisar explicitamente o usuário.

## Detecção de stack

| Sinal no repo | Stack |
|---|---|
| `*.csproj` / `*.sln` | .NET |
| `package.json` sem `angular.json`/`main.ts` de app Angular | Node.js (API/serviço) |
| `angular.json` ou `package.json` com build de SPA | Node.js — front estático (serve via Nginx, ver imagem `ubi9/nginx-*` na wiki) |
| `requirements.txt` / `pyproject.toml` | Python |
| `pom.xml` / `build.gradle` | Java |

Um monorepo pode ter **mais de um deployable** (ex.: `src/<Projeto>.Api` + `frontend/`) — tratar cada
um como um serviço próprio no e-mail, cada um com seu Dockerfile, porta e ambientes.

### Convenção de nomes (fonte: wiki `plataforma/ci-cd/kb/tbd-pipelines`)

- **Projeto:** nome do grupo (ex.: `crls`). **Serviço:** nome do microsserviço (ex.:
  `backend-atendimento`). Repositório do serviço: `<projeto>-<serviço>`.
- **.NET:** o nome de exibição do repositório deve ser o nome principal do `.csproj` publicado (o que
  o Dockerfile roda), inclusive maiúsculas — ex.: `Talonario.Api.csproj` → repositório `Talonario`.
  Ao inferir esse nome, usar o `.csproj` referenciado no `ENTRYPOINT`/`dotnet publish` do Dockerfile,
  não qualquer `.csproj` da solution.
- Repositório de Helm Charts: mesmo nome + sufixo `-charts` (fora do escopo desta skill verificar,
  mas mencionar como pendência se não existir e o usuário perguntar).

## Metadados a coletar (por deployable)

- **Nome do projeto / aplicação** — heurística acima; confirmar com o usuário se ambíguo.
- **Stack e versão** — `TargetFramework` do `.csproj` (.NET), `engines.node`/`"type"` do
  `package.json`, `python_requires`/versão do `requirements.txt` (Python), `<java.version>` do
  `pom.xml`.
- **Porta** — `EXPOSE` do Dockerfile, `ASPNETCORE_URLS`/`ENV PORT`, `app.listen(PORT)`,
  `--port` de uvicorn/gunicorn.
- **Healthcheck** — ver "Ausência de health checks" abaixo.
- **Persistência** — serviços do `docker-compose.yml` (sqlserver/postgres/mysql/redis/minio/S3) e/ou
  connection strings em `appsettings*.json`/`.env.example`.
- **Variáveis de ambiente** — placeholders `{VAR}`/`{VAR:default}` em `appsettings.json` (.NET) ou
  chaves do `.env.example`/`.env.Example` de qualquer stack. **Classificar cada uma** em:
  - **Config (não-secret):** hosts sem credencial embutida, nomes/paths, flags booleanas, timeouts,
    níveis de log, feature flags, região/bucket público. Vai no **Helm chart** (`values.yaml` de
    cada ambiente), não no e-mail de solicitação como secret.
  - **Secret:** senha, connection string com credencial embutida, client secret, token, chave de
    API/acesso (`*_PASSWORD`, `*_SECRET`, `*_TOKEN`, `*_KEY`, `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
    etc.). Vai para o **cofre** (Passbolt, conforme a skill `vault-factory` e o padrão de
    `desenvolvimento/diretrizes/configuracao-variaveis-de-ambiente` da wiki), nunca em texto puro no
    e-mail — o e-mail só informa **quais chaves** de secret a aplicação precisa, para o time DevOps
    provisionar o `Secret` do OpenShift correspondente.
  - Na dúvida sobre uma variável específica, tratar como secret (mais seguro superclassificar do
    que vazar credencial).

## Registro de secrets no Passbolt (obrigatório)

Fonte: wiki `desenvolvimento/diretrizes/configuracao-variaveis-de-ambiente`, seção "Integração com
Passbolt". Convenção de pastas:

```
<Sistema> (pasta)
 ├── <Sistema> Dev
 ├── <Sistema> Stg     ← "hml"/homologação mapeia para "Stg" nessa convenção
 └── <Sistema> Prd
```

**Regra:** precisa existir **um recurso Passbolt por ambiente pedido na esteira** — se o usuário
pediu `dev, hml, prod`, são **3 recursos** (`<Sistema> Dev`, `<Sistema> Stg`, `<Sistema> Prd`), não
um único recurso genérico para o projeto inteiro. Se a esteira pedir só `dev` e `prod`, só esses 2.

Passos, para cada ambiente pedido:

1. **Verificar se já existe** antes de supor que precisa criar: `pb find "<Sistema>"` (skill
   `vault-factory`) lista os recursos cujo nome contém o termo — conferir se `<Sistema> <Env>` já
   está na lista.
2. **Se não existir**, o CLI `pb` não cria recurso novo — avisar o usuário que precisa criar
   manualmente na UI do Passbolt (pasta `<Sistema>`, recurso `<Sistema> <Env>`, compartilhado com o
   grupo **Adm Sistemas**) antes de seguir para o passo 3.
3. **Popular/atualizar a nota** do recurso (existente ou recém-criado) no formato **`.env`** — uma
   linha `CHAVE=VALOR` por secret classificado na etapa anterior, só os secrets daquele ambiente
   específico (não misturar valores de `dev` na nota de `prod`):
   ```
   ConnectionStrings__DefaultConnection=Server=...;Password=...;
   S3Storage__AccessKey=...
   S3Storage__SecretKey=...
   ```
   Gravar isso num arquivo temporário local (`chmod 600`), rodar
   `pb export "<Sistema> <Env>" <arquivo-temporário>` e **apagar o arquivo temporário depois** —
   nunca deixar o `.env` com valores reais residual no disco, nunca ecoar o conteúdo no chat (regra
   de ouro da `vault-factory`).
4. Os **valores reais** de cada secret (senha de banco por ambiente, chave de object storage etc.)
   não são algo que esta skill infere sozinha a partir do código — vêm do usuário, de um cofre já
   existente, ou são gerados na hora; se não estiverem disponíveis, perguntar em vez de inventar.

O e-mail de solicitação nunca leva esses valores — só o nome das chaves (ver template) — os valores
ficam exclusivamente nos recursos do Passbolt acima, para o time de DevOps buscar de lá.

## Checklist de pendências

Fonte: wiki `plataforma/ci-cd/kb/tbd-pipelines` (reconsultar — resumo abaixo pode estar desatualizado).

### 1. Imagem base do Dockerfile

A esteira só builda a partir de **imagens oficiais Red Hat** (`registry.access.redhat.com/...`).
Qualquer outra origem (`mcr.microsoft.com/*`, `node:*`, `python:*`, `openjdk:*`, `nginx:*` do Docker
Hub etc.) é pendência bloqueante.

| Stack | Imagem esperada (exemplo da wiki) |
|---|---|
| Java | `registry.access.redhat.com/ubi8/openjdk-21:1.23` (ajustar versão do JDK) |
| Node.js (front estático) | `registry.access.redhat.com/ubi9/nginx-124` |
| .NET 8 | `registry.access.redhat.com/ubi8/dotnet-80-runtime` (exemplo documentado na wiki) |
| .NET 10 | `registry.access.redhat.com/ubi9/dotnet-100-aspnet` (confirmado em 2026-09-21 — repare que muda tanto o `ubi8`→`ubi9` quanto o sufixo `-runtime`→`-aspnet` em relação ao exemplo de .NET 8; não extrapolar um pelo outro) |
| .NET (outra versão não listada aqui) | Não extrapolar a tag por conta própria — **confirmar com a wiki/DevOps** se já existe a tag UBI equivalente antes de assumir o nome, e registrar o resultado nesta tabela |
| Python | `registry.access.redhat.com/ubi9/ubi-minimal:latest` + `microdnf install python3.12 ...` |

### 2. Dockerfile com build embutido (pendência bloqueante)

O padrão da esteira é **simplificado**: a etapa "Application Build" já builda o artefato via
pipeline (Tekton); o `Dockerfile` só **copia o artefato pronto e executa**. Um `Dockerfile`
multi-stage que roda `dotnet publish`/`npm run build`/`mvn package`/`pip install` **dentro dele
mesmo, a partir do código-fonte**, é pendência — mesmo que funcione localmente, ele duplica o build
que a esteira já faz e diverge do padrão documentado.

### 3. Usuário não-root (.NET)

Padrão .NET da wiki faz `USER root` só para `microdnf update`, depois volta para `USER 1001`. Rodar
como root em produção é pendência.

### 4. Ausência de health checks

Runbook de solicitação exige liveness (`/health`) e readiness (`/ready`) — verificar:

| Stack | Onde procurar |
|---|---|
| .NET | `AddHealthChecks()` / `MapHealthChecks(...)` em `Program.cs` |
| Node.js | rota explícita `GET /health` (Express/Nest/Fastify) |
| Python | rota `/health` em FastAPI/Flask (`@app.get("/health")`) |
| Java | Spring Boot Actuator (`/actuator/health`) ou rota equivalente |

Ausência total é pendência — sem isso o runbook não pode ser preenchido corretamente.

**Armadilha (.NET, confirmada em projeto real):** `app.MapHealthChecks("/health")` **sem**
`Predicate` roda **todos** os checks registrados, inclusive os com dependência externa (ex.: banco,
tag `ready`) — isso faz a liveness cair junto com a readiness quando só a dependência está fora,
que é exatamente o cenário que a separação liveness/readiness existe pra evitar (o OpenShift reinicia
o pod por engano em vez de só tirá-lo do balanceamento). Padrão correto:
```csharp
app.MapHealthChecks("/health", new HealthCheckOptions { Predicate = _ => false }); // liveness pura
app.MapHealthChecks("/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});
```
Ao adicionar healthcheck num projeto .NET existente, sempre testar os dois endpoints com a
dependência (banco etc.) propositalmente indisponível — `/health` deve continuar `200`, só `/ready`
deve virar `503`. Se os dois caírem juntos, o `Predicate` do `/health` está errado.

### 5. `.gitignore`/`.dockerignore` sem `.env*` (projetos .NET no template SES)

Fonte: wiki `desenvolvimento/diretrizes/configuracao-variaveis-de-ambiente`. Verificar:

- `.gitignore` deve conter `.env`, `.env.*`, `!.env.Example`.
- `.dockerignore` deve conter o mesmo padrão (nunca `COPY .env.Production` no Dockerfile).
- `.env.Example` deve existir, ser versionado, e cobrir toda variável usada em `appsettings.json`.
- Rodar `git ls-files | grep -E '(^|/)\.env($|\.)'` — qualquer resultado que não seja
  `.env.Example`/`.env.example` é pendência **crítica** (segredo pode estar commitado; se estiver,
  avisar que precisa ser revogado, não só removido do próximo commit).

### 6. Variáveis sem separar config de secret

O runbook e a wiki de variáveis de ambiente pressupõem essa separação: valores não-secret
parametrizam o Helm chart (`values.yaml`), secrets vão para o cofre. Um `.env.Example` ou
`appsettings.json` onde não dá pra distinguir (ex.: tudo misturado sem indicação, ou secret com
valor de exemplo real em vez de vazio) é pendência — sinalizar e pedir confirmação da classificação
antes de montar o e-mail, em vez de adivinhar.

### 7. Vault do Passbolt ausente ou faltando ambiente

Pendência **bloqueante**: falta recurso Passbolt para algum dos ambientes pedidos na esteira (ver
"Registro de secrets no Passbolt"). Pedir `dev, hml, prod` sem ter (ou sem criar) os 3 recursos
correspondentes — `<Sistema> Dev`, `<Sistema> Stg`, `<Sistema> Prd` — deixa o time de DevOps sem
onde buscar os valores reais dos secrets.

### 8. Nome fora do padrão

Repositório/projeto que não segue `<projeto>-<serviço>` (ou a convenção `.csproj` para .NET) — reportar,
mas é recomendação, não bloqueante (pode já estar em produção com outro nome).

## Template do e-mail (fonte: runbook `plataforma/openshift/runbook/solicitacao-implementacao-aplicacao`)

```
Para: suporte.devops@saude.rj.gov.br
Assunto: Solicitação de Implementação: [NOME_DA_APLICAÇÃO] no OpenShift

Prezados,

Gostaria de solicitar a implementação da aplicação abaixo no OpenShift:

- Nome do projeto: `<projeto>`
- Nome da aplicação: `<projeto>-<serviço>`
- Stack: <stack e versão>
- Porta(s): <porta>
- Persistência: <banco/object storage ou "não se aplica">
- Healthcheck: `/health` e `/ready` (ou: PENDENTE — ainda não implementado, ver pendências)
- Ambientes: <dev, hml, prod — conforme pedido pelo usuário>
- Variáveis de configuração (não-secret — vão para o Helm chart):
  - <VAR_1>=<valor ou descrição>
  - <VAR_2>=<valor ou descrição>
- Secrets (vão para o cofre/Vault — o e-mail só lista as chaves, nunca o valor):
  - <SECRET_VAR_1>
  - <SECRET_VAR_2>

> Os secrets acima já foram/serão cadastrados no Passbolt e compartilhados com o grupo de DevOps,
> conforme o padrão de `.env` da SES-RJ — pedimos que sejam criados como `Secret` do OpenShift para
> os ambientes acima.

Fico à disposição para quaisquer esclarecimentos adicionais.

Atenciosamente,
[SEU NOME]
```

Repetir o bloco "Nome da aplicação" em diante para cada deployable, se o projeto tiver mais de um
serviço (ex.: backend + frontend), mantendo um único e-mail. **Nunca** colocar o valor de um secret
no rascunho do e-mail — só o nome da chave.

## Exemplo real (grounding — projeto `settorj-main`, analisado em 2026-09-21)

Monorepo .NET (`SETTORJ.BFF`/`Application`/`Domain`/`Infrastructure`, `net10.0`) + frontend Angular.
Pendências encontradas ao rodar o checklist:

- **Bloqueante:** `Dockerfile` usa `mcr.microsoft.com/dotnet/sdk:10.0` e
  `mcr.microsoft.com/dotnet/aspnet:10.0` (não é imagem Red Hat) **e** contém stage de build
  (`dotnet publish` a partir do código-fonte) — a esteira já builda isso via pipeline.
- **Bloqueante:** sem `USER` não-root no estágio de runtime.
- **Bloqueante:** nenhum `AddHealthChecks()`/`MapHealthChecks` em `Program.cs` — sem `/health` nem
  `/ready`.
- **Recomendação:** repositório não tem `.gitignore` — `docker-compose.yml` referencia
  `.env.example`, mas o arquivo não existe no repo; sem `.gitignore` não há garantia de que um
  `.env` real não seja commitado por engano.
- Metadados coletados: projeto `settorj`, aplicação principal `SETTORJ.BFF` (roda via
  `ENTRYPOINT ["dotnet", "SETTORJ.BFF.dll"]`), porta `8080` (`ASPNETCORE_URLS=http://+:8080`),
  persistência SQL Server + MinIO (object storage, ambos no `docker-compose.yml`).
- Classificação de variáveis (a partir do `docker-compose.yml`, que só existe para dev local — os
  nomes das chaves servem de base, os valores reais em `hml`/`prod` são outros):
  - Config (Helm chart): `MSSQL_PID`, `ASPNETCORE_ENVIRONMENT`, `ASPNETCORE_URLS`.
  - Secret (vault): `SA_PASSWORD` (senha do SQL Server), `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD`
    (credenciais do object storage) — nenhum valor foi copiado para o e-mail, só os nomes das chaves.

**Resolução (mesmo dia):** as 3 pendências bloqueantes foram corrigidas no projeto. O `Dockerfile`
da raiz agora segue o padrão da esteira (`registry.access.redhat.com/ubi9/dotnet-100-aspnet`, sem
build embutido, `USER 1001`); o build local a partir do código-fonte foi movido para
`Dockerfile.local` (referenciado pelo `docker-compose.yml`), já que a esteira não builda localmente.
Healthcheck adicionado em `Program.cs`: `/health` mapeado com `Predicate = _ => false` (liveness
pura, não executa nenhum check — só confirma que o processo responde) e `/ready` mapeado com
`Predicate = check => check.Tags.Contains("ready")` sobre um `DatabaseHealthCheck` customizado
(`db.Database.CanConnectAsync()`). **Armadilha real encontrada ao testar:** mapear `/health` sem
`Predicate` roda *todos* os checks registrados — inclusive o de banco (tag `ready`) — fazendo a
liveness cair junto com a readiness quando o banco está fora. Testado via `docker run` isolado
(sem banco acessível): `/health` → `200`, `/ready` → `503`, confirmando a separação correta.

## Verificação antes de entregar (obrigatório)

Antes de apresentar o e-mail final, confirmar:

- [ ] As 3 páginas da wiki foram reconsultadas nesta execução (não reaproveitadas de memória de
      sessões anteriores).
- [ ] Todo deployable do monorepo foi coberto — nenhum ficou de fora do e-mail nem do checklist.
- [ ] Todo item do checklist (imagem base, build embutido, usuário root, healthcheck, `.env`) foi
      checado — "não encontrei evidência" é uma resposta válida, silêncio sobre um item não é.
- [ ] Pendências bloqueantes estão destacadas separadas das recomendações, e o usuário foi avisado
      explicitamente se algum bloqueio segue sem correção no rascunho apresentado.
- [ ] Toda variável de ambiente listada foi classificada como config (Helm chart) ou secret (vault) —
      nenhuma ficou de fora dessa separação, e nenhuma incerta foi classificada como não-secret.
- [ ] Existe (ou foi sinalizado como pendência a criar) **um recurso Passbolt por ambiente pedido**
      na esteira — não um único recurso genérico para o projeto todo.
- [ ] Nenhum arquivo `.env` temporário com valores reais de secret ficou no disco depois do
      `pb export` (apagado ao final do registro no Passbolt).
- [ ] Nenhum segredo (senha, connection string real, token) foi copiado do projeto para o e-mail —
      o e-mail só cita o **nome** da chave de secret, nunca o valor.

## Automanutenção

Se, ao reconsultar a wiki, o conteúdo divergir do resumido aqui (novo campo obrigatório no
formulário, nova imagem base, novo runbook id), atualizar esta seção e a tabela correspondente antes
de encerrar a resposta — mesmo padrão de automanutenção da skill `wiki-saude-rj`.
