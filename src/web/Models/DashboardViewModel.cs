namespace SreDemo.Web.Models;

public class DashboardViewModel
{
    public string ServerName { get; set; } = string.Empty;
    public DateTime CurrentTimeUtc { get; set; }
    public long MemoryUsageMB { get; set; }
    public TimeSpan ProcessUptime { get; set; }
    public int ThreadCount { get; set; }
    public string EnvironmentName { get; set; } = string.Empty;
    public int TotalUsers { get; set; }
    public string RuntimeVersion { get; set; } = string.Empty;
}
