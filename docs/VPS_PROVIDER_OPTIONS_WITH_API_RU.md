# Green VPN: замена VPS-провайдера для VPN-нод

Дата обновления: 2026-06-12.

Цель: найти провайдера для новых VPN exit-node вместо Timeweb, с API/автоматизацией, оплатой из РФ и зарубежными локациями. Основной сайт и текущий стабильный контур не трогать; новые узлы сначала подключать только к test/preview.

## Короткое решение

Рекомендуемый следующий тестовый провайдер: **RUVDS**.

Причины:

- есть API для баланса, списка серверов, дата-центров, тарифов, создания сервера и удаления/команд управления;
- есть оплата российскими картами, МИР, ЮMoney, СберБанк Онлайн, СБП, счетом;
- есть зарубежные дата-центры: London, Zurich, Frankfurt, Amsterdam и другие;
- есть 3-дневный тест для новых пользователей, но создание тестовых серверов через API прямо в старой API-документации отмечено как недоступное, поэтому первый тест может потребовать ручного заказа;
- дешевле и проще для первого A/B-теста, чем HOSTKEY.

Практический порядок теста:

1. RUVDS London.
2. RUVDS Zurich.
3. RUVDS Amsterdam как альтернативный NL не на Timeweb.
4. HOSTKEY Netherlands/UK/France как запасной вариант.

**Не начинать снова с Frankfurt.** Timeweb Frankfurt уже показал нестабильное поведение именно в нашем VPN-сценарии. Frankfurt можно вернуться проверять позже, но не как первый replacement.

## Оценка кандидатов

### 1. RUVDS — основной кандидат

Что подтверждено официально:

- API V2 доступен на `https://ruvds.com/api-docs/`.
- Старый API-обзор описывает логин через API key + username/password, баланс, дата-центры, тарифы, список серверов, создание сервера `https://ruvds.com/api/server/create/`, команды управления и удаление через `server/command`.
- На странице дата-центров заявлены London, Zurich, Frankfurt, Amsterdam и другие площадки.
- В справке по оплате указаны Card Russian для российских Visa/Mastercard/МИР, ЮMoney, СберБанк Онлайн, СБП, UnionPay, счет.

Плюсы для Green VPN:

- можно автоматизировать lifecycle VPS через API;
- можно оплатить из РФ без обходных схем;
- есть несколько зарубежных локаций, значит можно быстро проверить маршруты;
- есть дешевые стартовые тарифы, поэтому A/B-тест не должен быть дорогим.

Риски:

- API создает платные серверы, тестовый период через API может быть недоступен;
- надо отдельно проверить UDP/443, TCP/443, WireGuard/OpenVPN, MTU и YouTube media с реального Android в РФ;
- RUVDS Frankfurt может вести себя иначе, чем Timeweb Frankfurt, но повторять Frankfurt первым нерационально.

Решение: брать **London** как первый test-node.

### 2. HOSTKEY — запасной кандидат

Что подтверждено официально:

- есть API/Invapi и документация по API-ключам;
- в оплате указаны банковский перевод, банковские карты Visa/MasterCard/МИР, ЮMoney, интернет-банк, наличные;
- на продуктовых страницах заявлены VPS в Netherlands, Germany, France, UK, cloud VPS с API/control panel, root access, 1Gbps/10Gbps, DDoS protection.

Плюсы:

- сильнее выглядит как серверная компания;
- хорошие зарубежные локации;
- API и панель зрелые;
- можно отменять серверы через Invapi/панель.

Минусы:

- обычно дороже RUVDS для маленькой VPN-ноды;
- часть VPS-страниц выглядит как SEO/маркетинг, конкретный тариф надо проверять в кабинете;
- для первого дешевого smoke-теста менее удобно.

Решение: держать как второй вариант, если RUVDS London/Zurich не пройдет mobile smoke.

### 3. Serverspace — технически нормальный, но платежный риск

