import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import serverConfig from './config/server.config';
import corsConfig from './config/cors.config';
import loggingConfig from './config/logging.config';
import { HealthModule } from './features/health/health.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [serverConfig, corsConfig, loggingConfig],
      envFilePath: ['.env.local', '.env'],
      cache: true,
    }),
    HealthModule,
  ],
  controllers: [],
  providers: [],
})
export class AppModule {}
