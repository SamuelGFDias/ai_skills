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

