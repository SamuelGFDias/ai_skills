import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { SwPush } from '@angular/service-worker';
import { HttpClient } from '@angular/common/http';
import { AuthService } from '../auth.service';

@Component({
  selector: 'app-push-subscriber',
  standalone: true,
  imports: [FormsModule],
  template: `
    <input
      type="text"
      [(ngModel)]="userId"
      placeholder="ex.: analyst-1"
    />
    <button (click)="assinarNotificacoes()">
      Ativar Notificações com Aba Fechada
    </button>
    <p>{{ status }}</p>
    <p>Refresh de token disparado: {{ authService.refreshCount }} vez(es)</p>
  `
})
export class PushSubscriberComponent {
  private swPush = inject(SwPush);
  private http = inject(HttpClient);
  protected authService = inject(AuthService);
  private readonly apiBaseUrl = 'http://localhost:5080';
  status = '';
  userId = '';

  constructor() {
    this.swPush.notificationClicks.subscribe(({ action, notification }) => {
      console.log('Notificação clicada:', action, notification);
    });

    this.swPush.messages.subscribe((message: any) => {
      console.log('Mensagem push silenciosa recebida:', message);
      if (message?.type === 'permissions-changed') {
        this.authService.refreshToken();
      }
    });
  }

  assinarNotificacoes(): void {
    if (!this.userId) {
      this.status = 'Informe o ID do usuário antes de ativar as notificações.';
      console.warn(this.status);
      return;
    }

    if (!this.swPush.isEnabled) {
      this.status = 'Service Workers não estão habilitados neste ambiente.';
      console.warn(this.status);
      return;
    }

    this.http.get<{ publicKey: string }>(`${this.apiBaseUrl}/api/push/vapid-public-key`)
      .subscribe({
        next: ({ publicKey }) => {
          this.swPush.requestSubscription({ serverPublicKey: publicKey })
            .then((sub: PushSubscription) => {
              this.http.post(`${this.apiBaseUrl}/api/push/register`, sub, {
                headers: { 'X-User-Id': this.userId }
              }).subscribe({
                next: () => { this.status = 'Inscrição registrada no backend com sucesso.'; console.log(this.status); },
                error: (err) => { this.status = 'Erro ao enviar subscription ao backend.'; console.error(err); }
              });
            })
            .catch((err) => { this.status = 'Erro ao solicitar permissão de push.'; console.error(err); });
        },
        error: (err) => { this.status = 'Erro ao buscar chave pública VAPID.'; console.error(err); }
      });
  }
}
