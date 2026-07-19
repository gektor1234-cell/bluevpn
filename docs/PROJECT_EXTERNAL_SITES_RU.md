# Green VPN: реестр сайтов и внешних веб-сервисов

Дата фиксации: 2026-07-19.

Это максимально полный реестр сайтов, доменов и веб-endpoint, которые участвовали в разработке, эксплуатации, тестировании, оплате, рекламе, публикации или исследовании Green VPN. В список включены и одноразовые источники. Личные сайты из открытых вкладок, не связанные с проектом, исключены.

Источники реестра:

- URL из кода, документации и operational-скриптов репозитория;
- `docs/CURRENT_HANDOFF.md`, `docs/RELEASE_STATE.md` и профильные runbook;
- журнал действий текущей задачи Codex до запроса на этот реестр;
- подтвержденные кабинеты и страницы, которые открывались во время проекта.

Ограничения:

- встроенный браузер не предоставил API полной истории, поэтому файлы профилей Chrome/Яндекс.Браузера намеренно не читались;
- tracking, CDN и служебные asset-домены объединены с основным сервисом, если не имели отдельной проектной роли;
- query-параметры, токены, идентификаторы платежей, логины и другие чувствительные данные удалены;
- `example.*`, `*.test`, `localhost`, `127.0.0.1`, `0.0.0.0` и учебные заглушки не считаются внешними сайтами.

Статусы:

- **рабочий** - используется текущим продуктом или эксплуатацией;
- **исторический** - использовался раньше, но сейчас не является основным;
- **тестовый** - использовался для preview, smoke или диагностики;
- **исследование** - изучался, сравнивался или использовался как источник;
- **кандидат** - рассматривался, но не интегрирован.

## 1. Собственные домены и публичные endpoint Green VPN

