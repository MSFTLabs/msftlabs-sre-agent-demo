using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace SreDemo.Web.Controllers;

[Authorize(Roles = "Admin")]
public class AdminController : Controller
{
    private readonly ILogger<AdminController> _logger;
    private readonly IConfiguration _configuration;
    private readonly IHttpClientFactory _httpClientFactory;

    public AdminController(ILogger<AdminController> logger, IConfiguration configuration, IHttpClientFactory httpClientFactory)
    {
        _logger = logger;
        _configuration = configuration;
        _httpClientFactory = httpClientFactory;
    }

    public IActionResult Index()
    {
        _logger.LogInformation("Admin page accessed by {User}", User.Identity?.Name);
        return View();
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> TriggerSqlInjection()
    {
        var gatewayUrl = _configuration["AppGatewayUrl"];
        if (string.IsNullOrEmpty(gatewayUrl))
            return Json(new { error = "AppGatewayUrl not configured" });

        var patterns = new[]
        {
            "?id=1' OR '1'='1",
            "?search='; DROP TABLE Users;--",
            "?q=1 UNION SELECT username,password FROM Users",
            "?input=<script>alert('xss')</script>",
            "?file=../../etc/passwd",
        };

        var client = _httpClientFactory.CreateClient();
        client.Timeout = TimeSpan.FromSeconds(10);
        var results = new List<object>();
        var blockedCount = 0;

        foreach (var pattern in patterns)
        {
            var target = $"{gatewayUrl.TrimEnd('/')}/{pattern}";
            try
            {
                var response = await client.GetAsync(target);
                var blocked = response.StatusCode == System.Net.HttpStatusCode.Forbidden;
                if (blocked) blockedCount++;
                results.Add(new { pattern, status = (int)response.StatusCode, blocked });
                if (blocked)
                    _logger.LogWarning("WAF blocked request: {Pattern} (HTTP 403)", pattern);
            }
            catch (Exception ex)
            {
                results.Add(new { pattern, error = ex.Message });
            }
        }

        _logger.LogInformation("WAF SQL injection test: {Blocked}/{Total} patterns blocked", blockedCount, patterns.Length);

        return Json(new
        {
            status = "completed",
            totalPatterns = patterns.Length,
            blockedCount,
            results
        });
    }
}
