# Публичный сайт, legal и бизнес-позиционирование

## Public site

Текущий публичный сайт:

`https://api.greenvpn.pro/`

Это временно и допустимо для ЮKassa/review. В будущем лучше вынести публичный сайт на `https://greenvpn.pro`, а API оставить на `https://api.greenvpn.pro`.

Страницы:

- `https://api.greenvpn.pro/`
- `https://api.greenvpn.pro/download/windows`
- `https://api.greenvpn.pro/download/android`
- `https://api.greenvpn.pro/download/ios`
- `https://api.greenvpn.pro/legal/requisites`
- `https://api.greenvpn.pro/legal/offer`
- `https://api.greenvpn.pro/legal/privacy`
- `https://api.greenvpn.pro/legal/acceptable-use`
- `https://api.greenvpn.pro/legal/refunds`
- `https://api.greenvpn.pro/payment/return`

## Download buttons

Пользователь хочет, чтобы на сайте были кнопки:

- скачать для Windows;
- скачать для Android;
- скачать для iPhone/iPad.

Это уже заложено в public site. Windows link должен начать вести на финальный installer только после final build/release gate.

## Legal

Public legal pages уже есть и были нужны для ЮKassa:

- requisites;
- offer;
- privacy;
- acceptable use;
- refunds.

Персональные/публичные реквизиты владельца были применены server-side через env. Не дублировать лишние персональные данные в docs.

## Позиционирование

Продукт не продвигаем как обход блокировок.

Допустимые смыслы:

- защищенное подключение;
- стабильность соединения;
- защита в публичных Wi-Fi;
- простой Windows installer;
- поддержка и подписка;
- понятный личный кабинет/оплата.

Не использовать публично:

- обход блокировок;
- разблокировка конкретных запрещенных/чувствительных сервисов;
- анонимность без следов;
- гарантия вечной доступности;
- безлимит без ограничений.

## Pricing strategy

Основной файл:

`C:\Users\gekto\projects\bluevpn\docs\BUSINESS_PRICING_STRATEGY_RU.md`

Рабочая логика:

- не демпинговать;
- окупать серверы, почту, SMS, платежные комиссии, домены, будущие VPS;
- иметь запас на поддержку и рост;
- основной тариф сделать понятным и доступным;
- не обещать unlimited без fair-use.

Предыдущая рекомендация:

- Start около 149 RUB;
- Standard около 299 RUB как основной;
- Plus около 449 RUB;
- Maximum около 699 RUB с fair-use;
- стартовая акция `START20` только на первый месяц, ограниченная по сроку и числу использований.
