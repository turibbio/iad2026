using Orders.Domain;

namespace Orders.Application;

public sealed class RemoveDiscountHandler(IOrderRepository repository)
{
    public async Task<Order?> HandleAsync(Guid orderId, CancellationToken cancellationToken = default)
    {
        var order = await repository.GetByIdAsync(orderId, cancellationToken);
        if (order is null)
        {
            return null;
        }

        order.RemoveDiscount();
        await repository.SaveAsync(order, cancellationToken);
        return order;
    }
}
