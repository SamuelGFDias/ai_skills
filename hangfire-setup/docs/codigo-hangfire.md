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
    // (ver implementacao completa no projeto de referencia - JobManager.cs)

    private static bool IsAppJob(Job job) =>
        job.Type.Namespace?.Contains("<Namespace>") == true;

    private static IEnumerable<QueueWithTopEnqueuedJobsDto> ReadQueuesSafely(IMonitoringApi monitor)
    {
        try { return monitor.Queues(); }
        catch (InvalidOperationException) { return []; }
    }
}
```

