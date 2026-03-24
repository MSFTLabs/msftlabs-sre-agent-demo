using Microsoft.EntityFrameworkCore;
using SreDemo.Web.Models;

namespace SreDemo.Web.Data;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();
    public DbSet<SitePage> SitePages => Set<SitePage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<User>(entity =>
        {
            entity.HasIndex(e => e.Username).IsUnique();
            entity.HasIndex(e => e.Email).IsUnique();
        });

        modelBuilder.Entity<SitePage>(entity =>
        {
            entity.HasIndex(e => e.Slug).IsUnique();
        });
    }
}
