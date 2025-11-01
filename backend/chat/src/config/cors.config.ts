import { registerAs } from '@nestjs/config';

export default registerAs('cors', () => ({
  allowCredentials: process.env.ALLOWED_CREDENTIALS === 'true',
  allowOrigins: process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',').map((origin) => origin.trim())
    : ['*'],
  allowHeaders: process.env.ALLOWED_HEADERS
    ? process.env.ALLOWED_HEADERS.split(',').map((header) => header.trim())
    : ['Content-Type', 'Authorization', 'X-Request-ID', 'X-Correlation-ID'],
  allowMethods: process.env.ALLOWED_METHODS
    ? process.env.ALLOWED_METHODS.split(',').map((method) => method.trim())
    : ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  maxAge: parseInt(process.env.MAX_AGE || '86400', 10),
}));
