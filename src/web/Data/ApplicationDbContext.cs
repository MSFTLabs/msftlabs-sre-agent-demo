using Microsoft.EntityFrameworkCore;
using SreDemo.Web.Models;

// Note: Users table exists in the DB but is not mapped here.
// Only the admin account is seeded by scripts/seed-db and used for demos.

namespace SreDemo.Web.Data;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<SitePage> SitePages => Set<SitePage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<SitePage>(entity =>
        {
            entity.HasIndex(e => e.Slug).IsUnique();
        });
    }
}