Что подтверждено официально:

- есть Public API, REST/JSON, GET/DELETE/POST/PUT;
- API умеет деплоить серверы, менять конфигурации, управлять network/storage/DNS;
- есть Terraform/CLI;
- биллинг каждые 10 минут, cloud servers от примерно 4 EUR/month;
- оплата: bank cards, PayPal, promo code; минимальное пополнение 5 EUR.

Проблема:

- официальная страница не подтверждает российские карты/МИР/СБП;
- для нас это означает риск зависнуть на оплате.

Решение: не первый выбор. Использовать только если пользователь вручную подтвердит успешное пополнение баланса.

### 4. Aéza — не рекомендовать как основной

Плюсы:

- есть VPS, почасовая оплата, API/REST заявлены;
- много локаций, дешевые тарифы.

Критичный риск:

- 2025/2026 публично есть санкционный/репутационный риск вокруг Aeza Group по материалам OFAC.

Решение: не использовать как основу Green VPN, чтобы не тащить репутационный и платежный риск в продукт.

## Что именно тестировать на новой ноде

Минимальный smoke перед добавлением в preview:

1. SSH доступ, `uname`, distro, kernel.
2. Firewall: открыты TCP/443 и UDP/443, WireGuard порт, ICMP.
3. WireGuard:
   - handshakes;
   - traffic counters растут;
   - NAT работает;
   - DNS внутри туннеля работает.
4. Android real-device:
   - подключение через auto;
   - ручной выбор новой ноды;
   - переподключение с NL на новую ноду без ручного stop/start;
   - Telegram;
   - YouTube page;
   - YouTube media playback минимум 60 секунд.
5. Windows:
   - получение конфига;
   - connect/disconnect;
   - отсутствие конфликтов с чужим VPN.
6. Backend/admin:
   - node visible only in preview/test;
   - disabled by default для stable;
   - healthScore обновляется;
   - errors видны в admin.

## Рекомендуемая инфраструктурная схема

На ближайший этап:

- stable/main: только проверенные NL-ноды, без экспериментов;
- preview/test: новая RUVDS London node;
- если London проходит mobile smoke: оставить ее в preview 24 часа;
- если 24 часа без деградации: добавить как резервный stable candidate, но не включать stable без отдельного решения;
- если London плохой: удалить и тестировать Zurich;
- если RUVDS целиком плохой: переходить к HOSTKEY Netherlands/UK/France.

## Что нужно для автоматического создания через API

Для RUVDS:

- аккаунт RUVDS;
- пополненный баланс;
- API key из настроек аккаунта;
- login/email аккаунта;
- пароль аккаунта или отдельная авторизация, если будет доступна;
- выбранный datacenter id, os id, tariff id после запроса `datacenter`, `os`, `tariff`.

Секреты хранить только вне repo:

- переменные окружения локально;
- защищенный secret storage на сервере;
- не писать API key/password в docs, scripts, commits.

## Источники

- RUVDS API docs: https://ruvds.com/api-docs/
- RUVDS API overview: https://ruvds.com/en-usd/use_api
- RUVDS дата-центры: https://ruvds.com/ru/data/
- RUVDS оплата: https://ruvds.com/ru/helpcenter/payment/
- HOSTKEY API docs: https://hostkey.ru/documentation/apidocs/
- HOSTKEY API keys: https://hostkey.ru/documentation/controlpanel/apikey/
- HOSTKEY оплата: https://hostkey.ru/about-us/payment-terms-and-methods/
- HOSTKEY cloud VPS: https://hostkey.com/vps/cloud-vps/
- Serverspace API: https://serverspace.io/services/api/
- Serverspace payment methods: https://serverspace.io/support/help/payment-methods-for-serverspace-cloud-services/
- Serverspace pricing: https://serverspace.io/pricing/
- OFAC Aeza note: https://home.treasury.gov/news/press-releases/sb0185
