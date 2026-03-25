using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Azure.Security.KeyVault.Secrets;
using SreDemo.Web.Data;
using SreDemo.Web.Models;

namespace SreDemo.Web.Controllers;

public class HealthController : Controller
{
    private readonly ApplicationDbContext _context;
    private readonly ILogger<HealthController> _logger;
    private readonly IConfiguration _configuration;

    public HealthController(
        ApplicationDbContext context,
        ILogger<HealthController> logger,
        IConfiguration configuration)
    {
        _context = context;
        _logger = logger;
        _configuration = configuration;
    }

    public async Task<IActionResult> Probe()
    {
        var model = new HealthProbeViewModel
        {
            CheckedAt = DateTime.UtcNow,
            ServerName = Environment.MachineName
        };

        // 1. Test Managed Identity via Key Vault secret read
        var secretClient = HttpContext.RequestServices.GetService<SecretClient>();
        if (secretClient != null)
        {
            try
            {
                await secretClient.GetSecretAsync("demo-secret");
                model.ManagedIdentityHealthy = true;
            }
            catch (Exception ex)
            {
                model.ManagedIdentityHealthy = false;
                model.ManagedIdentityError = ex.Message;
                _logger.LogError(ex, "Health probe: Managed Identity / Key Vault check failed");
            }
        }
        else
        {
            model.ManagedIdentityHealthy = false;
            model.ManagedIdentityError = "SecretClient not configured (KeyVaultName not set)";
        }

        // 2. Test SQL Connectivity via EF Core
        try
        {
            model.SqlUserCount = await _context.Users.CountAsync();
            model.SqlHealthy = true;
        }
        catch (Exception ex)
        {
            model.SqlHealthy = false;
            model.SqlError = ex.Message;
            _logger.LogError(ex, "Health probe: SQL connectivity check failed");
        }

        model.OverallHealthy = model.ManagedIdentityHealthy && model.SqlHealthy;

        _logger.LogInformation(
            "Health probe: Overall={Overall}, MI={MI}, SQL={SQL}",
            model.OverallHealthy ? "Healthy" : "Unhealthy",
            model.ManagedIdentityHealthy,
            model.SqlHealthy);

        if (!model.OverallHealthy)
            Response.StatusCode = 503;

        return View(model);
    }
}
