namespace SreDemo.Web.Models;

public class IntegrationViewModel
{
    public string KeyVaultName { get; set; } = string.Empty;
    public bool KeyVaultConnected { get; set; }
    public string? DemoSecretValue { get; set; }
    public string? KeyVaultError { get; set; }

    public bool SqlConnected { get; set; }
    public int SqlUserCount { get; set; }
    public string? SqlError { get; set; }

    public string? AppGatewayUrl { get; set; }
}
