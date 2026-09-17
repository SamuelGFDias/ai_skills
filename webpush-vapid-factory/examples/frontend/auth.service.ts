import { Injectable } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class AuthService {
  refreshCount = 0;

  refreshToken(): void {
    this.refreshCount++;
    console.log(`[AuthService] Token renovado após evento de permissão alterada (contagem: ${this.refreshCount}).`);
  }
}
