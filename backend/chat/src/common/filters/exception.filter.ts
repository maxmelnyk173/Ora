import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Response } from 'express';
import { BaseException } from '../exceptions/base.exception';
import { ForbiddenException } from '../exceptions/forbidden.exception';
import { NotFoundException } from '../exceptions/not-found.exception';
import { UnauthorizedException } from '../exceptions/unauthorized.exception';

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  private readonly statusMap = new Map<Function, number>([
    [NotFoundException, HttpStatus.NOT_FOUND],
    [ForbiddenException, HttpStatus.FORBIDDEN],
    [UnauthorizedException, HttpStatus.UNAUTHORIZED],
    [BaseException, HttpStatus.INTERNAL_SERVER_ERROR],
  ]);

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    const { statusCode, message, code, details } =
      this.normalizeException(exception);

    return this.writeErrorResponse(
      response,
      statusCode,
      message,
      code,
      details,
    );
  }

  private normalizeException(exception: unknown): {
    statusCode: number;
    message: string;
    code?: string;
    details?: any;
  } {
    let statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
    let message = 'Unhandled exception occurred';
    let code: string | undefined;
    let details: any;

    for (const [ctor, status] of this.statusMap) {
      if (exception instanceof (ctor as any)) {
        statusCode = status;
        message = (exception as any).message;
        code = (exception as any).code;
        details = (exception as any).details;
        return { statusCode, message, code, details };
      }
    }

    if (exception instanceof HttpException) {
      statusCode = exception.getStatus();
      const res = exception.getResponse();
      if (typeof res === 'string') {
        message = res;
      } else if (res && typeof res === 'object') {
        const resObj = res as any;
        message = resObj.message ?? message;
        code = resObj.code;
        details = resObj.details;
      }
    } else if (exception instanceof Error) {
      this.logger.error(exception.stack, exception.message);
      message = exception.message;
    } else {
      this.logger.error(
        'Unknown non-error exception',
        JSON.stringify(exception),
      );
    }

    return { statusCode, message, code, details };
  }

  private writeErrorResponse(
    response: Response,
    statusCode: number,
    message: string,
    code?: string,
    details?: any,
  ) {
    response.status(statusCode).json({ message, code, details });
  }
}
