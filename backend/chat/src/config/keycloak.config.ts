import { registerAs } from '@nestjs/config';

export default registerAs('keycloak', () => ({
  audience: process.env.KEYCLOAK_AUDIENCE,
  issuer: process.env.KEYCLOAK_ISSUER_URI,
  jwksUri: process.env.KEYCLOAK_JWKS_URI,
}));
