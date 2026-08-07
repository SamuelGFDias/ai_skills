---
name: hangfire-setup
description: "Configuracao completa do Hangfire em projetos .NET, incluindo abstracoes desacopladas, implementacao Hangfire, filtros, DI, dashboard, server profile-based e testes com NSubstitute. Baseado no padrao Sindras."
---

# Skill: hangfire-setup

Configuracao do Hangfire seguindo o padrao Sindras: camada de abstracao sem dependencia de Hangfire + projeto de implementacao concreta com Hangfire.

## Arquitetura

```
<Projeto>.Infra.BackgroundJobs              (abstracoes, sem dependencia Hangfire)
  |-- Interfaces/                            IBackgroundJobService, IJobManager, IJobContext, IJob, IJobRegister
  |-- Jobs/                                  Implementacoes concretas de jobs
  |-- Models/                                RescheduleJobsRequest, RescheduleJobsResult
  |-- Exceptions/                            JobFailureException
  |-- Extensions/                            JobErrorExtensions (EnsureSuccess)
  |-- JobRegister.cs                         Registro de recorrentes

<Projeto>.Infra.BackgroundJobs.Hangfire      (implementacao concreta com Hangfire)
  |-- HangfireJobActivator.cs                Ativador com escopo DI
  |-- HangfireBackgroundJobService.cs        IBackgroundJobService impl
  |-- HangfireJobContext.cs                  IJobContext impl (AsyncLocal)
  |-- JobManager.cs                          IJobManager impl (reschedule)
  |-- Factory/ConfigureHangfireService.cs    Extension methods de config
  |-- Filters/
       |-- JobContextFilter.cs               Contexto ambiente
       |-- CultureJobFilter.cs               Cultura pt-BR
       |-- JobFailureMetadataFilter.cs       Metadados de falha
       |-- RateLimitFilter.cs                Rate limiting (opcional)
       |-- AllowAllDashboardAuthorizationFilter.cs
```

## Dependencias NuGet

### Projeto de abstracoes (`*BackgroundJobs.csproj`)
Nenhuma dependencia do Hangfire. Apenas dependencias do dominio do projeto.

### Projeto de implementacao (`*BackgroundJobs.Hangfire.csproj`)
```xml
<ItemGroup>
  <PackageReference Include="Hangfire" />
  <PackageReference Include="Hangfire.Core" />
  <PackageReference Include="Hangfire.SqlServer" />
  <PackageReference Include="Hangfire.Console" />
  <PackageReference Include="FaceIT.Hangfire.Tags" />
  <PackageReference Include="FaceIT.Hangfire.Tags.SqlServer" />
  <PackageReference Include="Microsoft.Data.SqlClient" />
  <PackageReference Include="TimeZoneConverter" />
</ItemGroup>
<ItemGroup>
  <ProjectReference Include="..\<Projeto>.Infra.BackgroundJobs\<Projeto>.Infra.BackgroundJobs.csproj" />
</ItemGroup>
```

## Abstracoes (projeto sem Hangfire)

### `IBackgroundJobService`
```csharp
using System.Linq.Expressions;

namespace <Projeto>.Infra.BackgroundJobs.Interfaces;

public interface IBackgroundJobService
{
    string Enqueue<T>(Expression<Func<T, Task>> job);
    string Schedule<T>(Expression<Func<T, Task>> job, TimeSpan delay);
    void AddRecurringJob<T>(string jobName, Expression<Func<T, Task>> job, string cronExpression);
    string ContinueWith<T>(string parentId, Expression<Func<T, Task>> job);
}
```

### `IJobContext`
```csharp
using ErrorOr;

namespace <Projeto>.Infra.BackgroundJobs.Interfaces;

public interface IJobContext
{
    string JobId { get; }
    string Queue { get; }
    CancellationToken CancellationToken { get; }
    void SetResult(string value);
    void Log(string message);
    void Log(string format, params object[] args);
    void SetCulture(string culture);
    void AddTags(params string[] tags);
    void SetFailure(Error error);
    void SetFailure(string code, string description);
}
```

### `IJob`
```csharp
namespace <Projeto>.Infra.BackgroundJobs.Interfaces;

public interface IJob
{
    Task ExecuteAsync(params object[] args);
}
```

### `IJobRegister`
```csharp
namespace <Projeto>.Infra.BackgroundJobs.Interfaces;

public interface IJobRegister
{
    void RegisterAll();
}
```

