namespace Learning.Infrastructure.Data;

public class DbOptions
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;

    public string GetConnectionString()
        => $"Host={Host};Port={Port};Database={Name};Username={Username};Password={Password};TrustServerCertificate=True;";
}