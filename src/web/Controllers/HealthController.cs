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
    private readonly IHttpClientFactory _httpClientFactory;

    public HealthController(
        ApplicationDbContext context,
        ILogger<HealthController> logger,
        IConfiguration configuration,
        IHttpClientFactory httpClientFactory)
    {
        _context = context;
        _logger = logger;
        _configuration = configuration;
        _httpClientFactory = httpClientFactory;
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

        // 3. Test Function App API connectivity
        var funcUrl = _configuration["FunctionAppUrl"];
        if (!string.IsNullOrEmpty(funcUrl))
        {
            model.FunctionAppUrl = funcUrl;
            try
            {
                var client = _httpClientFactory.CreateClient();
                client.Timeout = TimeSpan.FromSeconds(10);
                var response = await client.GetAsync($"{funcUrl.TrimEnd('/')}/api/health");
                model.FunctionAppHealthy = response.IsSuccessStatusCode;
                model.FunctionAppStatusCode = (int)response.StatusCode;
            }
            catch (Exception ex)
            {
                model.FunctionAppHealthy = false;
                model.FunctionAppError = ex.Message;
                _logger.LogError(ex, "Health probe: Function App API check failed");
            }
        }
        else
        {
            model.FunctionAppHealthy = false;
            model.FunctionAppError = "FunctionAppUrl not configured";
        }

        model.OverallHealthy = model.ManagedIdentityHealthy && model.SqlHealthy && model.FunctionAppHealthy;

        // Core health = MI + SQL (controls HTTP status for App Gateway probe)
        // Function App is a dependency check shown on the page but doesn't take down the web app
        var coreHealthy = model.ManagedIdentityHealthy && model.SqlHealthy;

        _logger.LogInformation(
            "Health probe: Core={Core}, MI={MI}, SQL={SQL}, FuncApp={Func}",
            coreHealthy ? "Healthy" : "Unhealthy",
            model.ManagedIdentityHealthy,
            model.SqlHealthy,
            model.FunctionAppHealthy);

        // Return 503 only when core dependencies (MI + SQL) fail
        if (!coreHealthy)
            Response.StatusCode = 503;

        return View(model);
    }
}
