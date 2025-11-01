import { BaseException } from './base.exception';
import { ErrorCodes } from './errors.constants';

export class ForbiddenException extends BaseException {
  constructor() {
    super('Access Denied', ErrorCodes.ACCESS_DENIED);
  }
}
