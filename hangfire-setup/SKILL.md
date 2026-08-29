---
name: hangfire-setup
description: "Configuracao do Hangfire em projetos .NET seguindo o padrao Sindras: abstracoes desacopladas (sem dependencia de Hangfire) + projeto de implementacao concreta, filtros, DI, dashboard, server profile-based e testes com NSubstitute. Código de referência completo em docs/. Use ao configurar Hangfire, criar/revisar jobs ou background services em backend .NET."
---

# Skill: hangfire-setup

**Tipo:** internal

Configuracao do Hangfire seguindo o padrao Sindras: camada de abstracao sem dependencia de Hangfire + projeto de implementacao concreta com Hangfire.

## Arquitetura (resumo)

```
<Projeto>.Infra.BackgroundJobs              (abstracoes, sem dependencia Hangfire)
  |-- Interfaces/   IBackgroundJobService, IJobManager, IJobContext, IJob, IJobRegister
  |-- Jobs/         Implementacoes concretas de jobs
  |-- Models/       RescheduleJobsRequest, RescheduleJobsResult
  |-- Exceptions/   JobFailureException
  |-- Extensions/   JobErrorExtensions (EnsureSuccess)
  |-- JobRegister.cs

<Projeto>.Infra.BackgroundJobs.Hangfire      (implementacao concreta com Hangfire)
  |-- HangfireJobActivator.cs / HangfireBackgroundJobService.cs
  |-- HangfireJobContext.cs (AsyncLocal) / JobManager.cs (reschedule)
  |-- Factory/ConfigureHangfireService.cs
  |-- Filters/   JobContextFilter, CultureJobFilter, JobFailureMetadataFilter,
                 RateLimitFilter, AllowAllDashboardAuthorizationFilter
```

**Principio central:** as abstracoes (`*BackgroundJobs`) não conhecem Hangfire — a implementacao
concreta (`*BackgroundJobs.Hangfire`) vive na borda e só ela depende do Hangfire.

## Dependencias NuGet

- **Abstracoes** (`*BackgroundJobs.csproj`): nenhuma dependencia do Hangfire; só dependencias do dominio.
- **Implementacao** (`*BackgroundJobs.Hangfire.csproj`):
  `Hangfire`, `Hangfire.Core`, `Hangfire.SqlServer`, `Hangfire.Console`, `FaceIT.Hangfire.Tags`,
  `FaceIT.Hangfire.Tags.SqlServer`, `Microsoft.Data.SqlClient`, `TimeZoneConverter`, + ProjectReference
  do projeto de abstracoes.

## Passos de configuracao (DI/Startup)

1. `builder.AddHangfire()` — `UseSqlServerStorage(conn)`, `UseConsole()`, `UseTagsWithSql()`,
   `UseActivator(new HangfireJobActivator(sp))`, filtros (`RateLimit`, `CultureJob`, `JobContext`,
   `JobFailureMetadata`), `SetDataCompatibilityLevel(Version_180)`, serializers recomendados.
2. `builder.Services.AddHangfireServices()` — scoped de `IBackgroundJobService`, `IJobRegister`,
   `IJobContext`, `IJobManager`.
3. `builder.AddHangfireServer()` — profile-based via env `WORKER_PROFILE` (`HEAVY`/`FAST`/`ALL`);
   `ALL` roda filas `critical, default, heavy`, `FAST` `critical, default`, `HEAVY` só `heavy`.
4. `app.AddDashboard()` — `/hangfire` com `AllowAllDashboardAuthorizationFilter` (dashboard aberto;
   em produção, trocar por autorização real).
5. Registrar recorrentes: `scope.ServiceProvider.GetRequiredService<IJobRegister>().RegisterAll()`.

Connection string: banco SQL Server **dedicado** (separado do banco da aplicacao) — ver
`docs/connection-string.md`.

## Observacoes importantes (leia antes de implementar)

- `PerformContext` usa construtor de 3 parametros: `(IStorageConnection, BackgroundJob, IJobCancellationToken)`.
- `BackgroundJob` esta no namespace `Hangfire` (nao `Hangfire.Common`); `IJobCancellationToken` esta
  em `Hangfire` (nao `Hangfire.Server`).
- `SetJobParameter`/`GetJobParameter<T>` sao instance methods que usam `Connection`.
- Usar `InternalsVisibleTo` no csproj do Hangfire para o projeto de testes acessar
  `HangfireJobContext.Set()`.
- O banco Hangfire deve ser um **banco SQL Server separado** do banco da aplicacao.
- Worker profiles via variavel de ambiente `WORKER_PROFILE=HEAVY|FAST|ALL`.
- Jobs recorrentes com cron e fuso: `TZConvert.GetTimeZoneInfo("E. South America Standard Time")`.

## Codigo de referencia (docs/)

O codigo completo esta separado por camada — leia a secao necessaria, nao o arquivo inteiro:

| Secao | Arquivo |
|---|---|
| Abstracoes (`IBackgroundJobService`, `IJobContext`, `IJob`, `IJobRegister`, `IJobManager`, `JobFailureException`, `JobErrorExtensions`, `RescheduleJobsResult`, `JobRegister`) | `docs/codigo-abstracoes.md` |
| Implementacao Hangfire (`HangfireJobActivator`, `HangfireBackgroundJobService`, `HangfireJobContext`, `JobManager`) | `docs/codigo-hangfire.md` |
| Filtros (Contexto, Cultura, Falha, RateLimit, Dashboard) | `docs/codigo-filtros.md` |
| Configuracao / DI (`ConfigureHangfireService`, Startup, dual registration) | `docs/codigo-configuracao.md` |
| Connection string | `docs/connection-string.md` |
| Testes (`HangfireContextFactory` + exemplo) | `docs/codigo-testes.md` |

## Testes

Usar `HangfireContextFactory` (`docs/codigo-testes.md`) para criar `PerformContext`/`PerformedContext`/
`PerformingContext` em testes de filtros com NSubstitute — sem exigir um servidor Hangfire real.
Dependencias: `NSubstitute` + ProjectReference do projeto `.Hangfire`.
