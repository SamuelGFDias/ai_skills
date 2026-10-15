public interface IPushSubscriptionStore
{
    void AddOrUpdate(string userId, PushSubscriptionDto subscription);
    IReadOnlyList<PushSubscriptionDto> GetByUser(string userId);
    IReadOnlyList<PushSubscriptionDto> GetAll();
    void Remove(string endpoint);
}

public class InMemoryPushSubscriptionStore : IPushSubscriptionStore
{
    private readonly Dictionary<string, List<PushSubscriptionDto>> _subscriptionsByUser = new();
    private readonly object _lock = new();

    public void AddOrUpdate(string userId, PushSubscriptionDto subscription)
    {
        lock (_lock)
        {
            if (!_subscriptionsByUser.TryGetValue(userId, out var subscriptions))
            {
                subscriptions = new List<PushSubscriptionDto>();
                _subscriptionsByUser[userId] = subscriptions;
            }

            subscriptions.RemoveAll(s => s.Endpoint == subscription.Endpoint);
            subscriptions.Add(subscription);
        }
    }

    public IReadOnlyList<PushSubscriptionDto> GetByUser(string userId)
    {
        lock (_lock)
        {
            return _subscriptionsByUser.TryGetValue(userId, out var subscriptions)
                ? subscriptions.ToList()
                : new List<PushSubscriptionDto>();
        }
    }

    public IReadOnlyList<PushSubscriptionDto> GetAll()
    {
        lock (_lock)
        {
            return _subscriptionsByUser.Values.SelectMany(s => s).ToList();
        }
    }

    public void Remove(string endpoint)
    {
        lock (_lock)
        {
            foreach (var subscriptions in _subscriptionsByUser.Values)
            {
                subscriptions.RemoveAll(s => s.Endpoint == endpoint);
            }
        }
    }
}
