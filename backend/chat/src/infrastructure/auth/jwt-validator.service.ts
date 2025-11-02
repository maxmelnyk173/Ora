import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigType } from '@nestjs/config';
import {
  jwtVerify,
  JWTPayload,
  createRemoteJWKSet,
  JWTVerifyGetKey,
} from 'jose';
import { UnauthorizedException } from 'src/common/exceptions/unauthorized.exception';
import keycloakConfig from 'src/config/keycloak.config';

export class ValidatedToken implements JWTPayload {
  [propName: string]: unknown;
  iss?: string;
  sub?: string;
  aud?: string | string[];
  jti?: string;
  nbf?: number;
  exp?: number;
  iat?: number;
}

@Injectable()
export class JwtValidatorService implements OnModuleInit {
  private readonly logger = new Logger(JwtValidatorService.name);
  private readonly audience: string;
  private readonly issuer: string;
  private readonly jwksUri: string;
  private jwks: JWTVerifyGetKey;

  constructor(
    @Inject(keycloakConfig.KEY)
    private readonly keycloakCfg: ConfigType<typeof keycloakConfig>,
  ) {
    this.audience = this.keycloakCfg.audience!;
    this.issuer = this.keycloakCfg.issuer!;
    this.jwksUri = this.keycloakCfg.jwksUri!;
  }

  onModuleInit() {
    this.logger.log(`Initializing remote JWKS from ${this.jwksUri}`);
    this.jwks = createRemoteJWKSet(new URL(this.jwksUri));
  }

  async validateToken(token: string): Promise<ValidatedToken> {
    try {
      const { payload } = await jwtVerify(token, this.jwks, {
        issuer: this.issuer,
        audience: this.audience,
      });

      return payload as ValidatedToken;
    } catch (error) {
      this.logger.warn(
        `JWT validation failed: ${error.message} (Code: ${error.code})`,
      );
      throw new UnauthorizedException('Invalid or expired token');
    }
  }

  extractTokenFromHeader(authorization: string | undefined): string | null {
    if (!authorization) {
      return null;
    }
    const [type, token] = authorization.split(' ');
    return type === 'Bearer' ? token : null;
  }
}
