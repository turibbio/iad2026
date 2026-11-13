using Orders.Application;
using Orders.Domain;
using Orders.Infrastructure;
using Orders.Web.Components;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorComponents().AddInteractiveServerComponents();
builder.Services.AddScoped<IOrderRepository>(_ => new InMemoryOrderRepository(new Order(GetDemoOrderHandler.OrderId, 100m)));
builder.Services.AddScoped<ApplyDiscountHandler>();
builder.Services.AddScoped<GetDemoOrderHandler>();

var app = builder.Build();
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseAntiforgery();
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();
app.Run();
