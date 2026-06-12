# Green VPN: main freeze and test contour

Дата фиксации: 2026-06-12.

## Главное правило

Основной публичный контур `https://greenvpn.pro` сейчас считается стабильным рабочим контуром. На нем уже есть реальные пользователи, поэтому без отдельной явной команды владельца нельзя:

- загружать новые stable APK/EXE;
- менять stable update manifests;
- менять тексты, ссылки и download aliases основного сайта;
- публиковать новые серверы в основной публичный catalog;
- включать рекламу, adgate, экспериментальные проверки или новые тарифные сценарии в stable.

## Где продолжается разработка

Все дальнейшие эксперименты идут только через тестовый/preview-контур:

- rewarded/adgate-реклама;
- новые Android/Windows сборки;
- новые VPS/VPN nodes;
- provider/API experiments;
- RuStore/Yandex Ads проверки;
- paid/subscription flow;
- server health/route quality experiments.

## Server policy

- FriendlyLynet / Friendly Linnet не трогать.
- Основной публичный catalog держать минимальным и рабочим.
- Новый сервер сначала заводить как непубличный тестовый узел.
- Публиковать узел в stable catalog только после ручного подтверждения владельца и отдельного smoke/e2e.

## Timeweb Germany status

Проблемный Timeweb Frankfurt/Germany узел выведен из эксплуатации. Сервер `8147243` и отдельный floating IP `72.56.31.142` удалены через Timeweb API. В живом public catalog остались только рабочие Netherlands nodes.

