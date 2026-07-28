# Полный аудит Green VPN: фактическое состояние и все оставшиеся хвосты

Дата среза: 28.07.2026, Europe/Moscow
Режим проверки: read-only для production, серверов, платежей и пользовательских устройств

## 1. Граница и достоверность аудита

Проверены:

- ключевые этапы истории проекта и решения, повлиявшие на текущий продукт;
- актуальные handoff/runbook/release-документы;
- рабочее дерево Git, версии, сборочные сценарии и CI;
- backend, Flutter и Android-тесты;
- точные опубликованные Windows/Android-артефакты и их манифесты;
- production и paid-beta на обоих control plane;
- пять разрешенных серверов в read-only режиме;
- публичные сайты, каталоги, health/readiness и внешние загрузки;
- физические доказательства прежних Windows/Android/payment smoke;
- текущее состояние запросов рекламным провайдерам в доступной почте.

Не выполнялись:

- изменения production, серверных флагов, маршрутов или клиентской сети;
- новые OTP, платеж, возврат, автосписание, KYC или принятие договоров;
- повторное управление Windows-клиентом;
- операции на Friendly Linnet `5.129.237.163`.

История проекта восстановлена по релевантным веткам решений, handoff-документам и
доказательствам. Сырые журналы чатов суммарным объемом более 12 ГБ не читались
буквально байт за байтом: это не добавило бы достоверности по сравнению с
проверкой всех этапов, на которых менялись требования, архитектура и релизное
состояние.

## 2. Итог одним абзацем

Green VPN уже является работающим продуктом прямой дистрибуции: публичные
Windows/Android-файлы скачиваются, базовый VPN smoke проходил на обеих
платформах, guest-first и email-восстановление работали, реальный платеж
активировал подписку, два российских control plane согласованы, три тарифа
опубликованы, реклама выключена. Но продукт **не находится в состоянии
«осталось только подписать Windows»**. Повторный независимый аудит обнаружил
два блокера уровня P0 и несколько P1: публично доступные старые backend-копии
на VPN-узлах, незакрытый налоговый/чековый процесс для платных продаж,
невоспроизводимый из чистого Git релиз, Android 16 KB/API-совместимость,
отсутствие строгого six-stage smoke именно опубликованных артефактов и
неопределенный контракт «бесплатный тариф или трехдневный Trial».

## 3. Шкала приоритетов

| Уровень | Значение |
|---|---|
| P0 | Блокирует публичный релиз или прием реальных денег |
| P1 | Обязательно закрыть до следующего публичного кандидата |
| P2 | Закрыть до масштабирования и активного привлечения пользователей |
| P3 | Допустимый будущий этап, если функция пока выключена |

## 4. Главные блокеры

### P0. Старые публичные backend-копии на VPN-узлах

На NL1 `37.220.85.211` и London `88.218.250.86` активен и включен старый
`bluevpn-backend.service`, слушающий `0.0.0.0:8000`.

Повторная внешняя проверка:

- `http://37.220.85.211:8000/healthz` отвечает `200`, версия `0.9.103`;
- `http://88.218.250.86:8000/healthz` отвечает `200`, версия `0.9.105`;
- оба старых `/api/v1/catalog/tariffs` отвечают `200` и отдают устаревший
  каталог `2026-05-14-flex-v3` с одним тарифом;
- на NL1 старый backend также доступен через порт 80;
- в старых БД остаются записи пользователей, устройств, подписок и заказов.

Это одновременно:

- лишняя публичная поверхность атаки;
- риск split-brain между новыми и старыми control plane;
- хранение дублированных пользовательских и платежных записей;
- прямое противоречие текущим документам, где NL1/London описаны как VPN-узлы,
  а не действующие публичные API.

Правильное закрытие:

1. Сделать шифрованный backup старых БД/env и зафиксировать retention.
2. Проверить по логам и клиентским версиям, не используют ли старые клиенты
   legacy endpoint.
