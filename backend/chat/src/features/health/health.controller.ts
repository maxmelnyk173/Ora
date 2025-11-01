import { Controller, Get } from '@nestjs/common';
import { HealthCheck, HealthCheckService } from '@nestjs/terminus';

@Controller('health')
export class HealthController {
  constructor(private health: HealthCheckService) {}

  @Get('readiness')
  @HealthCheck()
  readiness() {
    return this.health.check([]);
  }

  @Get('liveness')
  @HealthCheck()
  liveness() {
    return this.health.check([]);
  }
}
