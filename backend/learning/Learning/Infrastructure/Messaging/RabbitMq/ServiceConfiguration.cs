using Learning.Infrastructure.Messaging.RabbitMq.Consumers;
using Learning.Infrastructure.Messaging.RabbitMq.Publishers;

namespace Learning.Infrastructure.Messaging.RabbitMq;

public static class ServiceConfiguration
{
    public static IServiceCollection AddRabbitMq(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<RabbitMqOptions>()
            .BindConfiguration(nameof(RabbitMqOptions))
            .ValidateDataAnnotations()
            .ValidateOnStart();

        services.AddSingleton<RabbitMqConnectionProvider>();
        services.AddSingleton<IMessagePublisher, RabbitMqPublisher>();

        services.AddSingleton<IMessageConsumer, RabbitMqConsumer>();
        services.AddSingleton<IMessageConsumer, DeadLetterQueueConsumer>();

        services.AddHostedService<RabbitMqConsumerBackgroundService>();

        return services;
    }
}