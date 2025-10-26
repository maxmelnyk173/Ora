package com.example.profile.infrastructure.telemetry;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.propagation.ContextPropagators;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.OpenTelemetrySdkBuilder;
import io.opentelemetry.sdk.logs.SdkLoggerProvider;
import io.opentelemetry.sdk.logs.export.BatchLogRecordProcessor;
import io.opentelemetry.sdk.metrics.SdkMeterProvider;
import io.opentelemetry.sdk.metrics.export.PeriodicMetricReader;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import lombok.AllArgsConstructor;
import io.opentelemetry.exporter.otlp.logs.OtlpGrpcLogRecordExporter;
import io.opentelemetry.exporter.otlp.metrics.OtlpGrpcMetricExporter;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@AllArgsConstructor
public class TelemetryConfig {
    private final TelemetryProperties properties;

    @Bean
    OpenTelemetry openTelemetry() {
        if (!properties.getEnableLogs() && !properties.getEnableMetrics() && !properties.getEnableTraces()) {
            return OpenTelemetry.noop();
        }

        Resource resource = Resource.getDefault()
                .merge(Resource.create(Attributes.builder().put("service.name", properties.getServiceName()).build()));

        OpenTelemetrySdkBuilder otel = OpenTelemetrySdk.builder();

        if (properties.getEnableTraces()) {
            SdkTracerProvider sdkTracerProvider = SdkTracerProvider.builder()
                    .addSpanProcessor(BatchSpanProcessor.builder(
                            OtlpGrpcSpanExporter.builder().setEndpoint(properties.getEndpoint()).build()).build())
                    .setResource(resource)
                    .build();
            otel.setTracerProvider(sdkTracerProvider);
        }

        if (properties.getEnableMetrics()) {
            SdkMeterProvider sdkMeterProvider = SdkMeterProvider.builder()
                    .registerMetricReader(PeriodicMetricReader.builder(
                            OtlpGrpcMetricExporter.builder().setEndpoint(properties.getEndpoint()).build()).build())
                    .setResource(resource)
                    .build();
            otel.setMeterProvider(sdkMeterProvider);
        }

        if (properties.getEnableLogs()) {
            SdkLoggerProvider sdkLoggerProvider = SdkLoggerProvider.builder()
                    .addLogRecordProcessor(BatchLogRecordProcessor.builder(
                            OtlpGrpcLogRecordExporter.builder().setEndpoint(properties.getEndpoint()).build())
                            .build())
                    .setResource(resource)
                    .build();
            otel.setLoggerProvider(sdkLoggerProvider);
        }

        return otel.setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
                .buildAndRegisterGlobal();
    }

    @Bean
    Tracer tracer(OpenTelemetry openTelemetry) {
        return openTelemetry.getTracer(properties.getServiceName());
    }

    @Bean
    Meter meter(OpenTelemetry openTelemetry) {
        return openTelemetry.getMeter(properties.getServiceName());
    }
}