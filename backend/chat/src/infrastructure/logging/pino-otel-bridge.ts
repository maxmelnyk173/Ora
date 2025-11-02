import { logs, LogRecord, SeverityNumber } from '@opentelemetry/api-logs';
import { Writable } from 'stream';

export class PinoToOtelStream extends Writable {
  private readonly otelLogger = logs.getLogger('pino-bridge');

  constructor() {
    super({ objectMode: true });
  }

  _write(chunk: any, _enc: string, callback: (error?: Error | null) => void) {
    try {
      const log = typeof chunk === 'string' ? JSON.parse(chunk) : chunk;
      const severity = this.mapLevel(log.level);

      const record: LogRecord = {
        body: log.msg,
        severityNumber: severity,
        severityText: log.level?.toString(),
        attributes: {
          context: log.context,
          ...log,
        },
      };

      this.otelLogger.emit(record);
    } catch (err) {
      return callback(err as Error);
    }
    callback();
  }

  private mapLevel(level: number): SeverityNumber {
    if (level >= 60) return SeverityNumber.FATAL;
    if (level >= 50) return SeverityNumber.ERROR;
    if (level >= 40) return SeverityNumber.WARN;
    if (level >= 30) return SeverityNumber.INFO;
    if (level >= 20) return SeverityNumber.DEBUG;
    return SeverityNumber.TRACE;
  }
}
