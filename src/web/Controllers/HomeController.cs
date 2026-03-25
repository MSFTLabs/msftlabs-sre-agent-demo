using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SreDemo.Web.Data;
using SreDemo.Web.Models;

namespace SreDemo.Web.Controllers;

public class HomeController : Controller
{
    private readonly ILogger<HomeController> _logger;
    private readonly ApplicationDbContext _context;

    public HomeController(ILogger<HomeController> logger, ApplicationDbContext context)
    {
        _logger = logger;
        _context = context;
    }

    public async Task<IActionResult> Index()
    {
        _logger.LogInformation("Home page visited");
        var page = await _context.SitePages.FirstAsync(p => p.Slug == "home" && p.IsActive);
        return View(page);
    }

    public async Task<IActionResult> AboutSre()
    {
        var page = await _context.SitePages.FirstAsync(p => p.Slug == "about-sre" && p.IsActive);
        return View(page);
    }

    public async Task<IActionResult> ContentPage(string slug)
    {
        if (string.IsNullOrEmpty(slug))
            return RedirectToAction("Index");

        var page = await _context.SitePages
            .FirstOrDefaultAsync(p => p.Slug == slug && p.IsActive);

        if (page == null)
            return NotFound();

        return View(page);
    }

    public async Task<IActionResult> ContentIndex()
    {
        var pages = await _context.SitePages
            .Where(p => p.IsActive)
            .OrderBy(p => p.SortOrder)
            .ToListAsync();

        return View(pages);
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View(new ErrorViewModel
        {
            RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier
        });
    }
}
