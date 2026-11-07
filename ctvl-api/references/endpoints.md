# CT-VL admin API: resumo de endpoints

Gerado por `scripts/gen-endpoints.py` a partir de `references/swagger.json` (Swagger 2.0, `basePath` `/api`, esquema https). Não edite à mão: regenere.

Autenticação: `Authorization: Bearer <JWT>`; o JWT vem de `POST /api-token-auth/` com `{username,password}`. O host no swagger original foi substituído por `<host>`.

Legenda: **obrig.** = campos `required` do corpo no swagger; **somente leitura** = `readOnly` (o servidor ignora ou rejeita na escrita). Listagens paginam com `limit`/`offset` e devolvem `{count,next,previous,results}`.

## api-token-auth

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| POST | `/api-token-auth/` | Returns a JSON Web Token that can be used for authenticated requests. |  | `Get JWT`: obrig. `username`, `password` |

## asymkeys

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/asymkeys/` | Returns a list of asymmetric keys | query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/asymkeys/` | Create an asymmetric key |  | `Asymmetric Key`: obrig. `name`; somente leitura `id` |
| GET | `/asymkeys/{id}` | Get an asymmetric key by id | path `id` (obrig.) |  |
| PUT | `/asymkeys/{id}` | Update an asymmetric key | path `id` (obrig.) | `Asymmetric Key`: obrig. `name`; somente leitura `id` |
| DELETE | `/asymkeys/{id}` | Delete an asymmetric key | path `id` (obrig.) |  |

## backup

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/backup/create` | Returns an encrypted backup file of the current CT-VL. | query `limit`<br>query `offset`<br>path `keyname` (obrig.) |  |
| GET | `/backup/create/{keyname}` | Returns an encrypted backup file of the current CT-VL. | path `keyname` (obrig.) |  |

## change_password

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| PUT | `/change_password/` | An endpoint for changing password. |  | `Change Password`: obrig. `old_password`, `new_password`, `new_password_confirm` |

## charsets

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/charsets/` | Returns a list of tokenization character sets | query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/charsets/` | Create a character set |  | `Tokenization Character Set`: obrig. `name`; somente leitura `idtokencharset` |
| GET | `/charsets/{idtokencharset}` | Get a character set by id | path `idtokencharset` (obrig.) |  |
| PUT | `/charsets/{idtokencharset}` | Update a character set | path `idtokencharset` (obrig.) | `Tokenization Character Set`: obrig. `name`; somente leitura `idtokencharset` |
| DELETE | `/charsets/{idtokencharset}` | Delete a character set | path `idtokencharset` (obrig.) |  |

## formats

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/formats/` | Returns a list of formats available for tokenization | query `limit`<br>query `offset` |  |

## groups

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/groups/` | Returns a list of groups | query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/groups/` | Create a group |  | `User Group`: obrig. `name`; somente leitura `id`, `mask`, `users` |
| GET | `/groups/{id}` | Get a group by id | path `id` (obrig.) |  |
| PUT | `/groups/{id}` | Update a group | path `id` (obrig.) | `User Group`: obrig. `name`; somente leitura `id`, `mask`, `users` |
| DELETE | `/groups/{id}` | Delete a group | path `id` (obrig.) |  |

## keys

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/keys/` | Returns a list of symmetric keys | query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/keys/` | Create a symmetric key |  | `Symmetric Key`: obrig. `name`; somente leitura `idkey` |
| GET | `/keys/{idkey}` | Get a symmetric key by id | path `idkey` (obrig.) |  |
| PUT | `/keys/{idkey}` | Update a symmetric key | path `idkey` (obrig.) | `Symmetric Key`: obrig. `name`; somente leitura `idkey` |
| DELETE | `/keys/{idkey}` | Delete a symmetric key | path `idkey` (obrig.) |  |

## logout

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| POST | `/logout/` | Revoke the current user's session |  | `Logout`: obrig. `session_key` |

