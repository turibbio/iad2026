using Bunit;
using Microsoft.Extensions.DependencyInjection;
using Orders.Application;
using Orders.Domain;
using Orders.Web.Components.Pages;
using Xunit;

namespace Orders.BlazorTests;

public sealed class HomeTests : BunitContext
{
    private readonly StubRepository _repository = new();

    public HomeTests()
    {
        Services.AddSingleton<IOrderRepository>(_repository);
        Services.AddScoped<GetDemoOrderHandler>();
        Services.AddScoped<ApplyDiscountHandler>();
        Services.AddScoped<RemoveDiscountHandler>();
    }

    [Fact]
    public void RendersOrderAndForm()
    {
        var page = Render<Home>();
        Assert.Contains("100,00", page.Find("[data-testid=total]").TextContent);
        Assert.Contains("Subtotale", page.Markup);
        Assert.Single(page.FindAll("form"));
        Assert.Equal("SAVE20", page.Find("#discount-code").GetAttribute("value"));
    }

    [Fact]
    public void ValidDiscountUpdatesTotalAndConfirmation()
    {
        var page = Render<Home>();
        page.Find("#discount-code").Change("SAVE20");
        page.Find("#discount-percentage").Change("20");
        page.Find("form").Submit();
        Assert.Contains("80,00", page.Find("[data-testid=total]").TextContent);
        Assert.Equal("Sconto applicato.", page.Find("[role=status]").TextContent);
        Assert.Equal(1, _repository.Saves);
    }

    [Theory]
    [InlineData("", "20", "Il codice è obbligatorio.")]
    [InlineData("   ", "20", "Il codice è obbligatorio.")]
    [InlineData("BAD", "31", "Lo sconto deve essere tra 0 e 30%.")]
    [InlineData("BAD", "-1", "Lo sconto deve essere tra 0 e 30%.")]
    public void InvalidInputsKeepTotal(string code, string percentage, string message)
    {
        var page = Render<Home>();
        page.Find("#discount-code").Change(code);
        page.Find("#discount-percentage").Change(percentage);
        page.Find("form").Submit();
        Assert.Contains(message, page.Markup);
        Assert.Contains("100,00", page.Find("[data-testid=total]").TextContent);
        Assert.Equal(0, _repository.Saves);
    }

    [Fact]
    public void InvalidSubmitClearsPreviousSuccess()
    {
        var page = Render<Home>();
        page.Find("form").Submit();
        page.Find("#discount-percentage").Change("31");
        page.Find("form").Submit();
        Assert.Empty(page.FindAll("[role=status]"));
        Assert.Contains("80,00", page.Find("[data-testid=total]").TextContent);
    }

    [Fact]
    public void RemoveDiscountUpdatesOrderAndConfirmation()
    {
        var page = Render<Home>();
        page.Find("form").Submit();
        Assert.Contains("80,00", page.Find("[data-testid=total]").TextContent);
        page.FindAll("button").Single(b => b.TextContent == "Rimuovi sconto").Click();
        Assert.Contains("100,00", page.Find("[data-testid=total]").TextContent);
        Assert.Equal("Sconto rimosso.", page.Find("[role=status]").TextContent);
        Assert.Equal(2, _repository.Saves);
    }

    [Fact]
    public void MissingOrderIsVisible()
    {
        _repository.Order = null;
        var page = Render<Home>();
        Assert.Contains("Ordine non disponibile.", page.Markup);
        Assert.Empty(page.FindAll("form"));
    }

    private sealed class StubRepository : IOrderRepository
    {
        public Order? Order { get; set; } = new(GetDemoOrderHandler.OrderId, 100);
        public int Saves { get; private set; }
        public Task<Order?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default) => Task.FromResult(Order);
        public Task SaveAsync(Order order, CancellationToken cancellationToken = default)
        {
            Saves++;
            Order = order;
            return Task.CompletedTask;
        }
    }
}
