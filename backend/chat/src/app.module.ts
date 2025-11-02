import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import serverConfig from './config/server.config';
import corsConfig from './config/cors.config';
import loggingConfig from './config/logging.config';
import telemetryConfig from './config/telemetry.config';
import { HealthModule } from './features/health/health.module';
import { LoggerService } from './infrastructure/logging/logger.service';
import { TelemetryService } from './infrastructure/telemetry/telemetry.service';
import { LoggingMiddleware } from './middleware/logging.middleware';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [serverConfig, corsConfig, loggingConfig, telemetryConfig],
      envFilePath: ['.env.local', '.env'],
      cache: true,
    }),
    HealthModule,
  ],
  controllers: [],
  providers: [TelemetryService, LoggerService],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggingMiddleware).forRoutes('*path');
  }
}
