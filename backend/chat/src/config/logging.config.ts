import { registerAs } from '@nestjs/config';

export default registerAs('logging', () => ({
  level: process.env.LOG_LEVEL || 'info',
  prettyPrint:
    process.env.LOG_PRETTY_PRINT === 'true' ||
    process.env.NODE_ENV === 'development',
  redactPaths: process.env.LOG_REDACT_PATHS?.split(',') || [
    'req.headers.authorization',
    'req.headers.cookie',
    'password',
    'token',
    'apiKey',
  ],
}));