## masks

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/masks/` | Returns a list of masking characters | query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/masks/` | Create a masking character |  | `Mask`: obrig. `name`, `showleft`, `showright`, `maskchar`; somente leitura `idmask` |
| GET | `/masks/{idmask}` | Get a masking character by id | path `idmask` (obrig.) |  |
| PUT | `/masks/{idmask}` | Update a masking character | path `idmask` (obrig.) | `Mask`: obrig. `name`, `showleft`, `showright`, `maskchar`; somente leitura `idmask` |
| DELETE | `/masks/{idmask}` | Delete a masking character | path `idmask` (obrig.) |  |

## opaqueobjs

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/opaqueobjs/` | Returns a list of opaque objects | query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/opaqueobjs/` | Create an opaque object |  | `Opaque Object`: obrig. `name`; somente leitura `id` |
| GET | `/opaqueobjs/{id}` | Get an opaque object by id | path `id` (obrig.) |  |
| PUT | `/opaqueobjs/{id}` | Update an opaque object | path `id` (obrig.) | `Opaque Object`: obrig. `name`; somente leitura `id` |
| DELETE | `/opaqueobjs/{id}` | Delete an opaque object | path `id` (obrig.) |  |

## permissions

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/permissions/crypto/groups/` | Returns a list of group crypto permissions | query `group__name`<br>query `key__name`<br>query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/permissions/crypto/groups/` | Create a group crypto permission |  | `Group Crypto Permission`: obrig. `group`; somente leitura `id` |
| GET | `/permissions/crypto/groups/{id}` | Get a group crypto permission by id | path `id` (obrig.) |  |
| PUT | `/permissions/crypto/groups/{id}` | Update a group crypto permission | path `id` (obrig.) | `Group Crypto Permission`: obrig. `group`; somente leitura `id` |
| PATCH | `/permissions/crypto/groups/{id}` | permissions_crypto_groups_partial_update | path `id` (obrig.) | `Group Crypto Permission`: obrig. `group`; somente leitura `id` |
| DELETE | `/permissions/crypto/groups/{id}` | Delete a group crypto permission | path `id` (obrig.) |  |
| GET | `/permissions/crypto/users/` | Returns a list of user crypto permissions | query `user__username`<br>query `key__name`<br>query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/permissions/crypto/users/` | Create a user crypto permission |  | `User Crypto Permission`: obrig. `user`; somente leitura `id` |
| GET | `/permissions/crypto/users/{id}` | Get a user crypto permission by id | path `id` (obrig.) |  |
| PUT | `/permissions/crypto/users/{id}` | Update a user crypto permission | path `id` (obrig.) | `User Crypto Permission`: obrig. `user`; somente leitura `id` |
| PATCH | `/permissions/crypto/users/{id}` | permissions_crypto_users_partial_update | path `id` (obrig.) | `User Crypto Permission`: obrig. `user`; somente leitura `id` |
| DELETE | `/permissions/crypto/users/{id}` | Delete a user crypto permission | path `id` (obrig.) |  |
| GET | `/permissions/km/groups/` | Returns a list of group key management permissions | query `group__name`<br>query `key__name`<br>query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/permissions/km/groups/` | Create a group key management permission |  | `Group Key Management Permission`: obrig. `group`; somente leitura `id` |
| GET | `/permissions/km/groups/{id}` | Get a group key management permission by id | path `id` (obrig.) |  |
| PUT | `/permissions/km/groups/{id}` | Update a group key management permission | path `id` (obrig.) | `Group Key Management Permission`: obrig. `group`; somente leitura `id` |
| PATCH | `/permissions/km/groups/{id}` | permissions_km_groups_partial_update | path `id` (obrig.) | `Group Key Management Permission`: obrig. `group`; somente leitura `id` |
| DELETE | `/permissions/km/groups/{id}` | Delete a group key management permission | path `id` (obrig.) |  |
| GET | `/permissions/km/users/` | Returns a list of user key management permissions | query `user__username`<br>query `key__name`<br>query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/permissions/km/users/` | Create a user key management permission |  | `User Key Management Permission`: obrig. `user`; somente leitura `id` |
| GET | `/permissions/km/users/{id}` | Get a user key management permission by id | path `id` (obrig.) |  |
| PUT | `/permissions/km/users/{id}` | Update a user key management permission | path `id` (obrig.) | `User Key Management Permission`: obrig. `user`; somente leitura `id` |
| PATCH | `/permissions/km/users/{id}` | permissions_km_users_partial_update | path `id` (obrig.) | `User Key Management Permission`: obrig. `user`; somente leitura `id` |
| DELETE | `/permissions/km/users/{id}` | Delete a user key management permission | path `id` (obrig.) |  |
| GET | `/permissions/token/groups/` | Returns a list of group tokenization permissions | query `group__name`<br>query `key__name`<br>query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/permissions/token/groups/` | Create a group tokenization permission |  | `Group Tokenization Permission`: obrig. `group` |
| GET | `/permissions/token/groups/{idgroupprofile}` | Get a group tokenization permission by id | path `idgroupprofile` (obrig.) |  |
| PUT | `/permissions/token/groups/{idgroupprofile}` | Update a group tokenization permission | path `idgroupprofile` (obrig.) | `Group Tokenization Permission`: obrig. `group` |
| PATCH | `/permissions/token/groups/{idgroupprofile}` | permissions_token_groups_partial_update | path `idgroupprofile` (obrig.) | `Group Tokenization Permission`: obrig. `group` |
| DELETE | `/permissions/token/groups/{idgroupprofile}` | Delete a group tokenization permission | path `idgroupprofile` (obrig.) |  |
| GET | `/permissions/token/users/` | Returns a list of user tokenization permissions | query `user__username`<br>query `key__name`<br>query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/permissions/token/users/` | Create a user tokenization permission |  | `User Tokenization Permission`: obrig. `user` |
| GET | `/permissions/token/users/{iduserprofile}` | Get a user tokenization permission by id | path `iduserprofile` (obrig.) |  |
| PUT | `/permissions/token/users/{iduserprofile}` | Update a user tokenization permission | path `iduserprofile` (obrig.) | `User Tokenization Permission`: obrig. `user` |
| PATCH | `/permissions/token/users/{iduserprofile}` | permissions_token_users_partial_update | path `iduserprofile` (obrig.) | `User Tokenization Permission`: obrig. `user` |
| DELETE | `/permissions/token/users/{iduserprofile}` | Delete a user tokenization permission | path `iduserprofile` (obrig.) |  |

## sessions

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/sessions/` | Returns a list of active sessions | query `limit`<br>query `offset` |  |
| DELETE | `/sessions/{id}` | Revoke an active session | path `id` (obrig.) |  |

