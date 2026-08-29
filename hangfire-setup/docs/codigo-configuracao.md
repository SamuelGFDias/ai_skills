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

