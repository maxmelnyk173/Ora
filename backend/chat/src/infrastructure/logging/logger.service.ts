import {
  Injectable,
  LoggerService as NestLoggerService,
  Inject,
  OnModuleInit,
} from '@nestjs/common';
import pino, { LoggerOptions, Logger as PinoLogger } from 'pino';
import { ConfigType } from '@nestjs/config';
import { context, trace } from '@opentelemetry/api';
import loggingConfig from '../../config/logging.config';
import serverConfig from '../../config/server.config';
import { PinoToOtelStream } from './pino-otel-bridge';
import { requestContext } from './request-context';

function toSnakeCase(
  obj: Record<string, any> | undefined,
): Record<string, any> {
  if (!obj) return {};
  const out: Record<string, any> = {};
  for (const [k, v] of Object.entries(obj)) {
    out[k.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`)] = v;
  }
  return out;
}

@Injectable()
export class LoggerService implements NestLoggerService {
  private logger!: PinoLogger;

  constructor(
    @Inject(loggingConfig.KEY)
    private readonly logCfg: ConfigType<typeof loggingConfig>,
    @Inject(serverConfig.KEY)
    private readonly serverCfg: ConfigType<typeof serverConfig>,
  ) {
    const isProd = process.env.NODE_ENV === 'production';
    const pinoOptions: LoggerOptions = {
      name: this.serverCfg.name,
      level: this.logCfg.level,
      redact: { paths: this.logCfg.redactPaths, censor: '[REDACTED]' },
      mixin() {
        const span = trace.getSpan(context.active());
        const spanCtx = span?.spanContext();
        return spanCtx
          ? { trace_id: spanCtx.traceId, span_id: spanCtx.spanId }
          : {};
      },
    };

    const streams: pino.DestinationStream[] = [
      pino.destination(1),
      new PinoToOtelStream(),
    ];

    this.logger = pino(pinoOptions, pino.multistream(streams));
    this.logger.info('Logger initialized with OpenTelemetry bridge');
  }

  private enrich(meta?: Record<string, any>): Record<string, any> {
    const ctx = requestContext.getStore();
    const merged = { ...ctx, ...meta };
    return toSnakeCase(merged);
  }

  log(message: string, context?: string, meta?: Record<string, any>) {
    this.logger.info(this.enrich({ context, ...meta }), message);
  }
  error(
    message: string,
    trace?: string,
    context?: string,
    meta?: Record<string, any>,
  ) {
    this.logger.error(this.enrich({ context, stack: trace, ...meta }), message);
  }
  warn(message: string, context?: string, meta?: Record<string, any>) {
    this.logger.warn(this.enrich({ context, ...meta }), message);
  }
  debug(message: string, context?: string, meta?: Record<string, any>) {
    this.logger.debug(this.enrich({ context, ...meta }), message);
  }
  verbose(message: string, context?: string, meta?: Record<string, any>) {
    this.logger.trace(this.enrich({ context, ...meta }), message);
  }

  child(bindings: Record<string, any>): PinoLogger {
    return this.logger.child(bindings);
  }
  getPinoLogger(): PinoLogger {
    return this.logger;
  }
}