## tokengroups

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/tokengroups/` | Returns a list of tokenization groups | query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/tokengroups/` | Create a tokenization group |  | `Tokenization Group`: obrig. `name`, `key`; somente leitura `idtenant` |
| GET | `/tokengroups/{idtenant}` | Get a tokenization group by id | path `idtenant` (obrig.) |  |
| PUT | `/tokengroups/{idtenant}` | Update a tokenization group | path `idtenant` (obrig.) | `Tokenization Group`: obrig. `name`, `key`; somente leitura `idtenant` |
| DELETE | `/tokengroups/{idtenant}` | Delete a tokenization group | path `idtenant` (obrig.) |  |

## tokentemplates

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/tokentemplates/` | Returns a list of tokenization templates | query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/tokentemplates/` | Create a tokenization template |  | `Tokenization Template`: obrig. `name`, `tenant`, `format`, `charset`; somente leitura `datetablenum_status`, `idtokentemplate` |
| GET | `/tokentemplates/{idtokentemplate}` | Get a tokenization template by id | path `idtokentemplate` (obrig.) |  |
| PUT | `/tokentemplates/{idtokentemplate}` | Update a tokenization template | path `idtokentemplate` (obrig.) | `Tokenization Template`: obrig. `name`, `tenant`, `format`, `charset`; somente leitura `datetablenum_status`, `idtokentemplate` |
| DELETE | `/tokentemplates/{idtokentemplate}` | Delete a tokenization template | path `idtokentemplate` (obrig.) |  |

