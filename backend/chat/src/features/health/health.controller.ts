import { Controller, Get } from '@nestjs/common';
import { HealthCheck, HealthCheckService } from '@nestjs/terminus';
import { Public } from 'src/common/decorators/public.decorator';

@Controller('health')
@Public()
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
