import { Injectable, NestMiddleware } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { LoggerService } from 'src/infrastructure/logging/logger.service';
import {
  requestContext,
  RequestContextData,
} from 'src/infrastructure/logging/request-context';

@Injectable()
export class LoggingMiddleware implements NestMiddleware {
  constructor(private readonly logger: LoggerService) {}

  use(req: any, res: any, next: () => void) {
    const start = Date.now();

    const ctx: RequestContextData = {
      request_id: randomUUID(),
      http_method: req.method,
      http_path: req.originalUrl || req.url,
      http_query: req.query ? JSON.stringify(req.query) : '',
      client_ip:
        req.ip ||
        req.headers['x-forwarded-for'] ||
        req.connection?.remoteAddress,
      user_id: this.extractUserId(req),
    };

    requestContext.run(ctx, () => {
      res.on('finish', () => {
        const duration = Date.now() - start;
        ctx.status_code = res.statusCode;
        ctx.duration_ms = duration;

        if (res.statusCode >= 500) {
          this.logger.error(
            'Request completed with server error',
            undefined,
            'HttpLogger',
          );
        } else if (res.statusCode >= 400) {
          this.logger.warn('Request completed with user error', 'HttpLogger');
        } else {
          this.logger.log('Request completed successfully', 'HttpLogger');
        }
      });

      next();
    });
  }

  private extractUserId(req: any): string {
    const authHeader = req.headers['authorization'];
    if (!authHeader) return 'unknown';

    const token = authHeader.split(' ')[1];
    if (!token) return 'unknown';

    try {
      const payload = JSON.parse(
        Buffer.from(token.split('.')[1], 'base64').toString(),
      );
      return payload?.sub ?? 'unknown';
    } catch {
      return 'unknown';
    }
  }
}
