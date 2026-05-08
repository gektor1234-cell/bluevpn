# Green VPN: handoff для ChatGPT по домену, DNS, HTTPS и почте

Этот файл можно загрузить/вставить в ChatGPT, чтобы продолжить внешнюю настройку без лишних скриншотов в Codex.

## Контекст проекта

Проект: Green VPN.

Репозиторий:

```text
C:\Users\gekto\projects\bluevpn
```

Цель текущего этапа: подключить production-домен и почту, чтобы Green VPN мог отправлять письма подтверждения email с домена `greenvpn.pro`.

Важно:

- Видимый бренд: `Green VPN`.
- Backend/dev-prod server: `37.220.85.211`.
- API-домен: `api.greenvpn.pro`.
- Почтовый домен: `greenvpn.pro`.
- Секреты, пароли, токены, SMTP-пароли, admin-token и private keys нельзя писать в репозиторий и нельзя отправлять в чат без необходимости.

## Что уже сделано

### Домен

Куплен домен:

```text
greenvpn.pro
```

Регистратор:

```text
REG.RU
```

DNS-серверы:

```text
ns1.reg.ru
ns2.reg.ru
```

### API / HTTPS

В REG.RU добавлена запись:

```text
Type: A
Host: api
Value: 37.220.85.211
```

На сервере `37.220.85.211` уже настроен nginx для:

```text
https://api.greenvpn.pro
```

Let's Encrypt-сертификат выпущен успешно.

Backend systemd drop-in уже добавлен:

```text
/etc/systemd/system/bluevpn-backend.service.d/greenvpn-domain.conf
```

Backend env уже включает:

```text
GREENVPN_PUBLIC_BASE_URL=https://api.greenvpn.pro
GREENVPN_EMAIL_PUBLIC_BASE_URL=https://api.greenvpn.pro
GREENVPN_API_BASE_URLS=https://api.greenvpn.pro,http://37.220.85.211:8000
YOOKASSA_RETURN_URL=https://api.greenvpn.pro/payment/return
YOOKASSA_WEBHOOK_URL=https://api.greenvpn.pro/api/v1/billing/yookassa/webhook
```

Каталог backend уже отдаёт `https://api.greenvpn.pro` первым API base URL, старый IP оставлен как fallback.

### Яндекс 360

Куплен минимальный тариф Яндекс 360 для бизнеса.

Организация:

```text
Green VPN
```

Домен `greenvpn.pro` добавлен в Яндекс 360.

Права на домен подтверждены через TXT-запись.

## Текущие DNS-записи в REG.RU

В зоне `greenvpn.pro` сейчас примерно такой набор:

```text
A     @               -> 95.163.244.138
A     www             -> 95.163.244.138
A     api             -> 37.220.85.211
TXT   @               -> yandex-verification:5583d6225f64e34e
MX    @               -> mx.yandex.net. priority 10
TXT   @               -> v=spf1 redirect=_spf.yandex.net
TXT   mail._domainkey -> v=DKIM1; k=rsa; t=s; p=...
```

Записи `@` и `www` на `95.163.244.138` пока оставлены как парковка REG.RU. Их не трогать, пока не появится отдельный сайт/лендинг.

Запись `api -> 37.220.85.211` не трогать.

## Где остановились

На момент передачи:

- `MX` в Яндекс 360 принят.
- `SPF` в Яндекс 360 принят.
- `DKIM` TXT-запись добавлена в REG.RU, но Яндекс мог ещё не принять её из-за задержки DNS.

Нужно продолжить с проверки DKIM.

## Что делать дальше в Яндекс 360

### 1. Проверить DKIM

Открыть Яндекс 360 admin:

```text
admin.yandex.ru
```

Раздел:

```text
Почта -> Домены -> greenvpn.pro
```

или:

```text
Общие настройки -> Домены -> greenvpn.pro
```

Нажать:

```text
Проверить снова
```

Если DKIM не принят:

- подождать 5-15 минут;
- нажать проверку ещё раз;
- убедиться, что в REG.RU есть TXT host `mail._domainkey`;
- значение должно быть длинным и начинаться с `v=DKIM1;`.

Важно: DKIM нельзя перепечатывать руками. Его нужно копировать кнопкой копирования из Яндекс 360.

### 2. Добавить DMARC

После DKIM нужно добавить DMARC-запись в REG.RU.

В REG.RU:

```text
greenvpn.pro -> DNS-серверы и управление зоной -> Добавить запись -> TXT
```

Заполнить:

```text
Type: TXT
Subdomain / Host: _dmarc
Text / Value: v=DMARC1; p=none
TTL: default
```

Если позже нужен более строгий режим, можно будет усилить DMARC до `quarantine` или `reject`, но сейчас для старта нужен мягкий режим `p=none`, чтобы не ломать доставку.

### 3. Создать ящик no-reply

Нужно создать рабочий ящик:

```text
no-reply@greenvpn.pro
```

