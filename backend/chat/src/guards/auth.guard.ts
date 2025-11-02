import {
  CanActivate,
  ExecutionContext,
  Injectable,
  Logger,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtValidatorService } from 'src/infrastructure/auth/jwt-validator.service';
import { IS_PUBLIC_KEY } from '../common/decorators/public.decorator';
import { UnauthorizedException } from '../common/exceptions/unauthorized.exception';

@Injectable()
export class AuthGuard implements CanActivate {
  private readonly fallbackLogger = new Logger(AuthGuard.name);

  constructor(
    private readonly jwtValidator: JwtValidatorService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) {
      return true;
    }

    const request = context.switchToHttp().getRequest();

    const logger =
      request.log?.child({ context: AuthGuard.name }) || this.fallbackLogger;

    const token = this.jwtValidator.extractTokenFromHeader(
      request.headers.authorization,
    );

    if (!token) {
      logger.warn('No authorization token provided');
      throw new UnauthorizedException('No token provided');
    }

    try {
      const payload = await this.jwtValidator.validateToken(token);
      request.user = payload;
      return true;
    } catch (error) {
      logger.warn(`Authentication failed: ${error.message}`);
      if (error instanceof UnauthorizedException) {
        throw error;
      }
      throw new UnauthorizedException('Authentication failed');
    }
  }
}
