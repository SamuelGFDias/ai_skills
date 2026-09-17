---
name: webpush-vapid-factory
description: Gera, em qualquer projeto Angular + .NET, as abstrações de Web Push via VAPID (RFC 8292) endereçado a usuários específicos — notificações visíveis (funcionam com o app fechado) e mensagens silenciosas (só chegam com o app aberto, via SwPush.messages) — com armazenamento de subscriptions plugável (in-memory, Redis ou EF Core) e as armadilhas conhecidas documentadas (Service Worker só em build de produção, Node vs. Angular CLI major, Push API bloqueada em contexto efêmero). Use quando o usuário pedir para implementar, configurar ou depurar Web Push/VAPID/notificações push endereçadas a usuário num app Angular+.NET.
---

# Skill: webpush-vapid-factory

**Tipo:** internal

Gera as abstrações de Web Push via VAPID (RFC 8292) para um par de projetos Angular (frontend)
e .NET (backend), endereçando push a **usuários específicos** (não broadcast), com dois tipos de
mensagem — visível e silenciosa — e armazenamento de subscriptions plugável. Padrão com exemplos
de código real e testado dentro da própria pasta da skill, em `examples/` (ver seção 7), validado
originalmente com dois cenários de negócio reais testados via Playwright/Chromium real (dois
usuários simulados, cada um em perfil de browser isolado): notificação de chamado atribuído
(visível, app fechado) e revogação de permissão (silenciosa, app aberto).

## 1. Quando usar

- Projetos Angular + .NET que precisam enviar push **endereçado a um usuário específico**
  (não "notificar todo mundo") — ex.: "quando X acontece, o usuário Y é avisado no navegador".
- Casos que precisam funcionar com o app/aba **fechados** (notificação visível do SO).
- Casos que precisam empurrar um evento de **domínio/estado** para o app quando ele está
  **aberto**, sem necessariamente mostrar notificação do SO (mensagem silenciosa).
- Adicionar `@angular/pwa`/Service Worker a um Angular existente para viabilizar push.
- Gerar/rotacionar chaves VAPID e as abstrações de envio/despacho no backend .NET.
- Decidir ou implementar a estratégia de armazenamento de subscriptions (in-memory, Redis,
  EF Core) por trás de `IPushSubscriptionStore`.
- Depurar por que um push não chega (Service Worker, Node/Angular CLI, contexto de teste,
  app fechado ao usar mensagem silenciosa).

## 2. Visão geral da arquitetura — os dois tipos de mensagem

Toda mensagem push enviada por esta skill é modelada como uma subclasse de `PushMessage`, e o
tipo escolhido **é a decisão de design mais importante que o consumidor da skill precisa tomar
por caso de uso** — os dois tipos têm garantias de entrega estruturalmente diferentes:

| | `VisiblePushMessage` | `SilentPushMessage` |
|---|---|---|
| Formato "on the wire" | JSON com a chave `notification` (`{ notification: { title, body, icon?, vibrate?, data? } }`) | JSON **sem** a chave `notification` (ex.: `{ type, data }`) |
| O que o `ngsw-worker.js` faz ao receber | Chama `showNotification()` automaticamente — notificação do SO aparece | Repassa o payload via `postMessage` para todos os clients/abas abertos da mesma origem |
| Exposto no Angular via | `SwPush.notificationClicks` (clique do usuário na notificação) | `SwPush.messages` (observable de mensagens) |
| **Funciona com app/aba fechados?** | **Sim** — é o cenário clássico de push | **Não** — só entrega se houver pelo menos um client/aba aberto daquela origem no navegador no momento do push. Se o app estiver 100% fechado, a mensagem silenciosa se perde silenciosamente (esperado, não é bug) |
| Uso típico | Avisar o usuário de algo que ele precisa ver mesmo sem o app aberto (chamado atribuído, novo comentário, prazo vencendo) | Empurrar um evento de estado/domínio para atualizar algo em segundo plano só quando o app já está em uso (permissão revogada → forçar `refreshToken`; configuração alterada → invalidar cache local; dado mudou → refazer uma query) |

