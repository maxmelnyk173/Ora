using OpenTelemetry;
using OpenTelemetry.Logs;

namespace Learning.Infrastructure.Telemetry;

public class LogProcessor : BaseProcessor<LogRecord>
{
    public override void OnEnd(LogRecord data)
    {
        if (LogHelper.IsSystemLogCategory(data.CategoryName) && data.LogLevel < LogLevel.Warning)
            return;

        data.Attributes = [.. data.Attributes.Select(e => new KeyValuePair<string, object>(LogHelper.ToSnakeCase(e.Key), e.Value))];

        base.OnEnd(data);
    }
}