### `IJobManager`
```csharp
using <Projeto>.Infra.BackgroundJobs.Models;

namespace <Projeto>.Infra.BackgroundJobs.Interfaces;

public interface IJobManager
{
    RescheduleJobsResult RescheduleJobs(
        DateTimeOffset scheduledAt,
        bool includeFailed = false,
        bool includeProcessing = false);
}
```

### `JobFailureException`
```csharp
using ErrorOr;

namespace <Projeto>.Infra.BackgroundJobs.Exceptions;

public class JobFailureException : Exception
{
    public Error Error { get; }

    public JobFailureException(Error error)
        : base($"Job falhou: {error.Description}", null)
    {
        Error = error;
    }

    public JobFailureException(Error error, Exception? innerException)
        : base($"Job falhou: {error.Description}", innerException)
    {
        Error = error;
    }
}
```

### `JobErrorExtensions`
```csharp
using ErrorOr;
using <Projeto>.Infra.BackgroundJobs.Exceptions;

namespace <Projeto>.Infra.BackgroundJobs.Extensions;

public static class JobErrorExtensions
{
    public static T EnsureSuccess<T>(this ErrorOr<T> value)
    {
        return value.IsError ? throw new JobFailureException(value.FirstError) : value.Value;
    }
}
```

### `RescheduleJobsResult`
```csharp
namespace <Projeto>.Infra.BackgroundJobs.Models;

public class RescheduleJobsResult
{
    public int ScheduledJobsRescheduled { get; set; }
    public int EnqueuedJobsRescheduled { get; set; }
    public int FailedJobsRescheduled { get; set; }
    public int ProcessingJobsRescheduled { get; set; }
    public int SkippedJobs { get; set; }
    public int TotalRescheduled =>
        ScheduledJobsRescheduled + EnqueuedJobsRescheduled + FailedJobsRescheduled + ProcessingJobsRescheduled;
}
```

### `JobRegister` (exemplo)
```csharp
using <Projeto>.Infra.BackgroundJobs.Interfaces;

namespace <Projeto>.Infra.BackgroundJobs;

public class JobRegister(IBackgroundJobService jobService) : IJobRegister
{
    public void RegisterAll()
    {
        // Exemplo: job recorente a meia-noite
        jobService.AddRecurringJob<MeuJob>(
            "MeuJobRecorrente",
            j => j.ExecuteAsync(),
            "0 0 * * *"
        );
    }
}
```

## Implementacao Hangfire

### `HangfireJobActivator` — Escopo DI por job
```csharp
using Hangfire;
using Microsoft.Extensions.DependencyInjection;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire;

public class HangfireJobActivator(IServiceProvider provider) : JobActivator
{
    public override object ActivateJob(Type jobType)
    {
        return provider.GetRequiredService(jobType);
    }

    public override JobActivatorScope BeginScope(JobActivatorContext context)
    {
        return new ServiceProviderScope(provider.CreateScope());
    }

    private class ServiceProviderScope(IServiceScope serviceScope) : JobActivatorScope
    {
        public override object Resolve(Type type)
        {
            return serviceScope.ServiceProvider.GetRequiredService(type);
        }

        public override void DisposeScope()
        {
            serviceScope.Dispose();
        }
    }
}
```

### `HangfireBackgroundJobService`
```csharp
using System.Linq.Expressions;
using Hangfire;
using <Projeto>.Infra.BackgroundJobs.Interfaces;
using TimeZoneConverter;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire;

public class HangfireBackgroundJobService(IRecurringJobManager recurringJobManager) : IBackgroundJobService
{
    private readonly RecurringJobOptions _jobOptions = new()
    {
        TimeZone = TZConvert.GetTimeZoneInfo("E. South America Standard Time")
    };

    public string Enqueue<T>(Expression<Func<T, Task>> job) => BackgroundJob.Enqueue(job);
    public string Schedule<T>(Expression<Func<T, Task>> job, TimeSpan delay) => BackgroundJob.Schedule(job, delay);

    public void AddRecurringJob<T>(string jobName, Expression<Func<T, Task>> job, string cronExpression)
    {
        recurringJobManager.AddOrUpdate(jobName, job, cronExpression, _jobOptions);
    }

    public string ContinueWith<T>(string parentId, Expression<Func<T, Task>> job)
        => BackgroundJob.ContinueJobWith(parentId, job);
}
```