Возможный путь в Яндекс 360:

```text
Пользователи -> Добавить пользователя
```

или:

```text
Почта -> Общие ящики
```

Предпочтительно создать обычного пользователя/почтовый ящик, потому что для SMTP нужен логин и пароль приложения.

Данные:

```text
Логин: no-reply
Email: no-reply@greenvpn.pro
Имя: Green VPN
Фамилия/отображаемое имя: No Reply
```

Если Яндекс требует человека/сотрудника, можно назвать:

```text
Green VPN Mailer
```

### 4. Проверить вход в почту

Открыть:

```text
https://mail.yandex.ru
```

Зайти как:

```text
no-reply@greenvpn.pro
```

Проверить, что ящик открывается.

### 5. Подготовить SMTP-доступ

Для backend Green VPN нужны такие SMTP-настройки:

```text
GREENVPN_SMTP_HOST=smtp.yandex.ru
GREENVPN_SMTP_PORT=465
GREENVPN_SMTP_USERNAME=no-reply@greenvpn.pro
GREENVPN_SMTP_FROM=Green VPN <no-reply@greenvpn.pro>
GREENVPN_SMTP_PASSWORD=<пароль приложения>
```

Пароль приложения нельзя писать в репозиторий.

Если Яндекс требует пароль приложения:

- открыть настройки аккаунта `no-reply@greenvpn.pro`;
- включить двухфакторную защиту, если требуется;
- создать пароль приложения для почтового клиента/SMTP;
- сохранить его временно у себя, но не отправлять в публичные места.

Когда пароль будет готов, вернуться в Codex и запустить уже подготовленный безопасный скрипт:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1
```

Скрипт спросит пароль интерактивно и положит его только на сервер в `/etc/bluevpn/backend.env`, без записи секрета в git.

## Что потом должен сделать Codex

После того как ящик `no-reply@greenvpn.pro` и SMTP-пароль приложения готовы, Codex должен:

1. Запустить безопасный PowerShell/WSL-деплой SMTP env без записи секрета в репозиторий.
2. На сервере проверить systemd drop-in и `/etc/bluevpn/backend.env`:

```text
GREENVPN_SMTP_HOST=smtp.yandex.ru
GREENVPN_SMTP_PORT=465
GREENVPN_SMTP_USERNAME=no-reply@greenvpn.pro
GREENVPN_SMTP_FROM=Green VPN <no-reply@greenvpn.pro>
GREENVPN_SMTP_PASSWORD=<секрет только на сервере>
```

3. Перезапустить:

```text
systemctl restart bluevpn-backend.service
```

4. Проверить:

```text
https://api.greenvpn.pro/healthz
https://api.greenvpn.pro/api/v1/admin/email/readiness
```

5. Сделать тестовую регистрацию/повторную отправку письма.
6. Убедиться, что письмо подтверждения реально приходит.
7. После успешного теста можно включать production email readiness.

## Что нельзя делать

- Не делегировать весь домен на Яндекс, если нет отдельного решения. DNS сейчас остаётся в REG.RU.
- Не удалять `A api -> 37.220.85.211`.
- Не покупать лишние услуги REG.RU: хостинг, конструктор, SSL, переадресация, домен плюс.
- Не удалять TXT `yandex-verification`, пока Яндекс 360 использует домен.
- Не удалять MX/SPF/DKIM после принятия.
- Не вставлять реальные пароли в документацию проекта.
- Не писать SMTP-пароль в git.

## Минимальная инструкция для ChatGPT

Если продолжать в ChatGPT, можно написать ему:

```text
Мы настраиваем почту для Green VPN.

Домен greenvpn.pro куплен на REG.RU.
API уже работает на api.greenvpn.pro -> 37.220.85.211 через nginx + Let's Encrypt.
Яндекс 360 подключён, организация Green VPN создана.
Домен greenvpn.pro подтверждён.
MX принят.
SPF принят.
DKIM TXT уже добавлен в REG.RU, но его нужно дождаться/проверить в Яндексе.

Помогай мне пошагово:
1. дождаться/проверить DKIM;
2. добавить DMARC TXT _dmarc = v=DMARC1; p=none;
3. создать no-reply@greenvpn.pro;
4. подготовить SMTP settings для backend;
5. не проси меня отправлять пароли в чат;
6. не предлагай покупать лишние услуги.
```

## После возврата в Codex

Когда почта будет готова, вернуться в Codex и сказать:

```text
Почта Яндекс 360 готова: домен greenvpn.pro подтверждён, MX/SPF/DKIM/DMARC настроены, ящик no-reply@greenvpn.pro создан. Нужно подключить SMTP к backend безопасно, без записи пароля в репозиторий.
```

Тогда Codex должен продолжить с серверной настройки SMTP и теста реальных писем подтверждения email.

## Прогресс мастер-плана

Оценка текущего прогресса общего мастер-плана Green VPN:

```text
примерно 29%
```
