## Connection String

```json
{
  "ConnectionStrings": {
    "Hangfire": "Server={DB_HOST};Initial Catalog={DB_NAME};User Id={DB_USER};Password={DB_PASSWORD};MultipleActiveResultSets=false;Encrypt={ENCRYPT};TrustServerCertificate={TRUST_CERT};Connection Timeout={TIMEOUT};"
  }
}
```

Usar um banco SQL Server **dedicado** (separado do banco da aplicacao).