Regra de decisão para o consumidor da skill: **se a ação exige que o usuário seja avisado
independentemente de estar com o app aberto, use `VisiblePushMessage`. Se a ação só faz sentido
reagir enquanto o app já está aberto (ex.: forçar um refresh de token, invalidar um cache local,
recarregar uma tela em foco), use `SilentPushMessage` — e documente para quem for operar o
sistema que esse evento não tem efeito nenhum se o usuário estiver com o app fechado.**

Ambos os tipos são despachados pelo mesmo ponto de entrada — `IPushNotificationDispatcher.NotifyUserAsync(userId, message)` — o tipo é só o `message` passado.

## 3. Backend — abstrações a gerar

Nomes/namespaces adaptados ao projeto consumidor; contrato e regras abaixo são fixos.

### 3.1. DTOs de subscription

```csharp
public record PushSubscriptionDto(string Endpoint, PushSubscriptionKeysDto Keys);
public record PushSubscriptionKeysDto(string P256dh, string Auth);
```

Formato que casa exatamente com `PushSubscription.toJSON()` do navegador
(`{ endpoint, keys: { p256dh, auth } }`) — não renomear os campos internos.

### 3.2. `PushMessage` e subtipos — regra de serialização exata

```csharp
public abstract record PushMessage;

public record VisiblePushMessage(
    string Title,
    string Body,
    string? Icon = "assets/icons/icon-192x192.png",
    int[]? Vibrate = null,
    object? Data = null
) : PushMessage;

public record SilentPushMessage(
    string Type,
    object? Data = null
) : PushMessage;
```

Um serializador dedicado (`PushMessageSerializer.Serialize(PushMessage)`) decide o formato
"on the wire" por `switch` de tipo:

- `VisiblePushMessage` → serializa envolto em `{ notification: { title, body, icon, vibrate, data } }`
  (usar `JsonPropertyName` explícito nessas chaves, em inglês, porque é o contrato que o
  `ngsw-worker.js` espera — não são nomes livres).
- `SilentPushMessage` → serializa **sem** a chave `notification`, ex.: `{ type, data }`. É essa
  ausência da chave `notification` que faz o Service Worker do Angular tratar como mensagem
  silenciosa em vez de notificação visível — não é uma flag separada, é a forma do JSON.

### 3.3. `IWebPushNotificationService` — envio de baixo nível

```csharp
public enum PushSendStatus { Sent, Expired, Failed }
public record PushSendResult(PushSendStatus Status, string Endpoint);

public interface IWebPushNotificationService
{
    Task<PushSendResult> SendAsync(PushSubscriptionDto subscription, PushMessage message, CancellationToken ct = default);
}
```

A implementação concreta (única classe que conhece o pacote NuGet `WebPush`, autor Stephane
Queraud, versão confirmada `1.0.13`):

- Monta `VapidDetails` a partir de config (`Vapid:Subject/PublicKey/PrivateKey`), lançando
  `InvalidOperationException` se algum estiver ausente.
- Monta `WebPush.PushSubscription` a partir do DTO, serializa a `PushMessage` via
  `PushMessageSerializer` e chama `WebPushClient.SendNotificationAsync`.
- Trata `WebPushException` com `StatusCode` `410 Gone` ou `404 Not Found` como subscription
  expirada/revogada → devolve `Expired` (nunca propaga a exceção). Qualquer outro erro: loga
  (`ILogger`) e devolve `Failed`. Nunca `void`, nunca deixa exceção não tratada subir ao chamador.

### 3.4. `IPushNotificationDispatcher` — ponto de extensão para eventos de negócio

```csharp
public record PushDispatchResult(int Sent, int Expired, int Failed);

public interface IPushNotificationDispatcher
{
    Task<PushDispatchResult> NotifyUserAsync(string userId, PushMessage message);
}
```

Implementação: busca `store.GetByUser(userId)`, chama `SendAsync` para cada subscription do
usuário, remove do store as que voltarem `Expired`, agrega o resultado. **É este método —
`NotifyUserAsync(userId, message)` — que todo código de domínio deve chamar**; nada de domínio
deve conhecer `IWebPushNotificationService` ou `IPushSubscriptionStore` diretamente (ver seção 5).

### 3.5. `IPushSubscriptionStore` — contrato plugável (sempre gerar; ver estratégias abaixo)