| Сайт или домен | Роль | Статус |
|---|---|---|
| [greenvpn.pro](https://greenvpn.pro/) | Основной сайт, legal-страницы, публичные загрузки Android и Windows, paid-beta страницы | рабочий |
| [api.greenvpn.pro](https://api.greenvpn.pro/) | Production API, healthz, auth, catalog, billing, update manifests, рекламный web-gate | рабочий |
| [admin.greenvpn.pro](https://admin.greenvpn.pro/) | Защищенная операторская админка | рабочий |
| `updates.greenvpn.pro` | Ранний отдельный адрес Windows-обновлений | исторический |
| `api2.greenvpn.pro` | Экспериментальный/резервный API hostname, встречался в проверках | исторический |
| `nl1.vpn.greenvpn.pro` | Стабильный транспортный endpoint NL1 | рабочий, не обычный сайт |
| `nl2.vpn.greenvpn.pro` | NL2 и multiprotocol canary endpoint | рабочий/test, не обычный сайт |
| [176-113-81-35.sslip.io](https://176-113-81-35.sslip.io/) | Публичный fallback RUVDS Moscow для main, paid-beta, manifests и downloads | рабочий fallback |
| [88-218-250-86.sslip.io](https://88-218-250-86.sslip.io/) | Исторический London API/VPN fallback и health/bootstrap smoke | исторический |
| `http://37.220.85.211:8000` | Исторический прямой origin/backend NL1 | исторический, непубличный интерфейс |
| `72.56.32.197` | Timeweb public/control-plane IP, использовался в прямых проверках | рабочий инфраструктурный endpoint |
| `88.218.250.86` | London VPS endpoint, использовался в восстановлении и smoke | исторический/инфраструктурный |

Ключевые публичные пути, которые проверялись отдельно:

- `https://greenvpn.pro/paid-beta/`;
- `https://greenvpn.pro/downloads/GreenVPN_Android.apk`;
- `https://greenvpn.pro/downloads/GreenVPN_Setup.exe`;
- `https://api.greenvpn.pro/healthz`;
- `https://api.greenvpn.pro/paid-beta-api/healthz`;
- `https://api.greenvpn.pro/payment/return`;
- `https://api.greenvpn.pro/api/v1/billing/yookassa/webhook`;
- `https://api.greenvpn.pro/yookassa-review-20260711/` и две evidence PNG;
- `https://greenvpn.pro/paid-beta/yookassa-review-20260711/`;
- `https://176-113-81-35.sslip.io/paid-beta/yookassa-review-20260711/`.

## 2. Хостинг, VPS, домены, DNS и сертификаты

| Сайт или домен | Роль | Статус |
|---|---|---|
| [timeweb.cloud](https://timeweb.cloud/) | Основной Timeweb Cloud кабинет, серверы и баланс | рабочий |
| [api.timeweb.cloud](https://api.timeweb.cloud/) | API серверов, финансов, пресетов и SSH keys | рабочий |
| `*.s3.timeweb.cloud` | Временные object-storage загрузки и артефакты | рабочий/временный |
| `s3.twcstorage.ru` | Timeweb object storage endpoint | исторический/служебный |
| `swift.timeweb.cloud` | Timeweb storage endpoint | исторический/служебный |
| `mirror.timeweb.ru` | Пакетное зеркало Timeweb | служебный |
| `zabbix.repo.timeweb.ru` | Репозиторий monitoring-пакетов Timeweb | служебный |
| [ruvds.com](https://ruvds.com/) | RUVDS кабинет, API docs, серверы, баланс и support | рабочий |
| [api.ruvds.com](https://api.ruvds.com/) | RUVDS API v2 | рабочий |
| `dns.ruvds.com` | DNS-сервис RUVDS | служебный |
| `lg.ruvds.com` | Looking Glass RUVDS | диагностика |
| `ruvds.printdirect.ru` | Служебный домен документов/писем RUVDS | исторический/служебный |
| [reg.ru](https://www.reg.ru/) | Регистратор `greenvpn.pro`, DNS-зона и аккаунт | рабочий |
| [help.reg.ru](https://help.reg.ru/) | Справка по DNS-записям | рабочая документация |
| [cloud.reg.ru](https://cloud.reg.ru/) / [reg.cloud](https://reg.cloud/) | Облачные продукты и панели REG.RU, рассматривались при инфраструктурных действиях | исследование |
| [serverspace.io](https://serverspace.io/) | Альтернативный VPS-провайдер, тарифы и API | кандидат, API проверялся |
| [my.serverspace.io](https://my.serverspace.io/) | Кабинет Serverspace | кандидат |
| [api.serverspace.io](https://api.serverspace.io/) | Serverspace API | кандидат, проверялся |
| [hostkey.ru](https://hostkey.ru/) / [hostkey.com](https://hostkey.com/) | Альтернативный VPS-провайдер, API, оплата и зарубежные VPS | кандидат |
| [sslip.io](https://sslip.io/) | Wildcard DNS для IP-based fallback hostnames | рабочая инфраструктурная зависимость |
| [letsencrypt.org](https://letsencrypt.org/) | TLS-сертификаты | рабочий |
| `acme-v02.api.letsencrypt.org` | ACME production API | рабочий |
| [certbot.eff.org](https://certbot.eff.org/) | Certbot и инструкции по сертификатам | рабочая документация |
| [cloudflare-dns.com](https://cloudflare-dns.com/) | DNS-over-HTTPS проверки DNS-зоны | диагностика |
| [dns.google](https://dns.google/) | Google DNS-over-HTTPS проверки | диагностика |
| [repo.powerdns.com](https://repo.powerdns.com/) | Пакеты и ключ PowerDNS/dnsdist | test infrastructure |
| [dnsdist.org](https://dnsdist.org/) | Документация dnsdist | исследование/test |
| [deb.debian.org](https://deb.debian.org/) / [security.debian.org](https://security.debian.org/) | Debian packages и security updates | рабочая зависимость |
| [archive.ubuntu.com](https://archive.ubuntu.com/) / [security.ubuntu.com](https://security.ubuntu.com/) | Ubuntu packages и security updates | рабочая зависимость |

## 3. Почта, авторизация, SMS и служебные уведомления

| Сайт или домен | Роль | Статус |
|---|---|---|
| [e.mail.ru](https://e.mail.ru/) | Контактная почта проекта, переписка с ЮKassa, RUVDS и рекламными сетями | рабочий |
| [mail.ru](https://mail.ru/) | Mail.ru account и webmail ecosystem | рабочий |
| [cloud.mail.ru](https://cloud.mail.ru/) | Передача/хранение отдельных вложений | служебный |
| [360.yandex.ru](https://360.yandex.ru/business/) | Yandex 360 для доменной почты Green VPN | рабочий |
| [admin.yandex.ru](https://admin.yandex.ru/) | Администрирование Yandex 360 организации | рабочий |
| [mail.yandex.ru](https://mail.yandex.ru/) | Почта `@greenvpn.pro` и SMTP-проверки | рабочий |
| [passport.yandex.ru](https://passport.yandex.ru/) / [id.yandex.ru](https://id.yandex.ru/) | Yandex ID для 360 и РСЯ | рабочий |
| [sms.ru](https://sms.ru/) | SMS-коды, баланс, API и test send | рабочий внешний провайдер |
| [t.me/BotFather](https://t.me/BotFather) | Создание/настройка Telegram bot | рабочий setup |
| [api.telegram.org](https://api.telegram.org/) | Telegram alerts/support bot API | подготовлено/служебный |
| [forms.gle](https://forms.gle/) / [docs.google.com](https://docs.google.com/) / [drive.google.com](https://drive.google.com/) | Одноразовые формы и материалы провайдеров | разовое использование |
| [forms.yandex.ru](https://forms.yandex.ru/) | Формы поддержки/партнеров Яндекса | разовое использование |

## 4. Платежи, чеки и налоговый контур

| Сайт или домен | Роль | Статус |
|---|---|---|
| [yookassa.ru](https://yookassa.ru/) | Кабинет магазина, платежи, чат поддержки, договор и docs | рабочий |
| [api.yookassa.ru](https://api.yookassa.ru/v3) | Создание и проверка платежей, рекурренты | рабочий |
| [yoomoney.ru](https://yoomoney.ru/) | Платежный ecosystem ЮMoney/ЮKassa и письма | рабочий провайдерский домен |
| `promo.yookassa.ru` | Промо/служебные страницы ЮKassa | служебный |
| `ccomni-ds.yoomoney.ru` | Служебный checkout/телеметрический домен ЮMoney | служебный |
| `static.yoomoney.ru` | Статические ресурсы платежного интерфейса | служебный |
| [npd.nalog.ru](https://npd.nalog.ru/) | Налоговый контур самозанятого и чеки | рабочая внешняя зависимость |

## 5. Рекламные платформы и монетизация

### Подключенный или приоритетный контур

| Сайт или домен | Роль | Статус |
|---|---|---|
| [partner.yandex.ru](https://partner.yandex.ru/) | Кабинет РСЯ, приложение Green VPN, рекламные блоки и модерация | рабочий/приоритетный |
| [ads.yandex.com](https://ads.yandex.com/) | Yandex Mobile Ads и rewarded documentation | рабочий Android provider |
| [adfox.yandex.ru](https://adfox.yandex.ru/) | Yandex advertising/Adfox служебный контур | служебный |
| [yandex.ru](https://yandex.ru/) | Rewarded script, support и партнерская документация | рабочий ecosystem |
| [docs.yandex.ru](https://docs.yandex.ru/) | Материалы и документы Яндекса | служебный |
| `company.yandex.ru`, `pro-partners.yandex.ru`, `partner-bloggers.yandex.ru` | Партнерские правила, выплаты и справочные страницы | исследование/поддержка |

### Платформы, которым отправлялись запросы

| Сайт или домен | Роль | Статус |
|---|---|---|
| [mediatoday.ru](https://mediatoday.ru/) / [old.mediatoday.ru](https://old.mediatoday.ru/) | Rewarded Video, RUB-выплаты и Windows S2S вопрос | кандидат, запрос отправлен |
| [monetag.com](https://monetag.com/) | Rewarded interstitial и варианты выплат | кандидат, запрос отправлен |
| [docs.monetag.com](https://docs.monetag.com/) / [help.monetag.com](https://help.monetag.com/) | SDK, callback и payout documentation | исследование |
| [ayetstudios.com](https://www.ayetstudios.com/) | HTML5 rewarded video | кандидат, запрос отправлен |
| [docs.ayetstudios.com](https://docs.ayetstudios.com/) / [support.ayet.io](https://support.ayet.io/) | Web SDK, S2S и support ticket | исследование/support |
| [applixir.com](https://www.applixir.com/) | Web rewarded video и payout условия | кандидат, запрос отправлен |
| [support.applixir.com](https://support.applixir.com/) / `client.applixir.com` / `cdn.applixir.com` | Docs, publisher portal и SDK assets | исследование |
| [adsterra.com](https://adsterra.com/) | VAST/rewarded, выплаты и допустимость incentivized VPN flow | кандидат, запрос отправлен |
| [help-publishers.adsterra.com](https://help-publishers.adsterra.com/) | Publisher rules и выплаты | исследование |

### Дополнительные рекламные варианты, которые сравнивались

| Сайт или домен | Роль | Статус |
|---|---|---|
| [support.google.com/admanager](https://support.google.com/admanager/) / [developers.google.com/publisher-tag](https://developers.google.com/publisher-tag/) | Google Ad Manager rewarded web | исследование, не подходит как российский payout fallback |
| [propellerads.com](https://propellerads.com/) / [help.propellerads.com](https://help.propellerads.com/) | Web monetization и payout comparison | исследование |
| [ads.vk.com](https://ads.vk.com/) / [target.my.com](https://target.my.com/) / [target.vk.ru](https://target.vk.ru/) | VK Ads/myTarget как российская альтернатива | исследование |
| [adflux.network](https://adflux.network/) | Rewarded Video candidate из market scan | исследование |
| [offerwall.adparagon.io](https://offerwall.adparagon.io/) | Offerwall/rewarded infrastructure, встречалась при анализе ayeT | исследование |
| [aads.com](https://aads.com/) | Crypto ad network candidate | исследование |
| [videonow.ru](https://videonow.ru/) | Video advertising candidate | исследование |
| [rewardedmedia.com](https://rewardedmedia.com/) | Rewarded advertising candidate | исследование |
| [rewardio.com](https://www.rewardio.com/) | Rewarded advertising candidate | исследование |
| [venatus.com](https://www.venatus.com/) | Gaming/web monetization candidate | исследование |
| [adgora.net](https://www.adgora.net/) | Ad network candidate из market scan | исследование |
| [adrevanetwork.com](https://adrevanetwork.com/) | Ad network candidate из market scan | исследование |
| [admitad.ru](https://www.admitad.ru/) | Affiliate/ad platform candidate | исследование |

Последняя группа встретилась в поиске и сравнении. Для нее нет подтвержденной интеграции, кабинета или отправленной заявки, если это прямо не указано.

## 6. Магазины приложений, сборка, исходники и доверие установщика

| Сайт или домен | Роль | Статус |
|---|---|---|
| [rustore.ru](https://www.rustore.ru/) | Российская дистрибуция Android | проверялся/кандидат публикации |
| [console.rustore.ru](https://console.rustore.ru/) | Кабинет разработчика RuStore | проверялся |
| [play.google.com](https://play.google.com/) | Google Play и установка приложений на тестовые устройства | проверялся |
| [developer.android.com](https://developer.android.com/) | Android API, package visibility и versioning | рабочая документация |
| [github.com](https://github.com/) | Исходники, releases и third-party engines | рабочая зависимость |
| [api.github.com](https://api.github.com/) | Release metadata и проверки версий | рабочая зависимость |
| [raw.githubusercontent.com](https://raw.githubusercontent.com/) | License/source notices и raw-файлы | рабочая зависимость |
| [flutter.dev](https://flutter.dev/) / [docs.flutter.dev](https://docs.flutter.dev/) | Flutter build и platform integration docs | рабочая зависимость |
| [dart.dev](https://dart.dev/) / [pub.dev](https://pub.dev/) | Dart analyzer, lints и packages | рабочая зависимость |
| [repo1.maven.org](https://repo1.maven.org/) | Android Maven dependencies | рабочая зависимость |
| [services.gradle.org](https://services.gradle.org/) / [docs.gradle.org](https://docs.gradle.org/) | Gradle distributions и docs | рабочая зависимость |
| `schemas.android.com` | Android XML namespace, встречается в manifests/resources | машинная build-зависимость |
| [go.dev](https://go.dev/) | Go toolchain для transport engines | рабочая build-зависимость |
| [pypi.org](https://pypi.org/) | Python packages для backend/tests | рабочая build-зависимость |
| [developer.apple.com](https://developer.apple.com/) | Flutter/iOS/macOS reference metadata, не текущий продукт | справочная зависимость |
| [developer.mozilla.org](https://developer.mozilla.org/) | HTML/Web API reference для публичных страниц и web-gate | справочная зависимость |
| [learn.microsoft.com](https://learn.microsoft.com/) / [docs.microsoft.com](https://docs.microsoft.com/) | Windows, services, WebView2, installer и API docs | рабочая документация |
| `schemas.microsoft.com` / [wiki.gnome.org](https://wiki.gnome.org/) / `www.apple.com/DTDs` | Windows/Linux/macOS manifest и application metadata references | машинная build-зависимость |
| [apache.org](https://www.apache.org/) / [gnu.org](https://www.gnu.org/) / [fsf.org](https://fsf.org/) | Third-party license texts и license guidance | юридическая build-зависимость |
| [microsoft.com/security/portal/submit.aspx](https://www.microsoft.com/security/portal/submit.aspx) | Отправка Windows installer на false-positive review | проверялся |
| [drweb.ru](https://www.drweb.ru/) | Антивирусная проверка/false-positive контур | проверялся |
| [browser.yandex.ru/help/security/file-checking](https://browser.yandex.ru/help/security/file-checking) | Проверка скачиваемого installer Яндекс.Браузером | исследование/диагностика |
| [timestamp.digicert.com](http://timestamp.digicert.com/) | Timestamp endpoint для будущей Authenticode подписи | подготовлено |
| [openai.com](https://openai.com/) / [help.openai.com](https://help.openai.com/) / [developers.openai.com](https://developers.openai.com/) | Codex/ChatGPT как рабочий инструмент проекта | рабочий инструментарий |

Основные GitHub-проекты, которые реально участвовали: `amnezia-vpn/amneziawg-android`, `amnezia-vpn/amneziawg-go`, `amnezia-vpn/amneziawg-tools`, `amnezia-vpn/amneziawg-windows-client`, `apernet/hysteria`, `XTLS/Xray-core`, `SagerNet/sing-box`, `heiher/hev-socks5-tunnel`, `klzgrad/naiveproxy`, `klzgrad/forwardproxy`, `caddyserver/caddy`, `caddyserver/xcaddy`, `anytls/anytls-go`, `basil00/WinDivert`, `InterceptSuite/ProxyBridge`, `flutter/flutter`, `gradle/gradle`.

## 7. Протоколы, обходы, DNS и технические источники

| Сайт или домен | Роль | Статус |
|---|---|---|
| [wireguard.com](https://www.wireguard.com/) / [git.zx2c4.com](https://git.zx2c4.com/) | WireGuard docs и Android source | рабочий/исследование |
| [docs.amnezia.org](https://docs.amnezia.org/) / [amnezia.org](https://amnezia.org/) | AmneziaWG/AWG2 documentation | рабочий источник |
| [v2.hysteria.network](https://v2.hysteria.network/) | Hysteria2 official docs | рабочий source/test |
| [xtls.github.io](https://xtls.github.io/) | VLESS REALITY/XHTTP documentation | рабочий source/test |
| [sing-box.sagernet.org](https://sing-box.sagernet.org/) | sing-box protocols and routing docs | исследование/test |
| [bamsoftware.com/software/dnstt](https://www.bamsoftware.com/software/dnstt/) | dnstt source, signature и docs | рабочий canary source |
| [repo.powerdns.com](https://repo.powerdns.com/) / [dnsdist.org](https://dnsdist.org/) | dnstt DNS frontend | test infrastructure |
| [hev.cc](https://hev.cc/) | HEV socks5 tunnel reference | исследование/test |
| [shadowsocks.org](https://shadowsocks.org/) | Shadowsocks protocol reference | исследование |
| [softether.org](https://www.softether.org/) | SoftEther reference | исследование |
| [reqrypt.org](https://reqrypt.org/) | obfs/proxy reference | исследование |
| [community.torproject.org](https://community.torproject.org/) / [bridges.torproject.org](https://bridges.torproject.org/) | Tor/Pluggable Transports research | исследование |
| [datatracker.ietf.org](https://datatracker.ietf.org/) / [mailarchive.ietf.org](https://mailarchive.ietf.org/) | IETF RFC и MASQUE/protocol research | исследование |
| [ietf-wg-masque.github.io](https://ietf-wg-masque.github.io/) | MASQUE docs | исследование |
| [dnsprivacy.org](https://dnsprivacy.org/) / [dnsencryption.info](https://dnsencryption.info/) | DNS privacy/DoH/DoT references | исследование |
| [arxiv.org](https://arxiv.org/) / [usenix.org](https://www.usenix.org/) | Academic censorship/transport references | исследование |
| [nmap.org](https://nmap.org/) | Network diagnostics reference | диагностика |

## 8. Реальные сетевые smoke, media и selective-routing проверки

| Сайт или домен | Роль | Статус |
|---|---|---|
| [api.ipify.org](https://api.ipify.org/) / `api64.ipify.org` | Проверка внешнего IP/egress | постоянный smoke |
| [ifconfig.me](https://ifconfig.me/ip) | Резервная проверка внешнего IP | smoke fallback |
| [1.1.1.1](https://1.1.1.1/cdn-cgi/trace) | Cloudflare trace, DNS и connectivity | постоянный smoke |
| `8.8.8.8` | Google DNS/DoH и IP connectivity | постоянный smoke |
| [google.com/generate_204](https://www.google.com/generate_204) | Internet connectivity probe | постоянный smoke |
| `connectivitycheck.gstatic.com` / `www.gstatic.com` | Android/Google network validation и служебные assets | физический smoke |
| [youtube.com](https://www.youtube.com/) / [youtu.be](https://youtu.be/) | Страница, короткие ссылки, media playback и generate_204 | физический VPN smoke |
| [i.ytimg.com](https://i.ytimg.com/) | YouTube media/thumbnail reachability | физический smoke |
| [vk.com](https://vk.com/) / [www.vk.com](https://www.vk.com/) | Selective-routing/social-only проверка | test target |
| [max.ru](https://max.ru/) | Selective-routing и российский сервис без VPN | test/reference target |
| [rutube.ru](https://rutube.ru/) | Российский media reference | разовый test/reference |
| [ok.ru](https://ok.ru/) | Social routing reference | разовый test/reference |
| [discord.com](https://discord.com/) | Selective-routing domain/API reference | test target |
| [amazon.com](https://www.amazon.com/) | Текущий/проверенный REALITY camouflage target | transport test dependency |
| [microsoft.com](https://www.microsoft.com/) | Ранний REALITY target и TLS smoke | transport research/test |
| [cloudflare.com](https://www.cloudflare.com/) | TLS target и server clock/trace smoke | диагностика |
| [apple.com](https://www.apple.com/) | Ранний REALITY target candidate | transport research/test |
| [ipinfo.io](https://ipinfo.io/) / [wtfismyip.com](https://wtfismyip.com/) | Дополнительные IP/ASN проверки | разовая диагностика |
| [ssllabs.com](https://www.ssllabs.com/) | TLS diagnostics | разовая диагностика |
| [speedtest.net](https://beta.speedtest.net/) | Network throughput reference | разовая диагностика |

## 9. Закон, домен, рынок и конкурентные исследования

| Сайт или домен | Роль | Статус |
|---|---|---|
| [publication.pravo.gov.ru](https://publication.pravo.gov.ru/) | Официальные тексты законов о рекламе/VPN | исследование |
| [consultant.ru](https://www.consultant.ru/) | Правовые разъяснения | исследование |
| [normativ.kontur.ru](https://normativ.kontur.ru/) | Правовая/налоговая справка | исследование |
| [reestr.digital.gov.ru](https://reestr.digital.gov.ru/) | Российские цифровые реестры | исследование |
| [398-fz.rkn.gov.ru](https://www.398-fz.rkn.gov.ru/) | Роскомнадзор/reference | исследование |
| [cctld.ru](https://www.cctld.ru/) / [icann.org](https://www.icann.org/) | Domain/registrar справка | исследование |
| [onlinepatent.ru](https://onlinepatent.ru/) | Товарный знак и бренд | исследование |
| [home.treasury.gov](https://home.treasury.gov/) | Проверка санкционного риска VPS-провайдера Aeza | исследование |
| [levada.ru](https://www.levada.ru/) | Статистика использования VPN/доступа к ресурсам | исследование |
| [protonvpn.com](https://protonvpn.com/) | Конкурент, free/pricing benchmark | исследование |
| [mullvad.net](https://mullvad.net/) | Конкурент, pricing/privacy benchmark | исследование |
| [nordvpn.com](https://nordvpn.com/) | Конкурент, pricing benchmark | исследование |
| [surfshark.com](https://surfshark.com/) | Конкурент, pricing benchmark | исследование |
| [adguard-vpn.com](https://adguard-vpn.com/) | Конкурент и license/reference | исследование |
| [help.netflix.com](https://help.netflix.com/) | Streaming/device requirements reference | исследование |
| [tomsguide.com](https://www.tomsguide.com/) / [investegate.co.uk](https://www.investegate.co.uk/) | Владение/репутация VPN-компаний | исследование |

## 10. Что намеренно не включено как проектный сайт

- Личные вкладки, игры, новости, покупки, соцсети и почта, которые просто были открыты рядом, но не имели доказанной роли в Green VPN.
- Рекламные tracking-пиксели, captcha-assets, telemetry CDN и случайные ссылки из footer открытых страниц.
- `example.com`, `example.test`, `yookassa.test`, `bluevpn.local`, `localhost`, `127.0.0.1` и другие тестовые заглушки.
- URL с токенами, логинами, паролями, payment IDs, method IDs, invite-кодами и приватными конфигурациями.

## 11. Правило обновления реестра

При каждом новом внешнем сервисе добавлять:

1. корневой домен и безопасную ссылку;
2. назначение;
3. статус: рабочий, тестовый, кандидат, исторический или исследование;
4. владельца аккаунта/контракта без логина и секретов;
5. ссылку на отдельный runbook, если сервис влияет на production.
