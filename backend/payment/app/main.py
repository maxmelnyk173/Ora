from loguru import logger
from sqlalchemy import text
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from typing import AsyncIterator
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor  # type: ignore

from app.config.openapi import custom_openapi
from app.config.settings import RabbitMqSettings, Settings
from app.exceptions.exception_handlers import setup_exception_handlers
from app.infrastructure.messaging.manager import RabbitMqApplicationManager
from app.infrastructure.telemetry.config import configure_telemetry
from app.infrastructure.database.config import SessionLocal, engine
from app.infrastructure.dependencies import get_settings, get_token_validator
from app.middleware.auth import AuthMiddleware
from app.middleware.logging import RequestLoggingMiddleware
from app.features.payment.router import router as payment_router

settings: Settings = get_settings()
configure_telemetry(stg=settings)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Application lifespan context manager."""

    try:
        async with engine.connect() as conn:
            await conn.execute(statement=text(text="SELECT 1"))
        logger.info("Database connected successfully")
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        raise e

    rabbitmq_config: RabbitMqSettings = settings.rabbitmq

    try:
        rabbitmq_app_manager = RabbitMqApplicationManager(config=rabbitmq_config)

        # Create instances of services or dependencies that consumers need

        await rabbitmq_app_manager.startup()  # Add dependencies

        app.state.rabbitmq_app_manager = rabbitmq_app_manager

    except Exception as e:
        logger.error(f"RabbitMQ startup failed: {e}")
        raise e

    logger.info("Application startup complete")
    yield

    logger.info("Application shutdown initiated")

    rabbitmq_app_manager = app.state.rabbitmq_app_manager
    await rabbitmq_app_manager.shutdown()
    logger.info("RabbitMQ application manager shutdown complete")

    await engine.dispose()
    logger.info("Database engine disposed")

    rabbitmq_app_manager = None
    logger.info("Application shutdown complete")


app = FastAPI(
    lifespan=lifespan,
    title=settings.app.name,
    version=settings.app.version,
    debug=settings.app.debug,
)

app.openapi = lambda: custom_openapi(app=app)

FastAPIInstrumentor.instrument_app(app=app)  # type: ignore

app.add_middleware(
    middleware_class=CORSMiddleware,
    allow_credentials=settings.cors.allow_credentials,
    allow_origins=settings.cors.allow_origins,
    allow_methods=settings.cors.allow_methods,
    allow_headers=settings.cors.allow_headers,
)

app.add_middleware(middleware_class=RequestLoggingMiddleware)

app.add_middleware(
    middleware_class=AuthMiddleware,
    validator=get_token_validator(),
    public_apis=["/docs", "/openapi", "/health"],
)

setup_exception_handlers(app=app)


@app.get(path="/health/liveness")
async def liveness() -> dict[str, str]:
    return {"status": "alive"}


@app.get(path="/health/readiness")
async def readiness() -> dict[str, str]:
    try:
        async with SessionLocal() as session:
            await session.execute(statement=text(text="SELECT 1"))
        return {"status": "ready"}
    except Exception:
        return {"status": "not ready"}


app.include_router(router=payment_router, prefix="/api/v1/payments")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app=app, host=settings.app.host, port=int(settings.app.port))
