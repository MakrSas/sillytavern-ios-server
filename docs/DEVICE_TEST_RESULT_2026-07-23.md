# Результат device smoke-test — 23 июля 2026

## Проверенный артефакт

- commit: `9fbde8eeee39415c5cbde8008f003d37e4242296`;
- workflow run: `30023193444`;
- artifact: `SillyTavernServer-stage2-node18`;
- IPA SHA-256:
  `42DDC690F03B8322343E48208F99705E2C26619D304789FB063EB1C403143BEF`;
- способ запуска: LiveContainer на физическом iPhone;
- версия iOS и модель устройства: не записаны.

## Подтверждено снимками экрана

- приложение запускается на физическом iPhone;
- динамический `NodeMobile.framework` корректно загружается;
- runtime сообщает `v18.20.4`;
- control server запущен на `127.0.0.1:51662`;
- content server запущен на `127.0.0.1:8000`;
- присутствуют маркеры `ST_CONTROL_READY` и `ST_SERVER_READY`;
- HTTP-страница открывается во встроенном браузере;
- HTTP-страница успевает открыться в Safari после перехода приложения в фон;
- приложение корректно показывает предупреждение о возможной suspension.

## Существенное наблюдение

V8 напечатал:

```text
Warning: disabling flag --expose_wasm due to conflicting flags
```

Это подтверждает, что опубликованный NodeMobile 18 работает без доступного
WebAssembly. Полная интеграция SillyTavern не должна начинаться, пока отдельно
не проверены или не заменены WASM-зависимости Jimp и `tiktoken`.

Сообщение:

```text
sandbox_extension_issue_file failed for : 2 (No such file or directory)
```

не остановило control/content servers и на данном тесте является
нефатальным. Его источник нужно повторно проверить на обычной установке
SideStore/AltStore без LiveContainer.

## Пока не подтверждено

- точная длительность работы localhost после перехода в Safari;
- stop/start/restart на устройстве;
- автоматический выбор следующего порта при занятом 8000;
- восстановление состояния после перезапуска iPhone;
- запуск Node 22;
- WebAssembly, Jimp и `tiktoken`;
- настоящий сервер SillyTavern.
