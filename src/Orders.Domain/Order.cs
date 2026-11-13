namespace Orders.Domain;

public sealed class Order
{
    public Guid Id { get; }
    public decimal Subtotal { get; }
    public decimal DiscountPercentage { get; private set; }
    public string? DiscountCode { get; private set; }
    public decimal Total => Math.Round(Subtotal * (1 - DiscountPercentage / 100m), 2);

    public Order(Guid id, decimal subtotal)
    {
        if (id == Guid.Empty)
        {
            throw new ArgumentException("Order id is required.", nameof(id));
        }

        if (subtotal < 0m)
        {
            throw new ArgumentOutOfRangeException(nameof(subtotal));
        }

        Id = id;
        Subtotal = subtotal;
    }

    public void RemoveDiscount()
    {
        DiscountPercentage = 0;
        DiscountCode = null;
    }

    public void ApplyDiscount(string code, decimal percentage)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            throw new ArgumentException("Discount code is required.", nameof(code));
        }

        if (percentage < 0m || percentage > 30m)
        {
            throw new ArgumentOutOfRangeException(nameof(percentage), "Discount must be between 0% and 30%.");
        }

        DiscountCode = code.Trim();
        DiscountPercentage = percentage;
    }
}
