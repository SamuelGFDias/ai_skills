using System.Text.Json.Serialization;

public record PushSubscriptionDto(
    string Endpoint,
    PushSubscriptionKeysDto Keys
);

public record PushSubscriptionKeysDto(
    string P256dh,
    string Auth
);

public record AngularWebPushNotification(
    [property: JsonPropertyName("notification")] AngularNotificationDetails Notification
);

public record AngularNotificationDetails(
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("body")] string Body,
    [property: JsonPropertyName("icon")] string? Icon = "assets/icons/icon-192x192.png",
    [property: JsonPropertyName("vibrate")] int[]? Vibrate = null,
    [property: JsonPropertyName("data")] object? Data = null
);

/// <summary>
/// Tipo base para as mensagens push suportadas. Cada subtipo tem um formato
/// "on the wire" diferente — ver PushMessageSerializer.
/// </summary>
public abstract record PushMessage;

/// <summary>
/// Notificação visível: o ngsw-worker.js do Angular chama showNotification()
/// automaticamente a partir dela, mesmo com o app fechado.
/// </summary>
public record VisiblePushMessage(
    string Title,
    string Body,
    string? Icon = "assets/icons/icon-192x192.png",
    int[]? Vibrate = null,
    object? Data = null
) : PushMessage;

/// <summary>
/// Mensagem silenciosa: não gera notificação do SO. O ngsw-worker.js repassa
/// o payload via postMessage para os clients/abas abertos da mesma origem
/// (exposto no Angular via SwPush.messages). Só chega a algum lugar se o
/// navegador tiver pelo menos uma aba aberta daquela origem.
/// </summary>
public record SilentPushMessage(
    string Type,
    object? Data = null
) : PushMessage;
