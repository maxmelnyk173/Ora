using FluentValidation;
using Learning.Features.Categories;
using Learning.Features.Enrollments;
using Learning.Features.Products;
using Learning.Features.Profiles;
using Learning.Infrastructure.Data;
using Learning.Infrastructure.Identity;
using Learning.Infrastructure.Keycloak;
using Learning.Infrastructure.Messaging.RabbitMq;
using Learning.Infrastructure.OpenApi;
using Learning.Infrastructure.Telemetry;
using Learning.Middleware;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Serilog;
using System.Security.Claims;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration.AddEnvironmentVariables();

const string corsPolicy = "CorsPolicy";
builder.Services.AddCors(options =>
{
    options.AddPolicy(corsPolicy,
        pb =>
        {
            pb.WithOrigins(builder.Configuration["ALLOWED_ORIGINS"]?.Split(","))
              .WithMethods(builder.Configuration["ALLOWED_METHODS"]?.Split(","))
              .WithHeaders(builder.Configuration["ALLOWED_HEADERS"]?.Split(","));
        });
});

builder.Services.AddHealthChecks();
builder.Services.AddHttpContextAccessor();
builder.Services.AddOpenApi(o => { o.AddDocumentTransformer<BearerSecuritySchemeTransformer>(); });

var telemetryOptions = builder.Configuration.GetSection(nameof(TelemetryOptions)).Get<TelemetryOptions>();
ArgumentNullException.ThrowIfNull(telemetryOptions);

if (telemetryOptions.OtelTelemetryEnabled())
{
    builder.Services.AddTelemetry(telemetryOptions);
}
builder.Host.ConfigureSerilog(telemetryOptions);

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        var keycloakOptions = builder.Configuration.GetSection(nameof(KeycloakOptions)).Get<KeycloakOptions>();
        ArgumentNullException.ThrowIfNull(keycloakOptions);

        o.RequireHttpsMetadata = false;

        o.Authority = keycloakOptions.Authority;
        o.Audience = keycloakOptions.Audience;

        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidIssuer = keycloakOptions.Authority,
            ValidAudience = keycloakOptions.Audience,
            RoleClaimType = keycloakOptions.RoleAddress
        };
    });

builder.Services.AddAuthorizationBuilder()
    .AddPolicy(AuthorizationPolicies.RequireEducatorRole, p => p.RequireClaim(ClaimTypes.Role, KeycloakRoles.EducatorRole))
    .SetFallbackPolicy(new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());

var dbOptions = builder.Configuration.GetSection(nameof(DbOptions)).Get<DbOptions>();
ArgumentNullException.ThrowIfNull(dbOptions);
builder.Services.AddDbContext<AppDbContext>(o => o.UseNpgsql(dbOptions.GetConnectionString()).UseSnakeCaseNamingConvention());

builder.Services.AddValidatorsFromAssembly(typeof(Program).Assembly);

builder.Services.AddRabbitMq(builder.Configuration);

builder.Services.AddScoped<ICurrentUser, CurrentUser>();
builder.Services.AddScoped<IClaimsTransformation, KeycloakClaimsTransformer>();

builder.Services.AddEnrollments();
builder.Services.AddProducts();
builder.Services.AddProfiles();
builder.Services.AddCategories();

var app = builder.Build();

app.UseCors(corsPolicy);
app.UseHttpsRedirection();

const string openApiUrl = "/openapi/v1/openapi.json";
app.MapOpenApi(openApiUrl).AllowAnonymous();
app.UseSwaggerUI(o => { o.SwaggerEndpoint(openApiUrl, "v1"); });

app.Use(async (context, next) =>
{
    if (context.Request.Method == HttpMethods.Options)
    {
        context.Response.StatusCode = StatusCodes.Status204NoContent;
        return;
    }
    await next();
});

app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseMiddleware<LoggingMiddleware>();
app.UseSerilogRequestLogging();
app.MapPrometheusScrapingEndpoint();
app.UseAuthentication();
app.UseAuthorization();

app.MapHealthChecks("/health/readiness").AllowAnonymous();
app.MapHealthChecks("/health/liveness").AllowAnonymous();

app.MapCategoryEndpoints();
app.MapProductEndpoints();
app.MapEnrollmentEndpoints();

app.Run();