### `HangfireJobContext` — Contexto ambiente via AsyncLocal
```csharp
using System.Globalization;
using Hangfire.Console;
using Hangfire.Server;
using Hangfire.Tags;
using Serilog.Context;
using <Projeto>.Infra.BackgroundJobs.Exceptions;
using <Projeto>.Infra.BackgroundJobs.Interfaces;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire;

public class HangfireJobContext : IJobContext
{
    private static readonly AsyncLocal<PerformContext?> Current = new();
    private static readonly AsyncLocal<IDisposable?> LogContextScope = new();

    public CancellationToken CancellationToken
        => Current.Value?.CancellationToken.ShutdownToken ?? CancellationToken.None;

    internal static void Set(PerformContext? context)
    {
        Current.Value = context;
        if (context?.BackgroundJob?.Id == null) return;
        LogContextScope.Value?.Dispose();
        LogContextScope.Value = LogContext.PushProperty("JobId", context.BackgroundJob.Id);
    }

    public string JobId => Current.Value?.BackgroundJob?.Id ?? "unknown";
    public string Queue => Current.Value?.BackgroundJob?.Job?.Queue ?? "default";

    public void SetResult(string value) => Current.Value?.SetJobParameter("Result", value);

    public void Log(string message)
    {
        using (LogContext.PushProperty("JobId", JobId))
        using (LogContext.PushProperty("Queue", Queue))
        {
            Current.Value?.WriteLine(message);
            Serilog.Log.Information(message);
        }
    }

    public void Log(string messageTemplate, params object[] args)
    {
        using (LogContext.PushProperty("JobId", JobId))
        {
            Serilog.Log.Information(messageTemplate, args);
        }
        try { Current.Value?.WriteLine(messageTemplate, args); }
        catch (FormatException)
        {
            Current.Value?.WriteLine($"{messageTemplate} [Args: {string.Join(", ", args)}]");
        }
    }

    public void SetCulture(string culture)
    {
        var ci = new CultureInfo(culture);
        CultureInfo.CurrentCulture = ci;
        CultureInfo.CurrentUICulture = ci;
    }

    public void AddTags(params string[] tags) => Current.Value?.AddTags(tags);

    public void SetFailure(ErrorOr.Error error)
    {
        Log("Job falhou: {Code} - {Description}", error.Code, error.Description);
        SetResult($"Falha: {error.Code} - {error.Description}");
        throw new JobFailureException(error);
    }

    public void SetFailure(string code, string description)
    {
        SetFailure(ErrorOr.Error.Failure(code, description));
    }
}
```

### `JobManager` — Reagendamento de jobs
```csharp
using Hangfire;
using Hangfire.Common;
using Hangfire.States;
using Hangfire.Storage;
using Hangfire.Storage.Monitoring;
using <Projeto>.Infra.BackgroundJobs.Interfaces;
using <Projeto>.Infra.BackgroundJobs.Models;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire;

public class JobManager(IBackgroundJobClient backgroundJobClient) : IJobManager
{
    private const int PAGE_SIZE = 250;

    public RescheduleJobsResult RescheduleJobs(
        DateTimeOffset scheduledAt, bool includeFailed = false, bool includeProcessing = false)
    {
        var monitor = JobStorage.Current.GetMonitoringApi();
        var result = new RescheduleJobsResult();
        var scheduledAtUtc = scheduledAt.UtcDateTime;

        foreach (var queue in ReadQueuesSafely(monitor))
        {
            foreach (var job in ReadEnqueuedJobs(monitor, queue.Name).Where(j => IsAppJob(j.Value.Job)))
            {
                if (TrySchedule(job.Key, new ScheduledState(scheduledAtUtc), EnqueuedState.StateName))
                    result.EnqueuedJobsRescheduled++;
                else
                    result.SkippedJobs++;
            }
        }

        foreach (var job in ReadScheduledJobs(monitor).Where(j => IsAppJob(j.Value.Job)))
        {
            if (TrySchedule(job.Key, new ScheduledState(scheduledAtUtc), ScheduledState.StateName))
                result.ScheduledJobsRescheduled++;
            else
                result.SkippedJobs++;
        }

        if (includeProcessing)
        {
            foreach (var job in ReadProcessingJobs(monitor).Where(j => IsAppJob(j.Value.Job)))
            {
                if (TrySchedule(job.Key, new ScheduledState(scheduledAtUtc), ProcessingState.StateName))
                    result.ProcessingJobsRescheduled++;
                else
                    result.SkippedJobs++;
            }
        }

        if (includeFailed)
        {
            foreach (var job in ReadFailedJobs(monitor).Where(j => IsAppJob(j.Value.Job)))
            {
                if (TrySchedule(job.Key, new ScheduledState(scheduledAtUtc), FailedState.StateName))
                    result.FailedJobsRescheduled++;
                else
                    result.SkippedJobs++;
            }
        }

        return result;
    }

    private bool TrySchedule(string jobId, ScheduledState state, string expectedState)
    {
        try { return backgroundJobClient.ChangeState(jobId, state, expectedState); }
        catch (InvalidOperationException) { return false; }
    }

    // Metodos de leitura paginada: ReadEnqueuedJobs, ReadScheduledJobs, ReadFailedJobs, ReadProcessingJobs
    // Cada um itera paginas de 250 ate esgotar ou lancar InvalidOperationException
    // (ver implementacao completa no Sindras - JobManager.cs)

    private static bool IsAppJob(Job job) =>
        job.Type.Namespace?.Contains("<Namespace>") == true;

    private static IEnumerable<QueueWithTopEnqueuedJobsDto> ReadQueuesSafely(IMonitoringApi monitor)
    {
        try { return monitor.Queues(); }
        catch (InvalidOperationException) { return []; }
    }
}
```

