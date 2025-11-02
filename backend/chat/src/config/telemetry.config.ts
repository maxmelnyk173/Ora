import { registerAs } from '@nestjs/config';

export default registerAs('telemetry', () => ({
  endpoint: process.env.OTEL_GRPC_URL || 'http://localhost:4317',
  // enableTracing: process.env.CHAT_OTEL_TRACING === 'true',
  // enableMetrics: process.env.CHAT_OTEL_METRICS === 'true',
  // enableLogging: process.env.CHAT_OTEL_LOGGING === 'true',
  enableTracing: true,
  enableMetrics: true,
  enableLogging: true,
}));
