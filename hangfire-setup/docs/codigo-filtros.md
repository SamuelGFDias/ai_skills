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

