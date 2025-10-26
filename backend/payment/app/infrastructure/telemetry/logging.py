import sys
import logging
from typing import Any, Dict, Callable
from loguru import logger
from opentelemetry.sdk.resources import Resource
from opentelemetry._logs import set_logger_provider
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter

from app.config.settings import LogSettings

LOG_LEVEL_MAP: Dict[int, str] = {
    logging.DEBUG: "DEBUG",
    logging.INFO: "INFO",
    logging.WARNING: "WARNING",
    logging.ERROR: "ERROR",
    logging.CRITICAL: "CRITICAL",
    5: "TRACE",
    25: "NOTICE",
}


class InterceptHandler(logging.Handler):
    """Intercepts standard logging and routes it to Loguru."""

    def emit(self, record: logging.LogRecord) -> None:
        level_name = LOG_LEVEL_MAP.get(record.levelno, record.levelname)
        logger.opt(exception=record.exc_info).log(level_name, record.getMessage())


def flatten_dict(
    d: Dict[str, Any], parent_key: str = "", sep: str = "."
) -> Dict[str, Any]:
    """Flattens nested dictionaries into a dot-separated key structure."""
    items: Dict[str, Any] = {}
    for k, v in d.items():
        new_key: str = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            val: Dict[str, Any] = v  # type: ignore
            items.update(flatten_dict(val, new_key, sep))
        else:
            items[new_key.lstrip("extra.")] = v
    return items


def create_otlp_sink(otel_handler: LoggingHandler) -> Callable[[Any], None]:
    """Creates an OTEL sink function."""

    def otlp_sink(message: Any) -> None:
        record: Any = message.record
        log_record = logging.LogRecord(
            name=record["name"],
            level=record["level"].no,
            pathname=record["file"].name if record["file"] else "",
            lineno=record["line"],
            msg=record["message"],
            args=(),
            exc_info=record["exception"],
            func=record["function"] or "<unknown>",
        )
        for key, value in flatten_dict(record["extra"]).items():
            setattr(log_record, key, value)

        otel_handler.emit(record=log_record)

    return otlp_sink


def create_otel_logging_provider(
    resource: Resource, otlp_endpoint: str
) -> LoggerProvider:
    """Creates and configures the OpenTelemetry Logger Provider."""
    log_provider = LoggerProvider(resource=resource)
    log_provider.add_log_record_processor(
        log_record_processor=BatchLogRecordProcessor(
            exporter=OTLPLogExporter(endpoint=otlp_endpoint)
        )
    )
    set_logger_provider(logger_provider=log_provider)
    return log_provider


def setup_logging(resource: Resource, stg: LogSettings, otel_endpoint: str) -> None:
    """Configures Loguru and OpenTelemetry logging together."""

    logger.remove()
    logger.add(
        sink=sys.stdout,
        colorize=True,
        level="INFO",
        enqueue=True,
        backtrace=True,
        catch=True,
        diagnose=True,
    )

    if resource:
        otel_logger_provider: LoggerProvider = create_otel_logging_provider(
            resource=resource, otlp_endpoint=otel_endpoint
        )
        otel_handler = LoggingHandler(
            level=logging.INFO, logger_provider=otel_logger_provider
        )
        logger.add(
            sink=create_otlp_sink(otel_handler=otel_handler),
            level=stg.level,
            enqueue=True,
            catch=True,
        )

    logging.basicConfig(handlers=[InterceptHandler()], level=logging.INFO)

    for name in logging.root.manager.loggerDict:
        existing_logger: logging.Logger = logging.getLogger(name=name)
        if not existing_logger.handlers:
            existing_logger.handlers = [InterceptHandler()]
            existing_logger.propagate = False
