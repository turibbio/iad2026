using Orders.Domain;

namespace Orders.Application;

public sealed class ApplyDiscountHandler(IOrderRepository repository)
{
    public async Task<Order?> HandleAsync(
        Guid orderId,
        string code,
        decimal percentage,
        CancellationToken cancellationToken = default)
    {
        var order = await repository.GetByIdAsync(orderId, cancellationToken);
        if (order is null)
        {
            return null;
        }

        order.ApplyDiscount(code, percentage);
        await repository.SaveAsync(order, cancellationToken);
        return order;
    }
}
