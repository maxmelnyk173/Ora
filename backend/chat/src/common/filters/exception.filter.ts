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

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    let statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
    let message = 'Unhandled exception occurred';
    let code = 'ERROR_INTERNAL_SERVER';
    let details: any = undefined;

    if (exception instanceof NotFoundException) {
      statusCode = HttpStatus.NOT_FOUND;
      message = exception.message;
      code = exception.code ?? 'ERROR_NOT_FOUND';
      details = exception.details;
    } else if (exception instanceof ForbiddenException) {
      statusCode = HttpStatus.FORBIDDEN;
      message = exception.message;
      code = exception.code ?? 'ERROR_FORBIDDEN';
      details = exception.details;
    } else if (exception instanceof BaseException) {
      statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
      message = exception.message;
      code = exception.code ?? 'ERROR_BASE_EXCEPTION';
      details = exception.details;
    } else if (exception instanceof HttpException) {
      statusCode = exception.getStatus();
      const res = exception.getResponse();
      if (typeof res === 'string') {
        message = res;
        code = 'ERROR_HTTP_EXCEPTION';
      } else if (typeof res === 'object' && res !== null) {
        const resObj = res as any;
        message = resObj.message ?? message;
        code = resObj.code ?? 'ERROR_HTTP_EXCEPTION';
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

    return this.writeErrorResponse(
      response,
      statusCode,
      message,
      code,
      details,
    );
  }

  private writeErrorResponse(
    response: Response,
    statusCode: number,
    message: string,
    code: string,
    details: any,
  ) {
    const errorResponse = {
      message,
      code,
      details,
    };

    response.status(statusCode).json(errorResponse);
  }
}
