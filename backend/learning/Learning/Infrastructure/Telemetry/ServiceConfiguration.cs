using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using Serilog.Events;

namespace Learning.Infrastructure.Telemetry;

public static class ServiceConfiguration
{
    public static void ConfigureSerilog(this ConfigureHostBuilder hostBuilder, TelemetryOptions telemetryOptions)
    {
        hostBuilder.UseSerilog((context, services, serilogConfig) =>
        {
            serilogConfig.ReadFrom.Configuration(context.Configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext()
                .Enrich.WithProperty("service_name", telemetryOptions.ServiceName)
                .WriteTo.Console(restrictedToMinimumLevel: LogEventLevel.Information);

        }, writeToProviders: true);
    }

    public static void AddTelemetry(this IServiceCollection services, TelemetryOptions options)
    {
        if (!options.OtelTelemetryEnabled())
            return;

        var otel = services.AddOpenTelemetry()
            .ConfigureResource(r => r.AddService(options.ServiceName));

        if (options.EnableOtelTraces)
        {
            otel.WithTracing(tracing =>
            {
                tracing.AddHttpClientInstrumentation()
                    .AddAspNetCoreInstrumentation()
                    .AddOtlpExporter(o =>
                    {
                        o.Endpoint = new Uri(options.OpenTelemetryEndpoint);
                        o.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
                        o.ExportProcessorType = OpenTelemetry.ExportProcessorType.Batch;
                    });
            });
        }

        if (options.EnableOtelMetrics)
        {
            otel.WithMetrics(metrics =>
            {
                metrics.AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation()
                    .AddPrometheusExporter()
                    .AddOtlpExporter(o =>
                    {
                        o.Endpoint = new Uri(options.OpenTelemetryEndpoint);
                        o.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
                        o.ExportProcessorType = OpenTelemetry.ExportProcessorType.Batch;
                    });
            });
        }

        if (options.EnableOtelLogging)
        {
            otel.WithLogging(logging =>
            {
                logging.AddProcessor(new LogProcessor())
                    .AddOtlpExporter(o =>
                    {
                        o.Endpoint = new Uri(options.OpenTelemetryEndpoint);
                        o.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
                        o.ExportProcessorType = OpenTelemetry.ExportProcessorType.Batch;
                    });
            });
        }
    }
}