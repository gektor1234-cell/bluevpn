# Green VPN: VPS providers with API and Russia-friendly payment

Дата анализа: 2026-06-12.

Цель: найти варианты, где можно программно создавать/удалять VPS/VPN nodes через API или Terraform, при этом оплата возможна из России. Основной сайт `greenvpn.pro` не трогать; любые новые узлы сначала подключать только к test/preview.

## Короткий вывод

Для VPN-exit за пределами РФ в первую очередь смотреть:

1. **RUVDS** — есть API V2, есть зарубежные локации включая Frankfurt/London/Zurich, оплата из РФ через СБП/российские способы. Лучший кандидат для следующего тестового узла.
2. **HOSTKEY** — есть InvAPI/API docs, VPS в Netherlands/Europe, заявлены варианты оплаты банковскими картами/переводами/crypto; на отдельных страницах прямо указана оплата в рублях картами российских банков, включая МИР. Хороший кандидат, особенно под NL/Europe.
3. **Serverspace** — есть API для cloud servers и управление VM/network/storage, но оплата российскими картами по официальным материалам не подтверждена так жестко, как у RUVDS/Selectel/Yandex. Кандидат после ручной проверки платежа.

Для control-plane/мониторинга/админки в РФ, но не как основной внешний VPN-exit:

4. **Selectel** — хороший API/Terraform/OpenStack, официально поддерживает оплату для резидентов РФ картой, банковским переводом, QR, ЮMoney. Но как VPN-exit за пределы РФ подходит хуже, если нужна именно иностранная точка выхода.
5. **Yandex Cloud** — сильный Terraform/API, официальная оплата для резидентов РФ в RUB российскими картами. Скорее для backend/control-plane, не для обходного VPN-exit.
6. **VK Cloud / Cloud.ru** — есть Terraform/API-история, но для текущей задачи это запасные варианты под РФ-инфру, а не очевидный внешний VPN-exit.

## Провайдеры

### RUVDS

Почему подходит:

- API V2 позволяет управлять серверами через HTTP-запросы.
- Есть зарубежные локации, включая Frankfurt, London, Zurich.
- Есть способы оплаты, удобные для РФ, включая СБП.
- Есть пробный период/тестовый сервер, что удобно для проверки мобильных маршрутов до покупки на долгий срок.

Риски:

- Нужно отдельно проверить UDP/443, WireGuard, NAT и YouTube/Telegram/Discord с мобильного оператора.
- После Timeweb Frankfurt нельзя считать сам факт Frankfurt достаточным; нужен реальный mobile smoke.

Источники:

- API docs: https://ruvds.com/api-docs/
- API overview: https://ruvds.com/en-usd/use_api
- Locations/pricing page: https://ruvds.com/en-usd
- Payment help: https://ruvds.com/ru/helpcenter/payment/

### HOSTKEY

Почему подходит:

- Есть InvAPI/API docs и управление серверами через API.
- Есть Netherlands/Europe VPS.
- Есть страницы с оплатой банковскими картами, переводом, PayPal/crypto; для части VPS-страниц указана оплата в рублях картами российских банков, включая МИР.

Риски:

- Нужно проверить конкретно нужный тариф/VPS location: не все страницы одинаково описывают платежные методы.
- API выглядит мощным, но перед автоматизацией надо получить API key и проверить create/delete на тестовом минимальном VPS.

Источники:

- API docs: https://hostkey.com/documentation/apidocs/
- InvAPI overview: https://hostkey.com/documentation/apidocs/api_index/
- API key docs: https://hostkey.com/documentation/controlpanel/apikey/
- Server order docs: https://hostkey.com/documentation/server_order/site_server_order/
- Payment methods: https://hostkey.com/about-us/payment-terms-and-methods/
- Netherlands VPS: https://hostkey.com/vps/netherland-vps/

### Serverspace

Почему подходит:

- Cloud server API умеет создавать/настраивать VM, network, storage.
- Панель и API подходят для автономного create/delete.

Риски:

- Официально найдено только "bank card/PayPal/promo code"; российские карты/МИР не подтверждены.
- Перед использованием нужна ручная проверка пополнения баланса.

Источники:

- API: https://serverspace.us/services/api/
- Payment methods: https://serverspace.io/support/help/payment-methods-for-serverspace-cloud-services/

### Selectel

Почему подходит:

- Официальная Terraform/OpenStack-интеграция.
- Для резидентов РФ официально есть пополнение банковской картой, банковским переводом, QR, ЮMoney.
- Хороший кандидат для control-plane, monitoring, storage, admin.

Риск для VPN:

- Если нужен зарубежный VPN-exit, Selectel не первый выбор; это скорее российская инфраструктура.

Источники:

- Terraform providers: https://docs.selectel.ru/en/terraform/providers/
- Balance top-up: https://docs.selectel.ru/balance-and-payments/manage/top-up-balance/

### Yandex Cloud

Почему подходит:

- Официальный Terraform provider и Compute resources.
- Резиденты РФ платят в RUB российскими картами.
- Хорош для backend/control-plane/monitoring.

Риск для VPN:

- Не основной кандидат для внешнего VPN-exit.

Источники:

- Compute Terraform reference: https://yandex.cloud/en/docs/compute/tf-ref
- Terraform provider: https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs
- Payment methods: https://yandex.cloud/en/docs/billing/payment/payment-methods-card-business

### Cloud.ru

Почему подходит:

- Есть Terraform-путь для создания VM.
- Российский облачный провайдер, удобнее для РФ-инфры.

Риск для VPN:

- Не основной кандидат для внешнего VPN-exit.

Источники:

- VM via Terraform: https://cloud.ru/docs/tutorials-evolution/list/topics/vm__vm-terraform
- Terraform setup: https://cloud.ru/docs/terraform/ug/topics/guides__configuring-terraform-provider

## Рекомендация

Следующий тестовый VPN node лучше делать не в stable catalog, а как private/test node:

1. Сначала RUVDS Frankfurt или London на минимальном тарифе.
2. Если Frankfurt снова плохо работает с мобильной сетью РФ, пробовать London/Zurich.
3. Второй кандидат — HOSTKEY Netherlands.
4. Любой новый узел сначала подключать только к preview/test, прогонять WireGuard temp-peer E2E и реальный Android mobile smoke, затем решать вопрос о stable.

