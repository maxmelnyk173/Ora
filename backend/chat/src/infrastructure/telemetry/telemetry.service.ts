import { Injectable, OnModuleInit, Logger, Inject } from '@nestjs/common';
import { ConfigType } from '@nestjs/config';
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-grpc';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-grpc';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { resourceFromAttributes } from '@opentelemetry/resources';
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions';
import { BatchLogRecordProcessor } from '@opentelemetry/sdk-logs';

import telemetryConfig from '../../config/telemetry.config';
import serverConfig from '../../config/server.config';

@Injectable()
export class TelemetryService implements OnModuleInit {
  private readonly logger = new Logger(TelemetryService.name);
  private sdk?: NodeSDK;

  constructor(
    @Inject(telemetryConfig.KEY)
    private readonly telConfig: ConfigType<typeof telemetryConfig>,
    @Inject(serverConfig.KEY)
    private readonly srvConfig: ConfigType<typeof serverConfig>,
  ) {}

  async onModuleInit() {
    if (
      !this.telConfig.enableLogging &&
      !this.telConfig.enableMetrics &&
      !this.telConfig.enableTracing
    ) {
      this.logger.log('OpenTelemetry is disabled');
      return;
    }

    const endpoint = this.telConfig.endpoint;
    this.logger.log(`Initializing OpenTelemetry with endpoint: ${endpoint}`);

    const resource = resourceFromAttributes({
      [ATTR_SERVICE_NAME]: this.srvConfig.name,
      [ATTR_SERVICE_VERSION]: this.srvConfig.version,
    });

    const traceExporter = this.telConfig.enableTracing
      ? new OTLPTraceExporter({ url: endpoint })
      : undefined;

    const metricReader = this.telConfig.enableMetrics
      ? new PeriodicExportingMetricReader({
          exporter: new OTLPMetricExporter({ url: endpoint }),
          exportIntervalMillis: 60_000,
        })
      : undefined;

    const logRecordProcessors = this.telConfig.enableLogging
      ? [new BatchLogRecordProcessor(new OTLPLogExporter({ url: endpoint }))]
      : [];

    this.sdk = new NodeSDK({
      resource,
      traceExporter,
      metricReader,
      logRecordProcessors,
      instrumentations: [
        getNodeAutoInstrumentations({
          '@opentelemetry/instrumentation-fs': { enabled: false },
        }),
      ],
    });

    try {
      this.sdk.start();
      this.logger.log('OpenTelemetry initialized successfully');
    } catch (error) {
      this.logger.error('Failed to initialize OpenTelemetry', error as Error);
    }

    // --- Graceful shutdown ---
    process.on('SIGTERM', async () => {
      try {
        await this.sdk?.shutdown();
        this.logger.log('OpenTelemetry shut down successfully');
      } catch (error) {
        this.logger.error('Error shutting down OpenTelemetry', error as Error);
      }
    });
  }
}