## users

| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |
|---|---|---|---|---|
| GET | `/users/` | Returns a list of users | query `ordering`<br>query `search`<br>query `limit`<br>query `offset` |  |
| POST | `/users/` | Create a user |  | `User`: obrig. `username`, `email`; somente leitura `id`, `ldap_user`, `mask` |
| PUT | `/users/reset_password/{id}` | An endpoint for resetting a user's password. | path `id` (obrig.) | `Reset Password`: obrig. `admin_password`, `new_password`, `new_password_confirm` |
| GET | `/users/{id}` | Get a user by id | path `id` (obrig.) |  |
| PUT | `/users/{id}` | Update a user | path `id` (obrig.) | `User`: obrig. `username`, `email`; somente leitura `id`, `ldap_user`, `mask` |
| DELETE | `/users/{id}` | Delete a user | path `id` (obrig.) |  |

## Esquemas (campos)

### Asymmetric Key

- `id` (integer) [somente leitura]
- `name` (string) [obrig.; máx 64]: Asymmetric key name

### Change Password

- `old_password` (string) [obrig.]: Current password
- `new_password` (string) [obrig.]: New password
- `new_password_confirm` (string) [obrig.]: Confirm new password

### File

- `file` (string) [somente leitura]: Backup file

### Get JWT

- `username` (string) [obrig.]
- `password` (string) [obrig.]

### Group Crypto Permission

- `id` (integer) [somente leitura]
- `group` (string) [obrig.]
- `key` (string)
- `asymkey` (string)
- `opaqueobj` (string)
- `canDecrypt` (boolean)
- `canEncrypt` (boolean)
- `canSign` (boolean)
- `canVerify` (boolean)

### Group Key Management Permission

- `id` (integer) [somente leitura]
- `group` (string) [obrig.]
- `key` (string)
- `asymkey` (string)
- `opaqueobj` (string)
- `canCreate` (boolean)
- `canDestroy` (boolean)
- `canModify` (boolean)
- `canExport` (boolean)
- `canFind` (boolean)
- `canImport` (boolean)

### Group Tokenization Permission

- `id` (integer)
- `group` (string) [obrig.]
- `key` (string): Symmetric key this permission applies to
- `asymkey` (string): Asymmetric key this permission applies to
- `opaqueobj` (string): Opaque Object this permission applies to
- `canPost` (boolean)
- `canGet` (boolean)

### Logout

- `session_key` (string) [obrig.]: JWT used by the authenticated user

### Mask

- `idmask` (integer) [somente leitura]
- `name` (string) [obrig.; máx 50]: Mask name
- `showleft` (integer) [obrig.]: Number of unencrypted characters starting from the left
- `showright` (integer) [obrig.]: Number of unencrypted characters starting from the right.
- `maskchar` (string) [obrig.]: Masking character

### Opaque Object

- `id` (integer) [somente leitura]
- `name` (string) [obrig.; máx 64]: Opaque object name

### Reset Password

- `admin_password` (string) [obrig.]: Password of the currently authenticated user (must be a superuser)
- `new_password` (string) [obrig.]: New password
- `new_password_confirm` (string) [obrig.]: Confirm new password

### Session

- `id` (integer) [somente leitura]
- `user` (string) [somente leitura; pattern `^[\w.@+-]+$`]
- `user_agent` (string) [obrig.; máx 255]
- `ip_address` (string) [obrig.; máx 50]
- `created` (string) [obrig.]
- `expires` (string) [obrig.]

### Symmetric Key

