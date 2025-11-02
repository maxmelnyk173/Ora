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
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { AuthGuard } from './guards/auth.guard';
import { GlobalExceptionFilter } from './common/filters/exception.filter';
import { JwtValidatorService } from './infrastructure/auth/jwt-validator.service';
import keycloakConfig from './config/keycloak.config';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [
        corsConfig,
        keycloakConfig,
        loggingConfig,
        serverConfig,
        telemetryConfig,
      ],
      envFilePath: ['.env.local', '.env'],
      cache: true,
    }),
    HealthModule,
  ],
  controllers: [],
  providers: [
    TelemetryService,
    LoggerService,
    JwtValidatorService,
    {
      provide: APP_GUARD,
      useClass: AuthGuard,
    },
    {
      provide: APP_FILTER,
      useClass: GlobalExceptionFilter,
    },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggingMiddleware).forRoutes('*path');
  }
}
