using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using SreDemo.Web.Models;

namespace SreDemo.Web.Controllers;

public class HealthController : Controller
{
    private static string? _probeConnectionString;
    private readonly ILogger<HealthController> _logger;

    public HealthController(
        ILogger<HealthController> logger,
        IConfiguration configuration)
    {
        _logger = logger;

        // Build a dedicated probe connection string with 5-second pool lifetime (once)
        if (_probeConnectionString == null)
        {
            var baseCs = configuration.GetConnectionString("DefaultConnection");
            if (!string.IsNullOrEmpty(baseCs))
            {
                var csb = new SqlConnectionStringBuilder(baseCs)
                {
                    LoadBalanceTimeout = 5  // Connections older than 5s are discarded on return to pool
                };
                csb.ApplicationName = "HealthProbe"; // Separate pool from EF Core
                _probeConnectionString = csb.ConnectionString;
            }
        }
    }

    public async Task<IActionResult> Probe()
    {
        var model = new HealthProbeViewModel
        {
            CheckedAt = DateTime.UtcNow,
            ServerName = Environment.MachineName
        };

        // Test SQL Connectivity via dedicated connection pool (5s lifetime)
        try
        {
            await using var conn = new SqlConnection(_probeConnectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM SitePages";
            var count = await cmd.ExecuteScalarAsync();
            model.SqlPageCount = Convert.ToInt32(count);
            model.SqlHealthy = true;
        }
        catch (Exception ex)
        {
            model.SqlHealthy = false;
            model.SqlError = ex.Message;
            _logger.LogError(ex, "Health probe: SQL connectivity check failed");
        }

        model.OverallHealthy = model.SqlHealthy;

        _logger.LogInformation(
            "Health probe: Overall={Overall}, SQL={SQL}",
            model.OverallHealthy ? "Healthy" : "Unhealthy",
            model.SqlHealthy);

        if (!model.OverallHealthy)
            Response.StatusCode = 503;

        return View(model);
    }
}
