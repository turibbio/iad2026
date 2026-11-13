using Orders.Application;
using Orders.Domain;
using Xunit;

namespace Orders.UnitTests;

public sealed class DiscountTests
{
    [Fact]
    public void Applying20PercentDiscount_Produces80EuroTotal()
    {
        var order = new Order(Guid.NewGuid(), 100m);
        order.ApplyDiscount("SAVE20", 20m);
        Assert.Equal(80m, order.Total);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(31)]
    [InlineData(100)]
    public void InvalidDiscount_IsRejected(decimal percentage)
    {
        var order = new Order(Guid.NewGuid(), 100m);
        Assert.Throws<ArgumentOutOfRangeException>(() => order.ApplyDiscount("BAD", percentage));
    }

    [Fact]
    public async Task HandlerPersistsAppliedDiscount()
    {
        var repository = new FakeRepository();
        var order = new Order(Guid.NewGuid(), 100m);
        await repository.SaveAsync(order);
        var handler = new ApplyDiscountHandler(repository);
        var updated = await handler.HandleAsync(order.Id, "SAVE10", 10m);

        Assert.NotNull(updated);
        Assert.Equal(90m, updated.Total);
        Assert.Equal(2, repository.SaveCalls);
    }

    private sealed class FakeRepository : IOrderRepository
    {
        private readonly Dictionary<Guid, Order> _orders = new();

        public int SaveCalls { get; private set; }

        public Task<Order?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
        {
            _orders.TryGetValue(id, out var order);
            return Task.FromResult(order);
        }

        public Task SaveAsync(Order order, CancellationToken cancellationToken = default)
        {
            _orders[order.Id] = order;
            SaveCalls++;
            return Task.CompletedTask;
        }
    }
}