```csharp
public interface IPushSubscriptionStore
{
    void AddOrUpdate(string userId, PushSubscriptionDto subscription);
    IReadOnlyList<PushSubscriptionDto> GetByUser(string userId);
    IReadOnlyList<PushSubscriptionDto> GetAll();
    void Remove(string endpoint);
}
```

Este é o contrato exato — qualquer implementação nova (Redis, EF Core, outra) deve se encaixar
nele via DI (`AddSingleton<IPushSubscriptionStore, MinhaImplementacao>()` ou `AddScoped` quando a
implementação depender de `DbContext`), sem mudar `IPushNotificationDispatcher` nem os endpoints.

**Sempre gerar a interface. Escolher e gerar apenas UMA das implementações abaixo** — nunca as
três de uma vez. Ao aplicar o padrão num projeto novo, **perguntar ao usuário ou inferir pela
stack do projeto** (já usa Redis? já usa EF Core? é uma instância única sem réplicas?) qual
estratégia usar antes de gerar código.

**Estratégia 1 — In-memory (`Dictionary<string, List<PushSubscriptionDto>>` + `lock`, singleton).**
Implementação real e testada em `examples/backend/PushSubscriptionStore.cs`
(`InMemoryPushSubscriptionStore`, indexado por `userId`). Simples, zero infraestrutura extra.
Trade-off: perde todas as subscriptions a cada restart do processo; **não funciona corretamente
com múltiplas instâncias/réplicas do backend** — cada instância teria seu próprio dicionário, e o
push de um usuário só chegaria se a instância que processasse `NotifyUserAsync` fosse a mesma que
registrou a subscription dele.
Adequado para: prova de conceito, MVP de instância única, ambiente de desenvolvimento.

**Estratégia 2 — Redis.** Chave `push:subscriptions:{userId}` — ex.: um `SET`/`LIST` de
subscriptions serializadas em JSON por usuário, ou um `Hash` por usuário com o endpoint como
campo. `AddOrUpdate` grava/atualiza a entrada daquele usuário; `GetByUser` lê e desserializa;
`Remove(endpoint)` precisa varrer por usuário (ou manter um índice reverso `endpoint → userId`
se o volume justificar). Resolve o problema de múltiplas instâncias, já que todas compartilham o
mesmo Redis.
Trade-off: precisa de Redis rodando e configurado (mais uma peça de infraestrutura); é um
cache/store de baixa durabilidade dependendo da política de persistência do Redis — geralmente
aceitável para subscriptions, porque elas expiram/mudam naturalmente e o app se reinscreve.
Adequado para: múltiplas instâncias/réplicas do backend, projeto que já usa Redis.
Sketch ilustrativo (não testado contra Redis real) em
`examples/backend/PushSubscriptionStore.Redis.cs.snippet`.

**Estratégia 3 — Banco relacional via EF Core.** Entidade
`PushSubscriptionEntity { Id, UserId, Endpoint, P256dh, Auth, CreatedAt }`, com índice único em
`Endpoint` (uma subscription pertence a um endpoint só) e índice em `UserId` (busca por usuário é
o caminho quente). `AddOrUpdate` faz upsert por `Endpoint`; `GetByUser` filtra por `UserId`;
`Remove` deleta por `Endpoint`.
Trade-off: mais setup (migration, `DbContext`), mas dá durabilidade real, auditabilidade, e
permite `JOIN` com outras tabelas de domínio (ex.: relacionar a subscription ao usuário/analista
de verdade em vez de um `userId` solto).
Adequado para: aplicação que já usa EF Core e quer tratar subscriptions como dado de domínio de
primeira classe.
Sketch ilustrativo (não testado contra banco real) em
`examples/backend/PushSubscriptionStore.EfCore.cs.snippet`.

### 3.6. Endpoints mínimos

- `GET /api/push/vapid-public-key` → `{ publicKey }` a partir da config.
- `POST /api/push/register` → recebe `PushSubscriptionDto`, resolve o `userId` do requisitante e
  chama `store.AddOrUpdate(userId, subscription)`.
  - **Resolução do `userId`**: em dev/prova de conceito, simulável por um header simples
    (`X-User-Id`), como no projeto de referência — evita montar um pipeline de auth completo só
    para testar o padrão. Em produção, **sempre** resolver via claims do JWT autenticado
    (`HttpContext.User`), nunca aceitar um `userId` vindo do corpo/header sem autenticação — senão
    qualquer requisição pode registrar subscription em nome de outro usuário.
