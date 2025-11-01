import { registerAs } from '@nestjs/config';

export default registerAs('server', () => ({
  port: parseInt(process.env.PORT || process.env.CHAT_PORT || '3000', 10),
  name: process.env.CHAT_NAME || 'chat-service',
  environment: process.env.ENV || 'development',
  version: process.env.CHAT_VERSION || '1.0.0',
}));