## Filtros Hangfire

### `JobContextFilter` — Injeta contexto ambiente
```csharp
using Hangfire.Server;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire.Filters;

public class JobContextFilter : IServerFilter
{
    public void OnPerforming(PerformingContext context) => HangfireJobContext.Set(context);
    public void OnPerformed(PerformedContext context) => HangfireJobContext.Set(null);
}
```

### `CultureJobFilter` — Cultura pt-BR
```csharp
using System.Globalization;
using Hangfire.Common;
using Hangfire.Server;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire.Filters;

public class CultureJobFilter : JobFilterAttribute, IServerFilter
{
    private CultureInfo? _originalCulture;
    private CultureInfo? _originalUiCulture;

    public void OnPerforming(PerformingContext context)
    {
        _originalCulture = CultureInfo.CurrentCulture;
        _originalUiCulture = CultureInfo.CurrentUICulture;
        var culture = new CultureInfo("pt-BR");
        CultureInfo.CurrentCulture = culture;
        CultureInfo.CurrentUICulture = culture;
    }

    public void OnPerformed(PerformedContext context)
    {
        if (_originalCulture != null) CultureInfo.CurrentCulture = _originalCulture;
        if (_originalUiCulture != null) CultureInfo.CurrentUICulture = _originalUiCulture;
    }
}
```

### `JobFailureMetadataFilter` — Metadados de falha
```csharp
using Hangfire.Server;
using Serilog;
using <Projeto>.Infra.BackgroundJobs.Exceptions;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire.Filters;

public class JobFailureMetadataFilter : IServerFilter
{
    public void OnPerforming(PerformingContext context) { }

    public void OnPerformed(PerformedContext context)
    {
        if (context.Exception is JobFailureException jobFailure)
        {
            var error = jobFailure.Error;
            context.SetJobParameter("ErrorCode", error.Code);
            context.SetJobParameter("ErrorDescription", error.Description);
            context.SetJobParameter("ErrorType", error.Type.ToString());
            context.SetJobParameter("FailureTime", DateTimeOffset.UtcNow.ToString("O"));
            Log.Error("Job {JobId} falhou - Code: {Code}, Description: {Description}",
                context.BackgroundJob?.Id, error.Code, error.Description);
        }
        else if (context.Exception != null)
        {
            context.SetJobParameter("ExceptionType", context.Exception.GetType().Name);
            context.SetJobParameter("ExceptionMessage", context.Exception.Message);
            context.SetJobParameter("FailureTime", DateTimeOffset.UtcNow.ToString("O"));
        }
    }
}
```

### `RateLimitFilter` — Placeholder
```csharp
using Hangfire.Common;
using Hangfire.States;
using Hangfire.Server;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire.Filters;

public class RateLimitFilter : JobFilterAttribute, IElectStateFilter
{
    public void OnStateElection(ElectStateContext context)
    {
        // Logica de rate limit: se estado for Failed por excesso, reagendar
    }
}
```

