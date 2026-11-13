using Orders.Application;
using Orders.Domain;
using Orders.Infrastructure;
using Xunit;

namespace Orders.UnitTests;

public sealed class BoundaryTests
{
    [Theory]
    [InlineData(0, 100)]
    [InlineData(30, 70)]
    [InlineData(0.01, 99.99)]
    [InlineData(29.99, 70.01)]
    public void Boundaries(decimal percentage, decimal total)
    {
        var order = new Order(Guid.NewGuid(), 100m);
        order.ApplyDiscount(" SAVE ", percentage);
        Assert.Equal(total, order.Total);
        Assert.Equal("SAVE", order.DiscountCode);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public void EmptyCodeDoesNotMutateOrder(string? code)
    {
        var order = new Order(Guid.NewGuid(), 100m);
        order.ApplyDiscount("VALID", 20);
        Assert.Throws<ArgumentException>(() => order.ApplyDiscount(code!, 10));
        Assert.Equal(80, order.Total);
        Assert.Equal("VALID", order.DiscountCode);
    }

    [Theory]
    [InlineData(-0.01)]
    [InlineData(30.01)]
    public void InvalidPercentagePreservesDiscount(decimal percentage)
    {
        var order = new Order(Guid.NewGuid(), 100);
        order.ApplyDiscount("VALID", 20);
        Assert.Throws<ArgumentOutOfRangeException>(() => order.ApplyDiscount("BAD", percentage));
        Assert.Equal(80, order.Total);
    }

    [Fact]
    public void ZeroSubtotalNeverBecomesNegative()
    {
        var order = new Order(Guid.NewGuid(), 0);
        order.ApplyDiscount("MAX", 30);
        Assert.Equal(0, order.Total);
    }

    [Fact]
    public void InvalidOrderIsRejected()
    {
        Assert.Throws<ArgumentException>(() => new Order(Guid.Empty, 100));
        Assert.Throws<ArgumentOutOfRangeException>(() => new Order(Guid.NewGuid(), -0.01m));
    }

    [Fact]
    public async Task MissingOrderReturnsNullWithoutSaving()
    {
        var repository = new MissingRepository();
        Assert.Null(await new ApplyDiscountHandler(repository).HandleAsync(Guid.NewGuid(), "SAVE20", 20));
        Assert.False(repository.Saved);
    }

    [Fact]
    public async Task ActualRepositoryRetainsUpdatedTotal()
    {
        var order = new Order(GetDemoOrderHandler.OrderId, 100);
        var repository = new InMemoryOrderRepository(order);
        await new ApplyDiscountHandler(repository).HandleAsync(order.Id, "SAVE20", 20);
        var loaded = await new GetDemoOrderHandler(repository).HandleAsync();
        Assert.Equal(80, loaded!.Total);
    }

    [Fact]
    public async Task CancelledRepositoryAccessIsRejected()
    {
        var repository = new InMemoryOrderRepository(new Order(GetDemoOrderHandler.OrderId, 100));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            repository.GetByIdAsync(GetDemoOrderHandler.OrderId, new CancellationToken(true)));
    }

    private sealed class MissingRepository : IOrderRepository
    {
        public bool Saved { get; private set; }
        public Task<Order?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default) => Task.FromResult<Order?>(null);
        public Task SaveAsync(Order order, CancellationToken cancellationToken = default)
        {
            Saved = true;
            return Task.CompletedTask;
        }
    }
}
