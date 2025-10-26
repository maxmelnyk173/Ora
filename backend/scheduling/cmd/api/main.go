package main

import (
	"github.com/maksmelnyk/scheduling/docs"
	httpSwagger "github.com/swaggo/http-swagger"

	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chiMiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"

	"github.com/maksmelnyk/scheduling/config"
	"github.com/maksmelnyk/scheduling/internal/auth"
	"github.com/maksmelnyk/scheduling/internal/booking"
	"github.com/maksmelnyk/scheduling/internal/database"
	"github.com/maksmelnyk/scheduling/internal/messaging"
	"github.com/maksmelnyk/scheduling/internal/messaging/handlers"
	"github.com/maksmelnyk/scheduling/internal/middleware"
	"github.com/maksmelnyk/scheduling/internal/schedule"
	"github.com/maksmelnyk/scheduling/internal/telemetry"
)

// @title SCHEDULING
// @version 1.0
// @description API documentation for Scheduling Service
// @host localhost:8084
// @BasePath /api/v1
// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
func main() {
	// --- Config & Context ---
	cfg := config.LoadConfig()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	docs.SwaggerInfo.Host = "localhost:" + cfg.Server.Port

	// --- Telemetry Setup ---
	tel, err := telemetry.Init(ctx, cfg)
	if err != nil {
		log.Fatalf("failed to initialize telemetry: %v", err)
	}
	defer func() {
		if err := tel.Shutdown(ctx); err != nil {
			tel.Logger.Errorf("failed to shutdown telemetry: %v", err)
		}
	}()

	// --- Http Client Setup ---
	httpClient := &http.Client{
		Timeout: 10 * time.Second,
	}

	// --- Auth JWT Validator ---
	jwksProvider := auth.NewJWKManager(cfg.Keycloak.JwksURI, time.Hour)
	validator := auth.NewJWTValidator(jwksProvider, cfg.Keycloak.Issuer, cfg.Keycloak.Audience)

	// --- Database ---
	db, err := database.NewPgSqlDb(&cfg.Postgres)
	if err != nil {
		tel.Logger.Panicf("Postgresql init error: %s", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			tel.Logger.Panicf("Postgresql close error: %s", err)
		}
	}()

	// --- RabbitMQ Connection Setup ---
	connProvider := messaging.NewConnectionProvider(&cfg.RabbitMq, tel.Logger)
	if err := connProvider.Connect(ctx); err != nil {
		tel.Logger.Errorf("Failed to connect to RabbitMQ: %v", err)
		os.Exit(1)
	}
	defer func() {
		if err := connProvider.Close(); err != nil {
			tel.Logger.Errorf("Error during RabbitMQ connection shutdown: %v", err)
		}
	}()

	// --- RabbitMQ Publisher Setup ---
	publisher := messaging.NewPublisher(connProvider, &cfg.RabbitMq, tel.Logger)
	if err := publisher.Initialize(ctx); err != nil {
		tel.Logger.Errorf("Failed to initialize publisher: %v", err)
		os.Exit(1)
	}
	defer func() {
		if err := publisher.Close(); err != nil {
			tel.Logger.Errorf("Error during publisher shutdown: %v", err)
		}
	}()

	schedulerService := schedule.InitializeScheduleService(tel.Logger, db, &cfg.External, httpClient, publisher)
	bookingService := booking.InitializeBookingService(tel.Logger, db, &cfg.External, httpClient, publisher)

	messageHandler := handlers.NewMessageHandler(tel.Logger, bookingService)

	// --- RabbitMQ Consumer Setup ---
	consumerRoutingKeys := []string{messaging.PaymentToSchedulingPattern}
	consumer := messaging.NewConsumer(connProvider, &cfg.RabbitMq, tel.Logger, consumerRoutingKeys)
	if err := consumer.Initialize(ctx); err != nil {
		tel.Logger.Errorf("Failed to initialize consumer: %v", err)
		os.Exit(1)
	}
	defer func() {
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer shutdownCancel()
		if err := consumer.Shutdown(shutdownCtx); err != nil {
			tel.Logger.Errorf("Error during consumer shutdown: %v", err)
		}
	}()
	go func() {
		if err := consumer.StartConsuming(ctx, messageHandler.HandleIncomingMessage); err != nil && err != context.Canceled {
			tel.Logger.Errorf("Consumer stopped with error: %v", err)
		} else {
			tel.Logger.Info("Consumer stopped gracefully.")
		}
	}()

	// --- RabbitMQ DLQ Consumer Setup ---
	dlqConsumer := messaging.NewDeadLetterConsumer(connProvider, &cfg.RabbitMq, tel.Logger)

	if err := dlqConsumer.Initialize(ctx); err != nil {
		tel.Logger.Errorf("Failed to initialize DLQ consumer: %v", err)
		os.Exit(1)
	}
	defer func() {
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer shutdownCancel()
		if err := dlqConsumer.Shutdown(shutdownCtx); err != nil {
			tel.Logger.Errorf("Error during DLQ consumer shutdown: %v", err)
		}
	}()
	go func() {
		if err := dlqConsumer.StartConsuming(ctx); err != nil && err != context.Canceled {
			tel.Logger.Errorf("DLQ consumer stopped with error: %v", err)
		} else {
			tel.Logger.Info("DLQ consumer stopped gracefully.")
		}
	}()

	// --- HTTP Router Setup ---
	router := chi.NewRouter()

	corsMiddleware := cors.New(cors.Options{
		AllowedOrigins:   cfg.CORS.AllowOrigin,
		AllowedMethods:   cfg.CORS.AllowMethods,
		AllowedHeaders:   cfg.CORS.AllowHeaders,
		AllowCredentials: cfg.CORS.AllowCredentials,
	})

	router.Use(corsMiddleware.Handler)
	router.Use(chiMiddleware.CleanPath)
	router.Use(chiMiddleware.Recoverer)
	router.Use(otelhttp.NewMiddleware("HTTPServer",
		otelhttp.WithSpanNameFormatter(func(operation string, r *http.Request) string { return r.Method + " " + r.URL.Path }),
		otelhttp.WithMeterProvider(otel.GetMeterProvider()),
	))
	router.Use(middleware.LoggingMiddleware(tel.Logger))
	router.Use(middleware.AuthMiddleware(validator, tel.Logger, []string{"/swagger", "/health"}))

	// --- Mount Routes ---
	router.Get("/swagger/*", httpSwagger.WrapHandler)

	router.Get("/health/liveness", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	router.Get("/health/readiness", func(w http.ResponseWriter, r *http.Request) {
		if db.Ping() != nil {
			http.Error(w, "db not ready", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ready"))
	})

	router.Mount("/api/v1/schedules", schedule.InitializeScheduleHTTPHandler(schedulerService))
	router.Mount("/api/v1/bookings", booking.InitializeBookingHTTPHandler(bookingService))

	// --- HTTP Server ---
	srv := &http.Server{
		Addr:    ":" + cfg.Server.Port,
		Handler: router,
	}

	// --- Signal Handling ---
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-signals
		tel.Logger.Info("Shutdown signal received, shutting down gracefully...")
		cancel()
	}()

	// --- Start Server ---
	tel.Logger.Infof("Starting server on :%s", cfg.Server.Port)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		tel.Logger.Panicf("Server failed: %v", err)
	}

	// --- Graceful HTTP Shutdown ---
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		tel.Logger.Errorf("HTTP server shutdown error: %v", err)
	} else {
		tel.Logger.Info("HTTP server shutdown completed")
	}

	tel.Logger.Info("Graceful shutdown complete.")
}
