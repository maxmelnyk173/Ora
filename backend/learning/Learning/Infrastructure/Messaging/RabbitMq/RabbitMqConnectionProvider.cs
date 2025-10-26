using Microsoft.Extensions.Options;
using RabbitMQ.Client;
using RabbitMQ.Client.Exceptions;

namespace Learning.Infrastructure.Messaging.RabbitMq;

public class RabbitMqConnectionProvider : IAsyncDisposable
{
    private readonly ILogger<RabbitMqConnectionProvider> _logger;
    private readonly RabbitMqOptions _options;
    private readonly Lazy<Task<IConnection>> _connectionTask;

    public Task<IConnection> Connection => _connectionTask.Value;

    public RabbitMqConnectionProvider(IOptions<RabbitMqOptions> options, ILogger<RabbitMqConnectionProvider> logger)
    {
        _logger = logger;
        _options = options.Value;
        _connectionTask = new Lazy<Task<IConnection>>(CreateConnectionAsync);
    }

    private async Task<IConnection> CreateConnectionAsync()
    {
        var factory = new ConnectionFactory
        {
            HostName = _options.HostName,
            Port = _options.Port,
            UserName = _options.UserName,
            Password = _options.Password,
            VirtualHost = _options.VirtualHost,
            AutomaticRecoveryEnabled = true,
            TopologyRecoveryEnabled = true,
            ConsumerDispatchConcurrency = _options.ConcurrentConsumers,
            NetworkRecoveryInterval = TimeSpan.FromSeconds(10),
            RequestedHeartbeat = TimeSpan.FromSeconds(60),
            RequestedConnectionTimeout = TimeSpan.FromSeconds(15),
            ContinuationTimeout = TimeSpan.FromSeconds(15),
            ClientProvidedName = $"LearningService@{Environment.MachineName}"
        };

        return await CreateConnectionWithRetry(factory);
    }

    private async Task<IConnection> CreateConnectionWithRetry(ConnectionFactory factory)
    {
        var maxRetries = _options.RetryCount;
        var initialDelayMs = _options.InitialRetryIntervalMs;
        var multiplier = _options.RetryMultiplier;

        for (var attempt = 1; attempt <= maxRetries; attempt++)
        {
            try
            {
                var connection = await factory.CreateConnectionAsync();

                connection.ConnectionBlockedAsync += (sender, args) =>
                {
                    _logger.LogWarning("RabbitMQ connection blocked: {reason}", args.Reason);
                    return Task.CompletedTask;
                };

                connection.ConnectionUnblockedAsync += (sender, args) =>
                {
                    _logger.LogInformation("RabbitMQ connection unblocked");
                    return Task.CompletedTask;
                };

                connection.ConnectionShutdownAsync += (sender, args) =>
                {
                    _logger.LogWarning("RabbitMQ connection shutdown: {reason}, initiator: {initiator}",
                        args.ReplyText, args.Initiator);
                    return Task.CompletedTask;
                };

                return connection;
            }
            catch (AuthenticationFailureException ex)
            {
                _logger.LogCritical(ex, "Authentication failed for RabbitMQ. Check credentials.");
                throw;
            }
            catch (Exception ex)
            {
                if (attempt > _options.RetryCount)
                {
                    _logger.LogError(ex, "Failed to connect to RabbitMQ after {maxRetries} attempts", _options.RetryCount);
                    throw;
                }

                var delayMs = RetryDelayCalculator.Calculate(attempt, _options.InitialRetryIntervalMs, _options.RetryMultiplier, _options.MaxRetryIntervalMs);
                _logger.LogWarning(ex, "Failed to connect to RabbitMQ (attempt {attempt}/{maxRetries}). Retrying in {delayMs}ms",
                    attempt, _options.RetryCount, delayMs);

                await Task.Delay(delayMs);
            }
        }

        throw new InvalidOperationException("Failed to connect to RabbitMQ.");
    }

    public async ValueTask DisposeAsync()
    {
        if (_connectionTask.IsValueCreated && _connectionTask.Value.IsCompletedSuccessfully)
        {
            var connection = await _connectionTask.Value;
            try
            {
                if (connection.IsOpen)
                    await connection.CloseAsync();

                connection.Dispose();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error disposing RabbitMQ connection.");
            }

            GC.SuppressFinalize(this);
        }
    }
}