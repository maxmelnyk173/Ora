from functools import lru_cache
import os

from typing import Any, Union


def get_env_var(name: str, default: Union[str, int, float, bool]) -> Any:
    value: str | None = os.getenv(key=name)

    if value is None:
        return default

    var_type = type(default)

    if var_type == bool:
        return value.lower() in ("true", "1", "t", "yes", "y")

    try:
        return var_type(value)
    except (ValueError, TypeError):
        return default


class AppSettings:
    name: str = get_env_var(name="PAYMENT_NAME", default="payment-service")
    version: str = get_env_var(name="PAYMENT_VERSION", default="1.0.0")
    port: str = get_env_var(name="PAYMENT_PORT", default="8086")
    host: str = get_env_var(name="PAYMENT_HOST", default="0.0.0.0")
    debug: bool = get_env_var(name="PAYMENT_DEBUG", default=False)


class CORSSettings:
    allow_credentials: bool = get_env_var(name="ALLOWED_CREDENTIALS", default=True)
    allow_origins: list[str] = get_env_var("ALLOWED_ORIGINS", default="").split(",")
    allow_methods: list[str] = get_env_var("ALLOWED_METHODS", default="").split(",")
    allow_headers: list[str] = get_env_var("ALLOWED_HEADERS", default="").split(",")


class DatabaseSettings:
    host: str = get_env_var(name="POSTGRES_HOST", default="localhost")
    port: int = get_env_var(name="POSTGRES_PORT", default=5432)
    name: str = get_env_var(name="PAYMENT_DB_NAME", default="")
    user: str = get_env_var(name="PAYMENT_DB_USER", default="")
    password: str = get_env_var(name="PAYMENT_DB_PASS", default="")
    pool_size: int = get_env_var(name="PAYMENT_DB_POOL_SIZE", default=10)
    max_overflow: int = get_env_var(name="PAYMENT_DB_MAX_OVERFLOW", default=20)
    timeout: int = get_env_var(name="PAYMENT_DB_TIMEOUT", default=30)
    debug: bool = get_env_var(name="PAYMENT_DB_DEBUG", default=False)


class KeycloakSettings:
    jwks_uri: str = get_env_var(name="KEYCLOAK_JWKS_URI", default="")
    issuer_uri: str = get_env_var(name="KEYCLOAK_ISSUER_URI", default="")
    audience: str = get_env_var(name="KEYCLOAK_AUDIENCE", default="")


class LogSettings:
    service_name: str = get_env_var(name="PAYMENT_NAME", default="payment-service")
    level: str = get_env_var(name="PAYMENT_LOG_LEVEL", default="INFO")


class TelemetrySettings:
    otel_endpoint: str = get_env_var(
        name="OTEL_GRPC_URL", default="http://localhost:4317"
    )
    enable_otel_tracing: str = get_env_var("PAYMENT_OTEL_TRACING", default=True)
    enable_otel_metrics: str = get_env_var("PAYMENT_OTEL_METRICS", default=True)
    enable_otel_logging: str = get_env_var("PAYMENT_OTEL_LOGGING", default=True)


class RabbitMqSettings:
    host: str = get_env_var("RABBITMQ_HOST", default="localhost")
    port: int = get_env_var("RABBITMQ_PORT", default=5672)
    username: str = get_env_var("RABBITMQ_USER", default="guest")
    password: str = get_env_var("RABBITMQ_PASS", default="guest")
    virtual_host: str = get_env_var("RABBITMQ_VHOST", default="/")
    exchange: str = get_env_var("RABBITMQ_EXCHANGE", default="payment-service-exc")
    dead_letter_exchange: str = get_env_var("RABBITMQ_DLQ_EXCHANGE", default="dlq-exc")
    message_ttl: int = get_env_var("RABBITMQ_MESSAGE_TTL", default=30000)
    retry_count: int = get_env_var("RABBITMQ_RETRY_COUNT", default=3)
    initial_retry_interval_ms: int = get_env_var(
        "RABBITMQ_INITIAL_RETRY_INTERVAL_MS", default=1000
    )
    max_retry_interval_ms: int = get_env_var(
        "RABBITMQ_MAX_RETRY_INTERVAL_MS", default=10000
    )
    retry_multiplier: float = get_env_var("RABBITMQ_RETRY_MULTIPLIER", default=2.0)
    concurrent_consumers: int = get_env_var("RABBITMQ_CONCURRENT_CONSUMERS", default=1)
    prefetch_count: int = get_env_var("RABBITMQ_PREFETCH_COUNT", default=10)
    publisher_confirm_timeout_ms: int = get_env_var(
        "RABBITMQ_PUBLISHER_CONFIRM_TIMEOUT_MS", default=1000
    )


class ExternalServiceSettings:
    learning_service_url: str = get_env_var(name="LEARNING_URL", default="")
    scheduling_service_url: str = get_env_var(name="SCHEDULING_URL", default="")


class Settings:
    app: AppSettings = AppSettings()
    cors: CORSSettings = CORSSettings()
    db: DatabaseSettings = DatabaseSettings()
    keycloak: KeycloakSettings = KeycloakSettings()
    log: LogSettings = LogSettings()
    telemetry: TelemetrySettings = TelemetrySettings()
    rabbitmq: RabbitMqSettings = RabbitMqSettings()
    external_services: ExternalServiceSettings = ExternalServiceSettings()


settings = Settings()


@lru_cache()
def get_settings() -> Settings:
    return Settings()


def get_external_service_settings() -> ExternalServiceSettings:
    return get_settings().external_services
