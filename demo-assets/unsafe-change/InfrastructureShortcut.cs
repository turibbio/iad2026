using Orders.Infrastructure;

namespace Orders.Application;

// DEMO ONLY: intentional forbidden dependency.
public static class InfrastructureShortcut
{
    public static Type RepositoryType => typeof(InMemoryOrderRepository);
}
