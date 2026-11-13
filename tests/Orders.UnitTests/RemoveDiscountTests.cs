using Orders.Application;
using Orders.Domain;
using Xunit;

namespace Orders.UnitTests;

public sealed class RemoveDiscountTests
{
    [Fact]
    public void RemovingDiscountIsIdempotent()
    {
        var order = new Order(Guid.NewGuid(), 100);
        order.ApplyDiscount("SAVE20", 20);
        order.RemoveDiscount();
        order.RemoveDiscount();
        Assert.Equal(100, order.Total);
        Assert.Equal(100, order.Subtotal);
        Assert.Equal(0, order.DiscountPercentage);
        Assert.Null(order.DiscountCode);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task HandlerPersistsOnlyExistingOrder(bool exists)
    {
        var repository = new StubRepository(exists);
        var result = await new RemoveDiscountHandler(repository).HandleAsync(Guid.NewGuid());
        Assert.Equal(exists, result is not null);
        Assert.Equal(exists, repository.Saved);
        if (result is not null)
        {
            Assert.Equal(100, result.Total);
            Assert.Null(result.DiscountCode);
        }
    }

    private sealed class StubRepository(bool exists) : IOrderRepository
    {
        public bool Saved { get; private set; }
        public Task<Order?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
        {
            if (!exists) return Task.FromResult<Order?>(null);
            var order = new Order(id, 100);
            order.ApplyDiscount("SAVE20", 20);
            return Task.FromResult<Order?>(order);
        }
        public Task SaveAsync(Order order, CancellationToken cancellationToken = default)
        {
            Saved = true;
            return Task.CompletedTask;
        }
    }
}
