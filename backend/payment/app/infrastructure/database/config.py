from sqlalchemy.ext.asyncio import (
    create_async_engine,
    async_sessionmaker,
    AsyncSession,
    AsyncAttrs,
)
from sqlalchemy.ext.asyncio.engine import AsyncEngine
from sqlalchemy.orm import DeclarativeBase
from typing import AsyncIterator

from app.config.settings import Settings
from app.infrastructure.dependencies import get_settings


class Base(AsyncAttrs, DeclarativeBase):
    """Base class for SQLAlchemy models."""

    pass


settings: Settings = get_settings()

engine: AsyncEngine = create_async_engine(
    url=f"postgresql+asyncpg://{settings.db.user}:{settings.db.password}@{settings.db.host}:{settings.db.port}/{settings.db.name}",
    echo=settings.db.debug,
    pool_size=settings.db.pool_size,
    max_overflow=settings.db.max_overflow,
    connect_args={"timeout": settings.db.timeout},
)

SessionLocal: async_sessionmaker[AsyncSession] = async_sessionmaker(bind=engine, expire_on_commit=False)


async def get_db_session() -> AsyncIterator[AsyncSession]:
    """Provide a database session for a request."""
    async with SessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
