export class BaseException extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly details?: Record<string, any>,
  ) {
    super(message);
    Object.setPrototypeOf(this, new.target.prototype);
  }
}
