namespace SreDemo.Web.Models;

public class HealthProbeViewModel
{
    public bool OverallHealthy { get; set; }
    public DateTime CheckedAt { get; set; }
    public string ServerName { get; set; } = string.Empty;

    // Managed Identity (via Key Vault)
    public bool ManagedIdentityHealthy { get; set; }
    public string? ManagedIdentityError { get; set; }

    // SQL Connectivity
    public bool SqlHealthy { get; set; }
    public int SqlUserCount { get; set; }
    public string? SqlError { get; set; }

    // Function App API
    public bool FunctionAppHealthy { get; set; }
    public int FunctionAppStatusCode { get; set; }
    public string? FunctionAppUrl { get; set; }
    public string? FunctionAppError { get; set; }
}
