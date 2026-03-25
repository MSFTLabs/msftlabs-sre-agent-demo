namespace SreDemo.Web.Models;

public class HealthProbeViewModel
{
    public bool OverallHealthy { get; set; }
    public DateTime CheckedAt { get; set; }
    public string ServerName { get; set; } = string.Empty;

    // SQL Connectivity
    public bool SqlHealthy { get; set; }
    public int SqlPageCount { get; set; }
    public string? SqlError { get; set; }

}
