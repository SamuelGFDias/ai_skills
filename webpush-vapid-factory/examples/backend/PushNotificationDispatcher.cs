public record PushDispatchResult(int Sent, int Expired, int Failed);

/// <summary>
/// Ponto de extensão de alto nível para lógica de negócio: envia uma
/// PushMessage para todas as subscriptions de um usuário, cuidando de
/// remover do store as que estiverem expiradas.
/// </summary>
public interface IPushNotificationDispatcher
{
    Task<PushDispatchResult> NotifyUserAsync(string userId, PushMessage message);
}

public class PushNotificationDispatcher : IPushNotificationDispatcher
{
    private readonly IPushSubscriptionStore _store;
    private readonly IWebPushNotificationService _pushService;

    public PushNotificationDispatcher(IPushSubscriptionStore store, IWebPushNotificationService pushService)
    {
        _store = store;
        _pushService = pushService;
    }

    public async Task<PushDispatchResult> NotifyUserAsync(string userId, PushMessage message)
    {
        var subscriptions = _store.GetByUser(userId);

        var sent = 0;
        var expired = 0;
        var failed = 0;

        foreach (var subscription in subscriptions)
        {
            var result = await _pushService.SendAsync(subscription, message);
            switch (result.Status)
            {
                case PushSendStatus.Sent:
                    sent++;
                    break;
                case PushSendStatus.Expired:
                    _store.Remove(result.Endpoint);
                    expired++;
                    break;
                case PushSendStatus.Failed:
                    failed++;
                    break;
            }
        }

        return new PushDispatchResult(sent, expired, failed);
    }
}
