import uuid

from http import HTTPStatus
from loguru import logger
from typing import Any, Dict
from fastapi import Request, Response
from starlette.types import ASGIApp
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from app.exceptions.app_exception import UnauthorizedException
from app.exceptions.error_codes import ErrorCode
from app.exceptions.exception_handlers import error_json_response
from app.infrastructure.jwks.validator import TokenValidator


class AuthMiddleware(BaseHTTPMiddleware):
    def __init__(
        self, app: ASGIApp, validator: TokenValidator, public_apis: list[str]
    ) -> None:
        super().__init__(app=app)
        self.validator: TokenValidator = validator
        self.public_apis: list[str] = public_apis

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        if request.method == "OPTIONS":
            return await call_next(request)

        for public_api in self.public_apis:
            if request.url.path.startswith(public_api):
                return await call_next(request)

        try:
            token: str | None = request.headers.get("Authorization")
            if not token or not token.startswith("Bearer "):
                return error_json_response(
                    message="Invalid token",
                    error_code=ErrorCode.INVALID_TOKEN,
                    status_code=HTTPStatus.UNAUTHORIZED,
                )

            token = token.split(sep="Bearer ")[1]
            payload: Dict[str, Any] = await self.validator.validate_token(token=token)

            user_id: Any | None = payload.get("sub")
            if user_id == None:
                return error_json_response(
                    message="Invalid token: user id not found",
                    error_code=ErrorCode.INVALID_TOKEN,
                    status_code=HTTPStatus.UNAUTHORIZED,
                )

            request.state.user_id = uuid.UUID(hex=user_id)
        except UnauthorizedException as ae:
            return error_json_response(
                message=ae.message,
                error_code=ae.code,
                status_code=HTTPStatus.UNAUTHORIZED,
            )
        except Exception as e:
            logger.exception("Unexpected error: {error}", error=str(object=e))
            raise e

        return await call_next(request)
