namespace Learning.Infrastructure.Telemetry;

public class TelemetryOptions
{
    public string ServiceName { get; set; } = "learning-service";
    public string OpenTelemetryEndpoint { get; set; } = "http://localhost:4317";
    public bool EnableOtelTraces { get; set; } = true;
    public bool EnableOtelMetrics { get; set; } = true;
    public bool EnableOtelLogging { get; set; } = true;

    public bool OtelTelemetryEnabled()
    {
        return EnableOtelLogging || EnableOtelMetrics || EnableOtelTraces;
    }
}