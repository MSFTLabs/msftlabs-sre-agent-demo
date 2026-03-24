using System.Diagnostics;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Azure.Security.KeyVault.Secrets;
using SreDemo.Web.Data;
using SreDemo.Web.Models;

namespace SreDemo.Web.Controllers;

[Authorize]
public class DashboardController : Controller
{
    private readonly ApplicationDbContext _context;
    private readonly ILogger<DashboardController> _logger;
    private readonly IConfiguration _configuration;

    public DashboardController(ApplicationDbContext context, ILogger<DashboardController> logger, IConfiguration configuration)
    {
        _context = context;
        _logger = logger;
        _configuration = configuration;
    }

    public IActionResult Index()
    {
        var process = Process.GetCurrentProcess();

        var model = new DashboardViewModel
        {
            ServerName = Environment.MachineName,
            CurrentTimeUtc = DateTime.UtcNow,
            MemoryUsageMB = GC.GetTotalMemory(false) / (1024 * 1024),
            ProcessUptime = DateTime.UtcNow - process.StartTime.ToUniversalTime(),
            ThreadCount = process.Threads.Count,
            EnvironmentName = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Unknown",
            TotalUsers = _context.Users.Count(),
            RuntimeVersion = Environment.Version.ToString()
        };

        var loginTime = HttpContext.Session.GetString("LoginTime");
        ViewBag.LoginTime = loginTime;
        ViewBag.DisplayName = User.FindFirst("DisplayName")?.Value ?? User.Identity?.Name;

        _logger.LogInformation("Dashboard accessed by {User}", User.Identity?.Name);

        return View(model);
    }

    public IActionResult Profile()
    {
        var username = User.Identity?.Name;
        var user = _context.Users.FirstOrDefault(u => u.Username == username);

        if (user == null)
            return RedirectToAction("Login", "Account");

        var model = new ProfileEditViewModel
        {
            FirstName = user.FirstName,
            LastName = user.LastName,
            Email = user.Email,
            Bio = user.Bio ?? string.Empty
        };

        return View(model);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Profile(ProfileEditViewModel model)
    {
        if (!ModelState.IsValid)
            return View(model);

        var username = User.Identity?.Name;
        var user = _context.Users.FirstOrDefault(u => u.Username == username);

        if (user == null)
            return RedirectToAction("Login", "Account");

        // Check if email is taken by another user
        if (await _context.Users.AnyAsync(u => u.Email == model.Email && u.Username != username))
        {
            ModelState.AddModelError("Email", "Email is already in use.");
            return View(model);
        }

        user.FirstName = model.FirstName;
        user.LastName = model.LastName;
        user.Email = model.Email;
        user.DisplayName = $"{model.FirstName} {model.LastName}";
        user.Bio = model.Bio;

        if (!string.IsNullOrEmpty(model.NewPassword))
        {
            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(model.NewPassword);
        }

        await _context.SaveChangesAsync();
        _logger.LogInformation("User {Username} updated profile", username);

        TempData["Success"] = "Profile updated successfully.";
        return RedirectToAction("Profile");
    }

    public IActionResult Settings()
    {
        return View();
    }

    public async Task<IActionResult> Integration()
    {
        var model = new IntegrationViewModel
        {
            KeyVaultName = _configuration["KeyVaultName"] ?? "Not configured"
        };

        // Test Key Vault connectivity via managed identity
        var secretClient = HttpContext.RequestServices.GetService<SecretClient>();
        if (secretClient != null)
        {
            try
            {
                var secret = await secretClient.GetSecretAsync("demo-secret");
                model.KeyVaultConnected = true;
                model.DemoSecretValue = secret.Value.Value;
            }
            catch (Exception ex)
            {
                model.KeyVaultConnected = false;
                model.KeyVaultError = ex.Message;
                _logger.LogError(ex, "Failed to read Key Vault secret");
            }
        }
        else
        {
            model.KeyVaultError = "SecretClient not configured (KeyVaultName not set)";
        }

        // Test SQL connectivity via managed identity
        try
        {
            model.SqlUserCount = _context.Users.Count();
            model.SqlConnected = true;
        }
        catch (Exception ex)
        {
            model.SqlConnected = false;
            model.SqlError = ex.Message;
            _logger.LogError(ex, "Failed to query SQL database");
        }

        _logger.LogInformation("Integration page accessed by {User} - KV: {KvStatus}, SQL: {SqlStatus}",
            User.Identity?.Name,
            model.KeyVaultConnected ? "Connected" : "Disconnected",
            model.SqlConnected ? "Connected" : "Disconnected");

        return View(model);
    }
}
