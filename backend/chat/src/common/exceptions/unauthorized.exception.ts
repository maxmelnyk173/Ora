import { BaseException } from './base.exception';
import { ErrorCodes } from './errors.constants';

export class UnauthorizedException extends BaseException {
  constructor(message?: string) {
    super(message || 'Unauthorized', ErrorCodes.AUTHORIZATION_FAILED);
  }
}