### `AllowAllDashboardAuthorizationFilter` — Dashboard aberto
```csharp
using Hangfire.Dashboard;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire.Filters;

public class AllowAllDashboardAuthorizationFilter : IDashboardAuthorizationFilter
{
    public bool Authorize(DashboardContext context) => true;
}
```

## Configuracao / DI

### Extension methods em `ConfigureHangfireService.cs`
```csharp
using Hangfire;
using Hangfire.Console;
using Hangfire.Tags.SqlServer;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using <Projeto>.Infra.BackgroundJobs.Hangfire.Filters;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire.Factory;

public static class ConfigureHangfireService
{
    public static void AddHangfire(this IHostApplicationBuilder bd)
    {
        string? connection = bd.Configuration.GetConnectionString("Hangfire");
        bd.Services.AddHangfire((sp, config) =>
            config.UseSqlServerStorage(connection)
                .UseConsole()
                .UseTagsWithSql()
                .UseActivator(new HangfireJobActivator(sp))
                .UseFilter(new RateLimitFilter())
                .UseFilter(new CultureJobFilter())
                .UseFilter(new JobContextFilter())
                .UseFilter(new JobFailureMetadataFilter())
                .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
                .UseSimpleAssemblyNameTypeSerializer()
                .UseRecommendedSerializerSettings()
        );
    }

    public static void AddHangfireServices(this IServiceCollection sp)
    {
        sp.AddScoped<IBackgroundJobService, HangfireBackgroundJobService>();
        sp.AddScoped<IJobRegister, JobRegister>();
        sp.AddScoped<IJobContext, HangfireJobContext>();
        sp.AddScoped<IJobManager, JobManager>();
    }

    public static void AddHangfireServer(this IHostApplicationBuilder bd)
    {
        string profile = bd.Configuration.GetSection("WORKER_PROFILE").Value?.ToUpper() ?? "ALL";
        if (profile is "HEAVY")
        {
            bd.Services.AddHangfireServer(options =>
            {
                options.ServerName = $"HEAVY-{Environment.MachineName}";
                options.WorkerCount = 2;
                options.Queues = ["heavy"];
            });
        }
        if (profile is "FAST" or "ALL")
        {
            bd.Services.AddHangfireServer(options =>
            {
                options.ServerName = $"FAST-{Environment.MachineName}";
                options.WorkerCount = 10;
                options.Queues = ["critical", "default"];
            });
        }
    }

    public static void AddDashboard(this IApplicationBuilder app)
    {
        app.UseHangfireDashboard("/hangfire", new DashboardOptions
        {
            Authorization = [new AllowAllDashboardAuthorizationFilter()],
            DashboardTitle = "Hangfire Dashboard",
        });
    }
}
```

### Startup (Program.cs)
```csharp
// Registro
builder.AddHangfire();
builder.Services.AddHangfireServices();
builder.AddHangfireServer();

// Middleware
app.AddDashboard();

// Registro de jobs recorrentes na inicializacao
using (var scope = app.Services.CreateScope())
{
    var jobRegister = scope.ServiceProvider.GetRequiredService<IJobRegister>();
    jobRegister.RegisterAll();
}
```

### Dual registration no IoC (para projetos MVC/API)
```csharp
private IServiceCollection AddHangfireBackgroundJobs(IConfiguration configuration)
{
    services.AddScoped<IJobManager, JobManager>();
    var connection = configuration.GetConnectionString("Hangfire");
    services.AddHangfire((sp, config) =>
        config.UseSqlServerStorage(connection)
            .UseConsole().UseTagsWithSql()
            .UseActivator(new HangfireJobActivator(sp))
            .UseFilter(new CultureJobFilter())
            .UseFilter(new JobContextFilter())
            .UseFilter(new JobFailureMetadataFilter())
            .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
            .UseSimpleAssemblyNameTypeSerializer()
            .UseRecommendedSerializerSettings()
    );
    services.AddHangfireServer(options =>
    {
        options.ServerName = $"ALL-{Environment.MachineName}";
        options.WorkerCount = 10;
        options.Queues = ["critical", "default", "heavy"];
    });
    services.AddHangfireServices();
    return services;
}
```