3. Немедленно закрыть внешний `8000` firewall/Nginx-правилом.
4. Остановить и отключить backend NL1.
5. Для London либо провести контролируемую миграцию legacy-клиентов, либо
   оставить только строго ограниченный совместимый endpoint без прямого 8000.
6. Ротировать старые credentials и удалить дубли после подтвержденного backup.

Автоматически выполнять это в рамках аудита нельзя: сначала нужен backup и
проверка legacy-клиентов.

### P0 для платных продаж. Нет доказанного чека самозанятого

Реальная YooKassa-оплата, webhook, активация подписки и восстановление аккаунта
были проверены. Это доказывает технический платежный путь, но не закрывает
налоговый чек.

Текущий запрос к YooKassa содержит сумму, capture, confirmation, description,
metadata и сохранение метода оплаты, но не содержит fiscal receipt/customer/
tax items/VAT. Email в metadata сам по себе чек не формирует.

Официальная документация YooKassa различает платежное подтверждение и
фискальный чек. С 29.12.2025 YooKassa прекратила поддержку формирования чеков
для самозанятых; доход и чек нужно проводить через «Мой налог» или подходящего
авторизованного партнера:

- [YooKassa: основы чеков](https://yookassa.ru/developers/payment-acceptance/receipts/basics)
- [YooKassa: журнал изменений](https://yookassa.ru/developers/using-api/changelog)
- [ФНС: НПД и выдача чека](https://npd.nalog.ru/faq/)

До приема публичных денег нужно:

1. Подтвердить фактический налоговый статус владельца.
2. Выбрать процесс: ручная очередь «Мой налог» либо интеграция с разрешенным
   партнером.
3. Связать payment/order с номером и статусом налогового чека.
4. Определить коррекцию чека при возврате.
5. Исправить пользовательский текст: «email для уведомления/доступа» нельзя
   выдавать за доказанный фискальный чек.

### P1. Опубликованный релиз не воспроизводится из чистого Git

Текущее состояние:

- ветка `green-vpn-transport-canary-20260711`;
- HEAD `9164bba`;
- ветка опережает origin на 26 коммитов;
- 79 tracked-файлов изменены, 46 файлов untracked;
- текущие public Android `0.3.15`, Windows `0.3.17` и backend `0.9.148`
  в значительной части опираются на незакоммиченное состояние;
- соответствующего чистого release tag нет;
- последний близкий tag: `greenvpn-final-full-audit-20260719`;
- `android/transport_preview/awg_tunnel/` игнорируется Git и восстанавливается
  из внешнего pinned-источника;
- `VERSION.txt` и несколько build-defaults содержат старые версии.

Checkpoint и Git bundle полезны для аварийного восстановления, но bundle
содержит только HEAD, а не все незакоммиченные исходники. Это не clean build.

Нужно:

1. Зафиксировать точный source snapshot без секретов и generated-мусора.
2. Сделать transport dependencies воспроизводимыми, включая offline/cache
   стратегию и проверяемые SHA.
3. Удалить или синхронизировать все ручные default version.
4. Собрать Android/Windows/backend в чистом workspace из одного commit/tag.
5. Сравнить полученные артефакты с manifest/SBOM/provenance.

### P1. Android: 16 KB page size и API 24/25

Точный публичный APK:

- package `pro.greenvpn.app`;
- version `0.3.15+2026072704`;
- minSdk 24;
- targetSdk 36.

ARM64-библиотека AmneziaWG `libawg2-go.so` в точном APK имеет LOAD alignment
`0x1000`, то есть 4 KB. Для новых/обновляемых Google Play-приложений с target
Android 15+ действует требование поддержки 16 KB. Нужна пересборка native
библиотеки и физический smoke на 16 KB-среде:

- [Android Developers: поддержка 16 KB page size](https://developer.android.com/guide/practices/page-sizes)

Дополнительно transport lint показал:

- AWG-модуль: 5 `NewApi` ошибок; в app desugaring включен, в модуле нет;
- Hysteria-модуль: 27 `NewApi` ошибок API 26 при заявленном minSdk 24;
- Hysteria2, VLESS, Naive и dnstt контроллеры сейчас сами возвращают
  unavailable на API 24/25, поэтому нормальный cascade их пропускает, но
  поддержка Android 7.0/7.1 получается неполной.

Нужно принять одно честное решение:

- поднять minSdk до 26; либо
- сохранить minSdk 24 и сделать API-safe реализацию/изоляцию с тестами.

### P1. Six-stage cascade доказан не на всех точных public-артефактах

Документация утверждает, что exact Android release и полный transport matrix
физически проверены. Фактические доказательства разделяются:

- точный production Android `pro.greenvpn.app` прошел install/cold launch,
  базовое подключение, egress и чистое отключение;
- успешная 16-route transport matrix и Quick Tile six-stage cascade выполнены
  на side-by-side package `pro.greenvpn.app.transportpreview`;
- точный Windows installer прошел аудит и реальный WireGuard runtime failover,
  но это не физический проход всех шести transport groups.

Следовательно, код и preview-маршруты доказаны, но строгая цепочка fallback
точно опубликованных Android/Windows-артефактов еще не доказана.

Нужно собрать более высокие версии и прогнать exact-artifact matrix:

- по одному преднамеренно недоступному этапу;
- проверка порядка, timeout, fail-closed и recovery;
- egress/DNS/cleanup после каждого успешного fallback;
- Android обычный UI и Quick Tile;
- Windows installer, а не preview runner.

### P1. Не определен единый контракт Free/Trial

Фактическое production-состояние:

- production free tier выключен;
- новый guest получает backend-подписку типа Trial на 3 дня;
- `subscriptionEnforced=false`, поэтому окончание Trial не закрывает доступ;
- клиент показывает гостю «Бесплатный»;
- сайты говорят «Бесплатный старт», но не называют трехдневный срок.

Paid-beta умеет server-side:

- включать/выключать free tier;
- менять месячную квоту без пересборки;
- менять лимит устройств;
- хранить профиль 10/20 Мбит/с;
- включать/выключать quota enforcement.

Но сейчас quota enforcement выключен, а `10 Мбит/с` является профилем policy:
Linux `tc` shaping еще не применяет реальное ограничение. Quota exhaustion
fail-closed физически не проверен.

Нужно выбрать один Product Contract:

1. **Постоянный Free:** понятная квота/скорость, физический exhaustion smoke,
   измеримое shaping или честная формулировка best effort.
2. **Trial 3 дня:** одинаковый текст на сайтах/клиентах, включенное enforcement,
   проверка expiry/grace/restore/upgrade и способ вернуть существующую покупку.

До этого нельзя считать onboarding и монетизацию завершенными.

## 5. Другие обязательные хвосты

### P2. Billing lifecycle

Доказано:

- guest -> email-код -> YooKassa -> webhook -> активация;
- доступ на Windows и Android;
- восстановление существующего аккаунта;
- сохраненный метод можно отвязать.

Не доказано:

- реальный возврат и связанная коррекция чека;
- реальное автосписание;
- отмена renewal до списания и после неуспешного списания;
- retry/dunning/idempotency на реальном provider event.

Production renewal executor сейчас выключен. Если автопродление остается
выключенным, это не блокирует одноразовую продажу после закрытия P0-чека, но
UI и договор не должны обещать работающую подписочную модель.

### P2. Документация противоречит фактам

Особенно опасны:

- `docs/RELEASE_STATE.md`: «ровно один owner blocker: windows_trust»;
- `docs/NEXT_OWNER_ACTIONS_RU.md`: «других обязательных действий нет»;
- `docs/CURRENT_HANDOFF.md`: exact Android matrix описана как production APK;
- topology-документы не отражают публичные старые API на NL1/London;
- `VERSION.txt` и build defaults отстали от production.

Эти документы нельзя просто косметически исправить до устранения P0/P1:
сначала меняется фактическое состояние, затем единый source of truth.

### P2. Два разных публичных сайта

- `greenvpn.pro` отдает новую статическую главную;
- `api.greenvpn.pro` и fallback отдают другую, более старую главную;
- тарифы `249/649/1099` совпадают;
- legal pages совпадают;
- содержимое landing page и его SHA не совпадают.

Предыдущая площадка РСЯ была привязана к `api.greenvpn.pro`, то есть модератор
видел не новую canonical-страницу. До новой заявки нужно унифицировать
canonical landing и зеркало. Текущий public probe проверяет доступность, но не
контентную идентичность.

### P2. Privacy/legal readiness

Публичная политика описывает email, guest ID, устройство, сервер и счетчики,
но не найдено отдельного доказанного процесса по:

- IP/nginx/security logs и точным срокам хранения;
- удалению/экспорту данных;
- трансграничной обработке на иностранных VPN-узлах;
- уведомлению Роскомнадзора и локализации;
- legal review оферты, возвратов и пользовательских ограничений.

Это не утверждение о нарушении. Это отсутствие проверяемого compliance packet.
Перед платным масштабированием нужен юрист по РФ и зафиксированный checklist.

### P2. Эксплуатация серверов

Хорошее:

- на пяти проверенных серверах нет failed systemd units;
- SQLite `quick_check` успешен;
- production/paid-beta на российских control plane синхронны;
- public uvicorn на control plane слушает localhost;
- SSH root password login выключен;
- сертификаты имеют запас примерно 66-69 дней;
- внешняя readiness-проверка: 12 green, 0 yellow, 0 red.

Хвосты:

- RUVDS Moscow использует около 72.9% root disk;
- backup-каталоги занимают около 3.54 GiB;
- Timeweb и NL2 имеют по шесть доступных системных обновлений;
- dnstt существует только на NL2 и не имеет резервирования;
- старые backend NL1/London остаются главным эксплуатационным риском.

### P3. Rewarded-реклама

Сейчас реклама корректно выключена:

- master gate, Android Rewarded, web Rewarded и beta `test_web` выключены;
- placement/provider ID в production нет;
- принудительный таймер отключения VPN выключен;
- fake completion, autoplay, скрытые показы и искусственные клики не нужны и
  не допустимы.

Статус провайдеров:

- Adsterra исключена: incentivized traffic запрещен;
- AppLixir исключена: неподходящий вывод в РФ и минимум 100 000 показов;
- Monetag исключена: Rewarded только Telegram Mini Apps, РФ-регистрация закрыта;
- MediaToday: ответа нет, включая поиск в спаме/корзине;
- ayeT ticket `677322`: только автоматический receipt;
- РСЯ остается теоретически лучшим кандидатом, но текущий чат в браузере не
  авторизован, поэтому новый ответ после последнего промежуточного статуса в
  этом аудите не подтвержден.

Реклама не является launch blocker, пока продукт честно работает без нее.
Возвращать ее можно только после письменного разрешения сценария VPN/WebView2,
подтверждаемого completion, понятного вывода в РФ и paid-beta smoke.

### P3. Каналы дистрибуции

- Direct Android/Windows download работает.
- Windows installer не подписан (`NotSigned`).
- Нужен Authenticode Code Signing certificate, а не лицензия Windows 10/11.
- Google Play не готов до исправления 16 KB/native и store checklist.
- iOS/macOS/Linux/web остаются Flutter-скелетами, а не поддерживаемыми
  продуктами; их нельзя рекламировать как готовые платформы.

## 6. Что доказанно работает сейчас

### Код и тесты

| Проверка | Результат |
|---|---:|
| Release gate | 0 warnings, 0 errors |
| Backend tests | 162/162 passed |
| Flutter analyze | no issues |
| Flutter default tests | 63 passed, 6 skipped |
| Explicit public-product tests | 4 passed |
| Explicit paid-beta free-tier tests | 5 passed |
| Android unit tests со всеми transport flags | 46/46 passed |
| Secret scan с untracked/history | passed |
| `pip-audit` | известных уязвимостей нет |
| `git diff --check` | whitespace errors нет |
| Android transport lint | failed, см. P1 выше |

### Публичная поверхность

| Проверка | Результат |
|---|---:|
| Public surface probe | 31/31 |
| Manifest checker | 18/18 |
| Exact body SHA downloads | 8/8 |
| Production/paid-beta backend | `0.9.148-owner-boundary.1` на обоих узлах |
| Каталог | три тарифа: 249/649/1099, `autoRenew=false`, ads=false |
| Windows | `0.3.17`, installer доступен, `NotSigned` |
| Android | `0.3.15+2026072704`, APK доступен |

### Физические проверки, которые не нужно повторять без смены артефакта

- базовая установка/запуск/подключение/egress/отключение exact Android APK;
- базовый Windows tunnel и WireGuard runtime failover;
- guest/email-код и восстановление аккаунта;
- реальная YooKassa-оплата и активация;
- public download hashes и оба зеркала;
- SMTP delivery.

Отдельно все еще нужны exact six-stage cascade, refund/tax receipt и, если
функция будет включаться, real renewal. Это другие проверки, а не повторение
уже пройденных.

## 7. Фактическая готовность по подсистемам

| Подсистема | Статус | Что осталось |
|---|---|---|
| Windows direct release | Частично готов | Authenticode; clean rebuild; exact six-stage matrix |
| Android direct release | Частично готов | 16 KB; API 24/25 решение; exact production matrix |
| VPN data plane | Работает | exact cascade proof; dnstt redundancy по желанию |
| Российские control plane | Работают | clean source release; hard expiry/product contract |
| Старые foreign API | P0 | закрыть exposure и split-brain |
| Guest-first auth | Работает | согласовать expiry/free UX |
| Email account restore | Работает | lifecycle/retention runbook |
| YooKassa payment | Технически работает | налоговый чек; refund; renewal policy |
| Free tier | Только paid-beta policy | выбрать production contract; quota/shaping smoke |
| Rewarded ads | Выключены | провайдера нет; можно выпускаться без рекламы |
| Public websites | Работают | унифицировать landing и wording |
| Admin/monitoring | Работают | stale API visibility и retention alerts |
| Privacy/legal | Не доказано полностью | legal/compliance packet |
| Google Play | Не готов | 16 KB/native/store/policy |
| Windows trust | Не готов | Code Signing certificate после технического закрытия |
| iOS/macOS/Linux | Не продукт | отдельный будущий scope |

## 8. Почему прежний вывод оказался слишком оптимистичным

Повторились несколько ошибок процесса:

1. `healthz=200` принимался за доказательство полной исправности, хотя отдельные
   endpoint могли зависать, а старые backend оставались публичными.
2. Успешная сборка или preview smoke принимались за exact public artifact smoke.
3. Незакоммиченное рабочее дерево не включалось в release Definition of Done.
4. Реальный платеж ошибочно воспринимался как вся платежная/налоговая готовность.
5. Handoff-документы цитировались как факт без повторной независимой проверки.
6. Ранее stale build был упакован после ошибки Flutter; это подтверждает, что
   номера версий и наличие файла не доказывают происхождение артефакта.
7. Слово Beta однажды заменило реальные тарифы, а реклама однажды оказалась
   включена не по продуктовому контракту: UI и feature flags менялись без
   полного regression matrix.
8. SMS начали внедрять до доказанной необходимости и затем удалили; guest-first
   нужно было заморозить как Product Contract раньше.
9. Расширение Windows MVP сразу до Android, billing, ads, admin и шести
   транспортов создало много параллельных незакрытых контуров.
10. Фраза «осталась лицензия Windows» смешала OS license и Authenticode.

## 9. Единственная правильная последовательность завершения

### Этап 0. Заморозка и доказательства

- не менять public artifacts;
- сделать новые encrypted backups;
- сохранить текущие health/catalog/manifests;
- зафиксировать этот аудит как новый source of truth.

### Этап 1. Закрыть P0 старых backend

- проверить legacy usage;
- закрыть direct `8000`;
- вывести NL1 backend из эксплуатации;
- мигрировать/ограничить London legacy;
- ротировать credentials;
- проверить снаружи, что старые catalog/auth/config больше недоступны.

### Этап 2. Заморозить Product Contract

Владелец выбирает:

- permanent Free; или
- 3-day Trial.

После выбора одинаково обновляются backend policy, Windows, Android, сайт,
каталог, оферта и тесты.

### Этап 3. Закрыть платежно-правовой контур

- определить налоговый статус и процесс чеков;
- реализовать order-to-receipt tracking;
- подготовить refund/correction runbook;
- сверить оферту/privacy/renewal wording с юристом;
- только затем разрешать public paid sales.

### Этап 4. Исправить Android

- 16 KB-сборка AWG native;
- решить minSdk 24 или 26;
- устранить transport lint errors;
- добавить lint всех модулей в CI.

### Этап 5. Сделать воспроизводимый release

- чистый commit/tag;
- единый version source;
- pinned dependencies с SHA;
- clean-room Android/Windows/backend build;
- manifest, SBOM и provenance;
- CI запускает transport flags, lint и explicit product tests.

### Этап 6. Новый exact-artifact canary

- версии выше `0.3.15` Android и `0.3.17` Windows;
- exact six-stage cascade matrix;
- Android API/16 KB matrix;
- Windows install/update/rollback;
- paid-beta на обоих control plane;
- физический smoke владельца только там, где без него нельзя.

### Этап 7. Синхронизировать поверхности

- одна canonical landing;
- одинаковые тарифы/free-trial wording;
- обновить handoff/release/runbook;
- public probe проверяет не только HTTP, но и content parity.

### Этап 8. Windows trust

- получить Authenticode Code Signing certificate;
- подписать payload/bootstrap/installer;
- проверить publisher/timestamp/hash;
- выпустить более высокую подписанную версию.

### Этап 9. Контролируемый production rollout

- backup;
- один control plane за раз;
- canary;
- exact download/hash;
- auth/payment/tunnel smoke;
- наблюдение;
- доказанный rollback.

## 10. Что в итоге требуется от владельца

После автономного инженерного закрытия от владельца должны остаться только:

1. Выбрать permanent Free или 3-day Trial.
2. Подтвердить налоговый статус и допустимый способ формирования чеков.
3. Получить Authenticode Code Signing certificate.
4. Отдельно разрешить реальный возврат/автосписание, если эти денежные smoke
   действительно нужны.
5. Провести финальный физический smoke перед production-разрешением.

Все остальное — cleanup серверов, исправления Android, CI, clean build,
синхронизация сайтов/документов и paid-beta — инженерная работа, которую можно
сделать без постоянного участия владельца.

## 11. Текущий Definition of Done

Релиз можно назвать завершенным только когда одновременно выполнено:

- P0 exposure закрыт и проверен извне;
- платные продажи имеют рабочий налоговый чек либо остаются выключенными;
- выбран и согласован Free/Trial contract;
- исходники находятся в чистом commit/tag;
- exact Android/Windows artifacts воспроизводятся из этого tag;
- Android проходит 16 KB и выбранную minSdk matrix;
- exact artifacts проходят strict six-stage cascade;
- сайты, клиенты, каталог и договор говорят одно и то же;
- Windows successor подписан;
- paid-beta/canary пройден;
- production выпущен с backup, мониторингом и rollback;
- итоговые handoff/release docs отражают факты, а не намерения.

До выполнения этих условий Green VPN можно использовать как работающий
ограниченный direct-download продукт, но нельзя честно считать полностью
закрытым коммерческим релизом.
