using System.Net;
using System.Text.Json;
using WebPush;

public enum PushSendStatus
{
    Sent,
    Expired,
    Failed
}

public record PushSendResult(PushSendStatus Status, string Endpoint);

public interface IWebPushNotificationService
{
    Task<PushSendResult> SendAsync(PushSubscriptionDto subscription, PushMessage message, CancellationToken cancellationToken = default);
}

/// <summary>
/// Serializa cada tipo de PushMessage no formato "on the wire" esperado pelo
/// ngsw-worker.js do Angular.
/// </summary>
public static class PushMessageSerializer
{
    public static string Serialize(PushMessage message)
    {
        return message switch
        {
            VisiblePushMessage visible => JsonSerializer.Serialize(
                new AngularWebPushNotification(
                    new AngularNotificationDetails(
                        visible.Title,
                        visible.Body,
                        visible.Icon,
                        visible.Vibrate,
                        visible.Data
                    ))),
            SilentPushMessage silent => JsonSerializer.Serialize(new { type = silent.Type, data = silent.Data }),
            _ => throw new NotSupportedException($"Tipo de PushMessage não suportado: {message.GetType().Name}")
        };
    }
}

public class WebPushNotificationService : IWebPushNotificationService
{
    private readonly WebPushClient _client = new();
    private readonly VapidDetails _vapidDetails;
    private readonly ILogger<WebPushNotificationService> _logger;

    public WebPushNotificationService(IConfiguration configuration, ILogger<WebPushNotificationService> logger)
    {
        _logger = logger;

        var subject = configuration["Vapid:Subject"]
            ?? throw new InvalidOperationException("Configuração 'Vapid:Subject' não encontrada.");
        var publicKey = configuration["Vapid:PublicKey"]
            ?? throw new InvalidOperationException("Configuração 'Vapid:PublicKey' não encontrada.");
        var privateKey = configuration["Vapid:PrivateKey"]
            ?? throw new InvalidOperationException("Configuração 'Vapid:PrivateKey' não encontrada.");

        _vapidDetails = new VapidDetails(subject, publicKey, privateKey);
    }

    public async Task<PushSendResult> SendAsync(PushSubscriptionDto subscription, PushMessage message, CancellationToken cancellationToken = default)
    {
        var pushSubscription = new PushSubscription(
            subscription.Endpoint,
            subscription.Keys.P256dh,
            subscription.Keys.Auth);

        var payloadJson = PushMessageSerializer.Serialize(message);

        try
        {
            await _client.SendNotificationAsync(pushSubscription, payloadJson, _vapidDetails, cancellationToken: cancellationToken);
            return new PushSendResult(PushSendStatus.Sent, subscription.Endpoint);
        }
        catch (WebPushException ex) when (ex.StatusCode is HttpStatusCode.Gone or HttpStatusCode.NotFound)
        {
            _logger.LogWarning(ex, "Inscrição push expirada para o endpoint {Endpoint}.", subscription.Endpoint);
            return new PushSendResult(PushSendStatus.Expired, subscription.Endpoint);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Falha ao enviar notificação push para o endpoint {Endpoint}.", subscription.Endpoint);
            return new PushSendResult(PushSendStatus.Failed, subscription.Endpoint);
        }
    }
}
