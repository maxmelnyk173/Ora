import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import serverConfig from './config/server.config';
import corsConfig from './config/cors.config';
import loggingConfig from './config/logging.config';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [serverConfig, corsConfig, loggingConfig],
      envFilePath: ['.env.local', '.env'],
      cache: true,
    }),
  ],
  controllers: [],
  providers: [],
})
export class AppModule {}
