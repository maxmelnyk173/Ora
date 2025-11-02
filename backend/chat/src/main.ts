import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ConfigType } from '@nestjs/config';
import { Logger, ValidationPipe, VersioningType } from '@nestjs/common';
import serverConfig from './config/server.config';
import corsConfig from './config/cors.config';
import { LoggerService } from './infrastructure/logging/logger.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    bufferLogs: true,
  });

  const loggerService = app.get(LoggerService);
  app.useLogger(loggerService);

  const serverCfg = app.get<ConfigType<typeof serverConfig>>(serverConfig.KEY);
  const corsCfg = app.get<ConfigType<typeof corsConfig>>(corsConfig.KEY);

  app.enableCors({
    origin: corsCfg.allowOrigins,
    methods: corsCfg.allowMethods,
    allowedHeaders: corsCfg.allowHeaders,
    credentials: corsCfg.allowCredentials,
    maxAge: corsCfg.maxAge,
  });

  app.enableShutdownHooks();

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: {
        enableImplicitConversion: true,
      },
      validationError: {
        target: false,
        value: false,
      },
    }),
  );

  app.enableVersioning({
    type: VersioningType.URI,
    defaultVersion: '1',
  });

  app.setGlobalPrefix('api');

  await app.listen(serverCfg.port);

  const logger = new Logger('Bootstrap');
  logger.log(
    `Server "${serverCfg.name}" v${serverCfg.version} running on http://localhost:${serverCfg.port}`,
  );
  logger.log(`Environment: ${serverCfg.environment}`);
}
bootstrap();