- Endpoint(s) de disparo/negócio: ver seção 5 — não hardcodear regra de "quem recebe" aqui, isso é
  do domínio de cada projeto.
- **CORS**: liberar explicitamente a origem do frontend (`WithOrigins("http://<host>:<porta>")`,
  `AllowAnyHeader()`, métodos `GET`/`POST`) — nunca `AllowAnyOrigin()` combinado com credenciais.

### 3.7. Chaves VAPID

- Gerar **uma única vez** com um programa/teste descartável (nunca deixar código de geração no
  `Program.cs` final):

  ```csharp
  var keys = WebPush.VapidHelper.GenerateVapidKeys();
  Console.WriteLine($"Public: {keys.PublicKey}");
  Console.WriteLine($"Private: {keys.PrivateKey}");
  ```

- Persistir `Vapid:Subject` (formato `mailto:algum@dominio`), `Vapid:PublicKey` e
  `Vapid:PrivateKey`:
  - Projeto de teste local sem VCS → `appsettings.Development.json` é aceitável.
  - Qualquer projeto real → User Secrets (`dotnet user-secrets`), variável de ambiente ou Key
    Vault em produção. **Nunca** versionar a chave privada.
- Se já existirem chaves persistidas, reaproveitá-las — não gerar novas sem o usuário pedir
  explicitamente rotação.

## 4. Frontend — abstrações a gerar

- **Antes de fixar a major do Angular CLI, checar a versão do Node instalado** (ver seção 6).
- Se o projeto ainda não tem PWA: `ng add @angular/pwa` — gera `ngsw-config.json`,
  `manifest.webmanifest`, ícones placeholder, e injeta em `app.config.ts`:

  ```ts
  provideServiceWorker('ngsw-worker.js', {
    enabled: !isDevMode(),
    registrationStrategy: 'registerWhenStable:30000',
  })
  ```

  Se o projeto já tem `@angular/pwa`, só confirmar que o provider está presente — não rodar
  `ng add` de novo.
- Criar um serviço/componente standalone (nome sugerido: `PushSubscriberService`/`Component`)
  que:
  1. Injeta `SwPush` (de `@angular/service-worker`) e `HttpClient`.
  2. Verifica `swPush.isEnabled` antes de qualquer chamada.
  3. Busca a chave pública em runtime via `GET /api/push/vapid-public-key` — **nunca** hardcoded
     (evita rebuild ao rotacionar chaves).
  4. Chama `swPush.requestSubscription({ serverPublicKey: publicKey })`.
  5. Envia a subscription resultante (já serializa como `toJSON()`/`{ endpoint, keys: { p256dh,
     auth } }`) via `POST /api/push/register`, associada ao usuário logado — em dev,
     header simples (`X-User-Id`); em produção, o backend resolve o usuário pelo JWT da própria
     requisição autenticada, sem o frontend precisar mandar o id.
  6. Assina `swPush.notificationClicks` para navegação/tratamento de clique em notificação
     visível.
  7. Assina `swPush.messages` para mensagens silenciosas — o **consumidor da skill implementa o
     dispatch por `type`** (isso é específico de cada app; ver exemplos na seção 5), ex.:

     ```ts
     this.swPush.messages.subscribe((message: any) => {
       if (message?.type === 'permissions-changed') {
         this.authService.refreshToken();
       }
       // outros types tratados aqui, um por evento de negócio
     });
     ```
  - Tratar erros de cada etapa (permissão negada, backend fora, chave inválida) e refletir em
    estado observável pelo template — nunca deixar a Promise rejeitada sem `.catch`/`error`.

## 5. Como conectar a eventos de negócio reais

O padrão é sempre o mesmo: **qualquer código de domínio chama
`dispatcher.NotifyUserAsync(userId, message)`** — o dispatcher e o store não sabem nada sobre a
regra de negócio que disparou o push; a regra de negócio não sabe nada sobre WebPush/VAPID.

Já testados ponta-a-ponta no projeto de referência:

- **Chamado atribuído a um analista** (visível, app fechado):
  `dispatcher.NotifyUserAsync(analystUserId, new VisiblePushMessage("Novo chamado atribuído", $"O chamado {ticketId} foi atribuído a você.", Data: new { url = $"/chamados/{ticketId}" }))`.