- `idkey` (integer) [somente leitura]
- `name` (string) [obrig.; máx 64]: Symmetric key name
- `seedkey` (boolean): Key that is used to generate the random tables. Only one key can have seedkey set to True.

### Tokenization Character Set

- `idtokencharset` (integer) [somente leitura]
- `name` (string) [obrig.; máx 50]: Tokenization character set name
- `alphabet` (string): A sequence of characters or a range (in HEX digits) defining the character set
- `predefined` (boolean): True if it's a predefined character set. False if it's a custom character set
- `range` (boolean): Character set type. True if it's a range, False if it's a sequence of alphanumeric characters

### Tokenization Format

- `idtokenformat` (integer) [somente leitura]
- `name` (string) [obrig.; máx 50]: Tokenization format name

### Tokenization Group

- `idtenant` (integer) [somente leitura]
- `name` (string) [obrig.; máx 50]: Tokenization group name
- `key` (string) [obrig.]

### Tokenization Template

- `idtokentemplate` (integer) [somente leitura]
- `name` (string) [obrig.; máx 50]
- `tenant` (string) [obrig.]: Tokenization group
- `format` (string) [obrig.]: Tokenization format
- `keepleft` (integer): Number of character to leave unencrypted starting from the left
- `keepright` (integer): Number of character to leave unencrypted starting from the right
- `irreversible` (boolean): Set irreversible to true if you never want the token to be detokenized
- `copyruntdata` (boolean): Return uncencrypted data instead of an error if teh input is smaller than 2 characters
- `allowsmallinput` (boolean): Allow inputs smaller than 6 characters
- `charset` (string) [obrig.]: Character set allowed
- `prefix` (string): An optional prefix to be added to all tokens
- `startyear` (integer): The smallest year the input data is assumed to fall
- `endyear` (integer): The highest year the input data is assumed to fall
- `daterecordcount` (integer)
- `datetablenum` (integer)
- `datetablenum_status` (string) [somente leitura]

### User

- `id` (integer) [somente leitura]
- `username` (string) [obrig.; máx 150; pattern `^[\w.@+-]+$`]: Required. 150 characters or fewer. Letters, digits and @/./+/-/_ only.
- `email` (string) [obrig.]: User's email
- `password` (string)
- `is_active` (boolean): Designates whether this user should be treated as active. Unselect this instead of deleting accounts.
- `is_staff` (boolean): Designates whether the user can log into this admin site.
- `is_superuser` (boolean): Designates that this user has all permissions without explicitly assigning them.
- `groups` (array de string): Groups the user belongs to
- `ldap_user` (string) [somente leitura]: Boolean value determining if it's an AD user
- `mask` (string) [somente leitura]: Mask assigned to the user

### User Crypto Permission

- `id` (integer) [somente leitura]
- `user` (string) [obrig.; pattern `^[\w.@+-]+$`]
- `key` (string)
- `asymkey` (string)
- `opaqueobj` (string)
- `canDecrypt` (boolean)
- `canEncrypt` (boolean)
- `canSign` (boolean)
- `canVerify` (boolean)

### User Group

- `id` (integer) [somente leitura]
- `name` (string) [obrig.; máx 200]: Group name
- `users` (string) [somente leitura]
- `mask` (string) [somente leitura]

### User Key Management Permission

- `id` (integer) [somente leitura]
- `user` (string) [obrig.; pattern `^[\w.@+-]+$`]
- `key` (string)
- `asymkey` (string)
- `opaqueobj` (string)
- `canCreate` (boolean)
- `canDestroy` (boolean)
- `canModify` (boolean)
- `canExport` (boolean)
- `canFind` (boolean)
- `canImport` (boolean)

### User Tokenization Permission

- `id` (integer)
- `user` (string) [obrig.; pattern `^[\w.@+-]+$`]
- `key` (string)
- `asymkey` (string)
- `opaqueobj` (string)
- `canPost` (boolean)
- `canGet` (boolean)
