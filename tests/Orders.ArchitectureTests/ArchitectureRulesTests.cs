using System.Xml.Linq;
using Orders.Application;
using Orders.Domain;
using Xunit;

namespace Orders.ArchitectureTests;

public sealed class ArchitectureRulesTests
{
    [Fact]
    public void ARCH001_ApplicationMustNotReferenceInfrastructure()
    {
        var dependencies = typeof(ApplyDiscountHandler).Assembly.GetReferencedAssemblies()
            .Select(x => x.Name).ToArray();

        Assert.DoesNotContain("Orders.Infrastructure", dependencies);
    }

    [Theory]
    [InlineData("Orders.Application", "Orders.Infrastructure", "ARCH001")]
    [InlineData("Orders.Domain", "Orders.Application", "ARCH002")]
    [InlineData("Orders.Domain", "Orders.Infrastructure", "ARCH002")]
    public void ProjectReferencesRespectBoundaries(string project, string forbidden, string rule)
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !File.Exists(Path.Combine(root.FullName, "Orders.slnx")))
            root = root.Parent;
        Assert.NotNull(root);
        var file = Path.Combine(root.FullName, "src", project, project + ".csproj");
        var references = XDocument.Load(file).Descendants("ProjectReference")
            .Select(x => ((string?)x.Attribute("Include"))?.Replace('\\', '/'));
        Assert.True(!references.Any(x => x?.Contains(forbidden + ".csproj", StringComparison.OrdinalIgnoreCase) == true),
            $"{rule}: {file} references {forbidden}");
    }

    [Fact]
    public void ARCH002_DomainMustNotReferenceApplicationOrInfrastructure()
    {
        var dependencies = typeof(Order).Assembly.GetReferencedAssemblies()
            .Select(x => x.Name).ToArray();

        Assert.DoesNotContain("Orders.Application", dependencies);
        Assert.DoesNotContain("Orders.Infrastructure", dependencies);
    }
}