- **Permissão revogada** (silenciosa, exige app aberto):
  `dispatcher.NotifyUserAsync(userId, new SilentPushMessage("permissions-changed", new { reason = "revoked-by-admin" }))`, tratado no frontend por um listener que chama `AuthService.refreshToken()`.

Outros exemplos genéricos, para deixar claro que o padrão não é hardcoded para
"chamados"/"permissões" — a implementar da mesma forma quando surgirem:

- **Novo comentário numa tarefa/chamado que o usuário acompanha** (visível): `dispatcher.NotifyUserAsync(watcherUserId, new VisiblePushMessage("Novo comentário", $"{autor} comentou em {tarefa}.", Data: new { url = $"/tarefas/{tarefaId}" }))`.
- **Configuração/feature flag do usuário alterada por um admin, exigindo recarregar estado local só se o app já estiver em uso** (silenciosa): `dispatcher.NotifyUserAsync(userId, new SilentPushMessage("settings-changed", new { key = "tema" }))`, tratado no frontend recarregando a configuração em cache.
- **Prazo de uma tarefa vencendo em breve** (visível, o usuário precisa ser avisado mesmo sem o app aberto): `dispatcher.NotifyUserAsync(responsavelUserId, new VisiblePushMessage("Prazo se aproximando", $"A tarefa {tarefa} vence em 1 dia.", Data: new { url = $"/tarefas/{tarefaId}" }))`.

Em todos os casos, o endpoint HTTP que expõe a ação de negócio (`POST /api/.../assign`,
`POST /api/.../revoke`, etc.) apenas injeta `IPushNotificationDispatcher` e chama
`NotifyUserAsync` depois de persistir o efeito de domínio — o dispatch de push nunca é a única
coisa que o endpoint faz, é um efeito colateral do evento de domínio real.

## 6. Armadilhas conhecidas

- **Service Worker só registra em build de produção.** `ng serve` não ativa o Service Worker do
  Angular. Qualquer teste manual do fluxo de push precisa servir o build de produção
  estaticamente (ex.: `ng build` seguido de servir `dist/<app>/browser/` com um servidor HTTP
  simples), não `ng serve`.
- **Node vs. major do Angular CLI.** Majors recentes exigem Node bem específico (ex.: Angular CLI
  22 exige Node `^22.22.3`) e falham silenciosamente com erro claro mesmo com Node "quase"
  compatível. Confirmar antes de fixar a major:

  ```bash
  node -v
  npx @angular/cli@<major> version
  ```

