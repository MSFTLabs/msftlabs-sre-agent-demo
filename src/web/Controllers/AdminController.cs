using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace SreDemo.Web.Controllers;

[Authorize(Roles = "Admin")]
public class AdminController : Controller
{
    private readonly ILogger<AdminController> _logger;
    private readonly IConfiguration _configuration;

    public AdminController(ILogger<AdminController> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    public IActionResult Index()
    {
        ViewBag.FunctionAppUrl = _configuration["FunctionAppUrl"] ?? string.Empty;
        _logger.LogInformation("Admin page accessed by {User}", User.Identity?.Name);
        return View();
    }
}