## Connection String

```json
{
  "ConnectionStrings": {
    "Hangfire": "Server={DB_HOST};Initial Catalog={DB_NAME};User Id={DB_USER};Password={DB_PASSWORD};MultipleActiveResultSets=false;Encrypt={ENCRYPT};TrustServerCertificate={TRUST_CERT};Connection Timeout={TIMEOUT};"
  }
}
```

Usar um banco SQL Server **dedicado** (separado do banco da aplicacao).

## Testes com HangfireContextFactory

### Dependencias de teste
```xml
<ItemGroup>
  <PackageReference Include="NSubstitute" />
  <ProjectReference Include="..\..\src\<Projeto>.Infra.BackgroundJobs.Hangfire\<Projeto>.Infra.BackgroundJobs.Hangfire.csproj" />
</ItemGroup>
```

### `HangfireContextFactory` — Factory para criar contextos Hangfire em testes
```csharp
using System.Reflection;
using Hangfire;
using Hangfire.Common;
using Hangfire.Server;
using Hangfire.Storage;
using NSubstitute;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire.Tests;

internal static class HangfireContextFactory
{
    private static readonly Type PerformContextType = typeof(PerformContext);
    private static readonly Type PerformedContextType = typeof(PerformedContext);
    private static readonly Type PerformingContextType = typeof(PerformingContext);
    private static readonly Type BackgroundJobType = typeof(BackgroundJob);
    private static readonly Type JobType = typeof(Job);

    private static object CreateJob(Type testClass)
    {
        var method = testClass.GetMethod("TestMethod",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
        return Activator.CreateInstance(JobType, [testClass, method])!;
    }

    public static PerformContext CreatePerformContext(Type testClass)
    {
        var job = CreateJob(testClass);
        var bgJob = Activator.CreateInstance(BackgroundJobType, ["test-job", job, DateTime.UtcNow])!;
        var connection = Substitute.For<IStorageConnection>();
        var parameters = new Dictionary<string, string>();

        connection.When(x => x.SetJobParameter(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<string>()))
            .Do(ci => parameters[ci.ArgAt<string>(1)] = ci.ArgAt<string>(2));

        connection.GetJobParameter(Arg.Any<string>(), Arg.Any<string>())
            .Returns(ci => parameters.TryGetValue(ci.ArgAt<string>(1), out var v) ? v : null!);

        var cancellationToken = Substitute.For<IJobCancellationToken>();
        var context = Activator.CreateInstance(PerformContextType, [connection, bgJob, cancellationToken])!;
        return (PerformContext)context;
    }

    public static PerformedContext CreatePerformedContext(Type testClass, Exception? exception)
    {
        var performContext = CreatePerformContext(testClass);
        return (PerformedContext)Activator.CreateInstance(
            PerformedContextType, [performContext, null, false, exception])!;
    }

    public static PerformingContext CreatePerformingContext(Type testClass)
    {
        var performContext = CreatePerformContext(testClass);
        return (PerformingContext)Activator.CreateInstance(
            PerformingContextType, [performContext])!;
    }
}
```

### Exemplo de teste com a factory
```csharp
using Hangfire.Server;
using NSubstitute;

namespace <Projeto>.Infra.BackgroundJobs.Hangfire.Tests;

public class MeuFiltroTests
{
    [Fact]
    public void OnPerforming_DeveDefinirContexto()
    {
        var context = HangfireContextFactory.CreatePerformingContext(GetType());
        var filter = new MeuFiltro();
        filter.OnPerforming(context);
        // Assert...
    }
}
```

## Observacoes importantes

- `PerformContext` usa construtor de 3 parametros: `(IStorageConnection, BackgroundJob, IJobCancellationToken)`
- `BackgroundJob` esta no namespace `Hangfire` (nao `Hangfire.Common`)
- `IJobCancellationToken` esta no namespace `Hangfire` (nao `Hangfire.Server`)
- `SetJobParameter`/`GetJobParameter<T>` sao instance methods que usam `Connection`
- Usar `InternalsVisibleTo` no csproj do Hangfire para o projeto de testes acessar `HangfireJobContext.Set()`
- O banco Hangfire deve ser um **banco SQL Server separado** do banco da aplicacao
- Para ambientes com worker profiles, usar variavel de ambiente `WORKER_PROFILE=HEAVY|FAST|ALL`