- **Push API bloqueada em contexto efêmero/incógnito.** Testar em modo incógnito ou em contexto
  anônimo padrão de automação (ex.: `browser.newContext()` do Playwright) NÃO funciona para a
  Push API — o Chrome bloqueia deliberadamente (https://crbug.com/41124656). Testes automatizados
  precisam usar `launchPersistentContext` com um `userDataDir` real (persistente), não um contexto
  novo e descartável. Para simular dois usuários distintos em teste, usar dois `userDataDir`
  diferentes (perfis de browser isolados) — foi assim que o projeto de referência provou que
  `analyst-1` recebe a notificação e `user-2` não recebe nada.
- **Mensagem silenciosa só chega com pelo menos uma aba/cliente aberto da origem.** Isso é
  estrutural, não um bug a corrigir: se o app estiver 100% fechado no momento do push, a
  `SilentPushMessage` se perde — não há retry, não há fila. Se o evento de negócio precisa
  garantidamente alcançar o usuário mesmo com o app fechado, ele não é candidato a mensagem
  silenciosa; use `VisiblePushMessage` ou combine com outro canal (e-mail, polling na próxima
  abertura do app).
- **Contexto seguro exigido pela Push API.** HTTPS em produção. `localhost` em HTTP puro é uma
  exceção aceita pelo navegador — útil para dev local sem certificado; qualquer outro host em HTTP
  não funciona.

## 7. Projeto de referência funcional

Os exemplos de código desta skill moram dentro da própria pasta da skill, em `examples/`
(caminhos relativos a `~/.config/ai/skills/webpush-vapid-factory/`), justamente para que a skill
seja autocontida e funcione em qualquer máquina/ambiente sem depender de um projeto de teste
externo.

- **Backend, código real testado ponta-a-ponta** — `examples/backend/`:
  - `Models.cs` — DTOs (`PushSubscriptionDto`/`PushSubscriptionKeysDto`) e `PushMessage`/
    `VisiblePushMessage`/`SilentPushMessage`.
  - `PushSubscriptionStore.cs` — `IPushSubscriptionStore`/`InMemoryPushSubscriptionStore`
    (Estratégia 1 da seção 3.5), indexado por `userId`.
  - `WebPushNotificationService.cs` — `IWebPushNotificationService`, implementação concreta e
    `PushMessageSerializer` (serialização exata dos dois tipos de mensagem).
  - `PushNotificationDispatcher.cs` — `IPushNotificationDispatcher`/`PushDispatchResult`, ponto
    de extensão de negócio.
  - `Program.cs.snippet` — trechos extraídos (registro de DI, CORS, os 2 endpoints mínimos e os
    2 endpoints de demonstração de negócio) de um `Program.cs` real; **não é o arquivo completo**,
    é ilustrativo de como esses pedaços se encaixam — copiar os trechos relevantes, não colar
    inteiro.
- **Frontend, código real testado ponta-a-ponta** — `examples/frontend/`:
  - `push-subscriber.component.ts` — componente com `SwPush`, subscrição de `notificationClicks`
    e `messages`.
  - `auth.service.ts` — exemplo de efeito reagindo a uma mensagem silenciosa via `refreshToken`.
- **Sketches ilustrativos, NÃO testados contra infraestrutura real** — `examples/backend/`:
  - `PushSubscriptionStore.Redis.cs.snippet` — Estratégia 2 da seção 3.5.
  - `PushSubscriptionStore.EfCore.cs.snippet` — Estratégia 3 da seção 3.5.

Ler esses arquivos como referência de código real e funcional (exceto os dois `.snippet` de
Redis/EF Core, explicitamente marcados como não testados) — **não copiar literalmente**; extrair
o padrão (abstrações, decisões, armadilhas) e adaptar aos nomes, namespaces, regras de negócio e
estratégia de armazenamento do projeto consumidor.

Contexto histórico: este padrão foi validado pela primeira vez ponta-a-ponta num projeto de teste
local (`/home/samuel.dias/dev/tests/WebPush/`), com Playwright/Chromium real, em dois cenários de
negócio (chamado atribuído — visível, app fechado; permissão revogada — silenciosa, app aberto);
esse caminho é efêmero e pode não existir em outra máquina, por isso os `examples/` acima são a
fonte de referência que a skill de fato depende.

## Checklist final antes de entregar

- [ ] Decidido, para cada evento de negócio, se a mensagem é `VisiblePushMessage` (precisa
      alcançar o usuário mesmo com o app fechado) ou `SilentPushMessage` (só precisa reagir com o
      app já aberto) — e documentado o trade-off para quem for operar o sistema.
- [ ] `IPushSubscriptionStore` gerado como interface, com **uma** implementação escolhida
      (in-memory, Redis ou EF Core) com base na stack real do projeto — nunca as três geradas
      juntas.
- [ ] Chaves VAPID persistidas fora de código versionado (exceto projeto de teste local sem VCS).
- [ ] `IWebPushNotificationService` sem dependência do pacote `WebPush` fora da implementação
      concreta.
- [ ] Tratamento de `WebPushException` 410/404 removendo a subscription do armazenamento.
- [ ] Código de domínio chama só `IPushNotificationDispatcher.NotifyUserAsync(userId, message)` —
      nunca conhece `IWebPushNotificationService`/`IPushSubscriptionStore` diretamente.
- [ ] `POST /api/push/register` resolve o `userId` por autenticação real em produção (claims do
      JWT), não por header não autenticado.
- [ ] CORS liberando exatamente a origem do frontend.
- [ ] Chave pública buscada em runtime no frontend, nunca hardcoded.
- [ ] Testado com build de produção servido estaticamente, não `ng serve`.
- [ ] Se houver teste automatizado de push, usa `launchPersistentContext` com `userDataDir` real
      (um por usuário simulado, se o teste precisar distinguir destinatários).
- [ ] Se algum evento usa `SilentPushMessage`, testado com a aba/app aberto — e documentado que
      não há entrega garantida com o app fechado.
