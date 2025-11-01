export const ErrorCodes = {
  ACCESS_DENIED: 'ERROR_ACCESS_DENIED',
  AUTHORIZATION_FAILED: 'AUTHORIZATION_FAILED',
  INTERNAL_SERVER: 'ERROR_INTERNAL_SERVER',
} as const;

export type ErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes];
