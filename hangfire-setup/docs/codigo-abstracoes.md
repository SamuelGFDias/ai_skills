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

