using Orders.Domain;

namespace Orders.Application;

public sealed class GetDemoOrderHandler(IOrderRepository repository)
{
    public static readonly Guid OrderId = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");

    public Task<Order?> HandleAsync(CancellationToken cancellationToken = default)
        => repository.GetByIdAsync(OrderId, cancellationToken);
}
