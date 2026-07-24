# Device gate Node 22 — 24 июля 2026

## Проверенный артефакт

- commit приложения: `94b11fd222286c74f7546d3575f6564da977623e`;
- workflow run: `30087395773`;
- artifact: `SillyTavernServer-stage2-node22-device-experimental`;
- размер IPA: `22 104 189` байт;
- SHA-256 IPA:
  `9ef48eed83c73d8a8a7e6e526142d2028ccf54dce1621026453ddd71edb69cd5`;
- способ запуска: LiveContainer на физическом iPhone;
- версия iOS и модель устройства: не записаны.

## Подтверждено снимками экрана

- NodeMobile сообщает `v22.9.0`;
- управляющий сервер запущен на динамическом localhost-порту;
- присутствует маркер `ST_CONTROL_READY`;
- content server запущен на `127.0.0.1:8000`;
- присутствует маркер `ST_SERVER_READY`;
- встроенный `WKWebView` открывает и отображает HTTP-страницу;
- после исправления отсутствует `ST_RUNTIME_ERROR`;
- предупреждение `--expose_wasm` подтверждает режим без WebAssembly.

Предшествующая сборка доходила до HTTP-ready, но затем падала при ESM-загрузке
`node:http`: синхронизация ленивых экспортов загружала Undici, которому
требовался WebAssembly. Исправление загружает HTTP-модуль через CommonJS и
не вычисляет неиспользуемые экспорты Undici.

Сообщение LiveContainer
`sandbox_extension_issue_file ... Operation not permitted` появилось после
перехода приложения в фон. Оно не остановило уже запущенный localhost и на
этом тесте считается нефункциональным предупреждением среды контейнера.

## Что этот gate разрешает

Успешно выполнен переход к Stage 3: CI может включать закреплённый payload
SillyTavern 1.18.0 и проверять его в `--jitless`. Этот документ не объявляет
сам SillyTavern проверенным на iPhone: для Stage 3 требуется новая IPA и
отдельная проверка настоящей главной страницы, данных, API и stop/start/restart.
