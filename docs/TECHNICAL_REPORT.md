# Технический отчёт: Node.js и SillyTavern на iOS

Дата проверки: 23 июля 2026 года.

## Итог

Встроить Node.js в обычное iOS-приложение технически возможно: NodeMobile
собирает Node/V8/libuv/OpenSSL в статический iOS framework и запускает V8 без
JIT. Этого достаточно для минимального HTTP-сервера.

Полный заявленный сценарий SillyTavern в отдельном Safari пока нельзя считать
работоспособным по двум независимым причинам:

1. нет опубликованного NodeMobile 20+; порт Node 22 не завершён;
2. при открытии Safari хост-приложение переходит в фон и обычно
   приостанавливается iOS, вместе с Node event loop.

Кроме того, сервер SillyTavern использует WebAssembly-зависимости, тогда как
V8 на iOS device без JIT требует отдельного WASM-интерпретатора либо замены
таких зависимостей.

Поэтому репозиторий останавливается на честном Stage 2: настоящий встроенный
Node HTTP-server, SwiftUI-управление и воспроизводимые CI-сборки.

## Проверенные исходные факты

### SillyTavern

Официальный `release/package.json`:

- версия `1.18.0`;
- `engines.node = ">= 20"`;
- точка запуска `server.js`;
- лицензия AGPL-3.0.

Официальная документация рекомендует ветку `release`. В standalone-режиме
актуальные данные хранятся в `./config.yaml` и `./data`; при обновлении ZIP
документация требует переносить именно их.

Источники:

- <https://github.com/SillyTavern/SillyTavern>
- <https://raw.githubusercontent.com/SillyTavern/SillyTavern/release/package.json>
- <https://docs.sillytavern.app/installation/>
- <https://docs.sillytavern.app/installation/updating/>

### NodeMobile

Последний опубликованный релиз:

- NodeMobile/Node.js `18.20.4`;
- готовые slices для iPhone arm64 и симулятора;
- запуск через C-функцию `node_start(int argc, char *argv[])`.

Сборочный скрипт NodeMobile включает `--v8-options=--jitless`, отключает
snapshot/code cache и собирает статические библиотеки.

Открытый PR обновления до Node 22.9.0 содержит исправления для:

- iOS deployment target 14;
- libuv;
- C++20;
- V8;
- генерации `node_js2c`.

PR остаётся открытым и не имеет опубликованного артефакта.

Источники:

- <https://github.com/nodejs-mobile/nodejs-mobile/releases/tag/v18.20.4>
- <https://github.com/nodejs-mobile/nodejs-mobile/pull/134>
- <https://github.com/nodejs-mobile/nodejs-mobile/tree/update22-9-0>

### JIT и WebAssembly

JIT-less V8 исполняет JavaScript через Ignition без выделения исполняемой
памяти. Это подходящая модель для обычного iOS-приложения.

Но в конфигурации V8 для iOS device WebAssembly и оптимизирующие компиляторы
отключаются, потому что сторонним приложениям недоступны исполняемые страницы.
Новые версии V8 разрабатывают WASM-интерпретатор DrumBrake, однако наличие и
пригодность этой конфигурации в Node 22 mobile fork должны быть доказаны
сборкой и тестом.

Источники:

- <https://v8.dev/blog/jitless>
- <https://chromium.googlesource.com/v8/v8/+/refs/tags/12.4.110/gni/v8.gni>

### Ограничение фона

Apple прямо указывает, что обычное приложение в фоне обычно находится в
состоянии suspended. Допустимые постоянные фоновые режимы относятся к
конкретным функциям: аудио, location, VoIP и другим заявленным сервисам.
Использовать их фиктивно для localhost-сервера нельзя.

При запуске Safari текущее приложение перестаёт быть foreground. Короткий
background task даёт время закончить ограниченную операцию, но не превращает
приложение в постоянный сервер.

Источники:

- <https://developer.apple.com/documentation/xcode/configuring-background-execution-modes>
- <https://developer.apple.com/documentation/UIKit/about-the-background-execution-sequence>
- <https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time>

## Анализ зависимостей SillyTavern 1.18.0

В `package-lock.json` найдено 830 package entries. Явный install script отмечен
только у `protobufjs`, но отсутствие install script не означает отсутствие
платформенного ограничения.

В production dependency graph присутствуют:

- `@jimp/wasm-avif`;
- `@jimp/wasm-jpeg`;
- `@jimp/wasm-png`;
- `@jimp/wasm-webp`;
- `tiktoken`;
- `onnxruntime-web`.

`src/jimp.js` импортирует четыре WASM-кодека напрямую. Этот модуль, в свою
очередь, импортируется endpoint-модулями characters, avatars, thumbnails,
content manager и image metadata. `src/server-startup.js` импортирует
tokenizer router, который импортирует `tiktoken`.

Следовательно, проверка только Express/HTTP недостаточна. До интеграции
SillyTavern обязательны:

```text
typeof WebAssembly
import("@jimp/wasm-png")
import("tiktoken")
import("./src/jimp.js")
import("./src/server-startup.js")
node server.js
GET http://127.0.0.1:<port>/
```

## Выбранная архитектура Stage 2

```text
SwiftUI
  │
  ├── ServerController
  │     ├── состояние и логи
  │     └── HTTP control client
  │
  └── Objective-C++ bridge
        └── node_start()
              ├── control HTTP server (127.0.0.1, динамический порт)
              └── content HTTP server (127.0.0.1, 8000+)
```

NodeMobile не является дочерним процессом: он выполняется в потоке того же
iOS-процесса. Поэтому:

- нельзя применять `Process`/`NSTask`;
- system kill приложения автоматически завершает runtime;
- повторный `node_start()` в одном процессе не считается поддержанным;
- stop/restart реализованы закрытием и повторным созданием content server при
  сохранении control server и Node event loop.

## Почему используется WKWebView

Встроенный `WKWebView` оставляет приложение foreground, поэтому Node event
loop продолжает обслуживать localhost. Это рабочая архитектура публичных API.

Внешний Safari оставлен только экспериментальной кнопкой с предупреждением.
Он может успеть загрузить страницу до suspension, но это не является
надёжным пользовательским режимом.

## CI-стратегия

### Baseline

`build-prototype-ipa.yml` использует опубликованный NodeMobile 18.20.4.
Назначение — доказать корректность Xcode/Swift/Objective-C++ integration.

### Experimental Node 22

`build-node22-and-ipa.yml` собирает device и Apple Silicon simulator slices из
закреплённого коммита Node 22.9.0 port. Закрепление защищает CI от незаметного
изменения выполняемых build scripts.

Node 22.9.0 не является финальным runtime. После успешного device proof порт
нужно вручную перебазировать на актуальный Node 22 (на дату отчёта —
`22.23.1`), повторно собрать и прогнать полный тест.

Текущие GitHub-hosted `macos-15` runners содержат Xcode 16.4; workflow выбирает
его явно, чтобы `macos-latest` не переключился на новый major Xcode.

Источники:

- <https://github.com/actions/runner-images>
- <https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md>
- <https://nodejs.org/dist/index.json>

## Обновления и резервные копии

Полный on-device update manager сознательно не включён в Stage 2. Реализовать
его до подтверждения runtime означало бы создать неработающую оболочку.

После прохождения Node/SillyTavern тестов допустимая схема:

1. остановить content server;
2. скопировать `config.yaml`, весь `data`, manifest и runtime version в новый
   каталог `Backups/<timestamp>`;
3. скачать только официальный tag archive в `Updates`;
4. проверить ожидаемый tag, размер, структуру и локальный manifest;
5. распаковать в уникальный staging-каталог;
6. не запускать shell-скрипты из архива;
7. перенести сохранённые пользовательские данные;
8. проверить imports и запуск на staging;
9. поменять указатель `current` атомарным rename внутри одного filesystem;
10. выполнить HTTP health check;
11. при ошибке вернуть предыдущий указатель.

`node_modules` должен создаваться доверенным CI для точно закреплённого
релиза. Выполнение произвольных npm scripts на iPhone не допускается.

## Критерии перехода к Stage 3

- оба Node 22 XCFramework slices собираются;
- unsigned IPA компилируется;
- IPA подписывается SideStore/AltStore;
- на физическом iPhone подтверждается версия runtime;
- smoke-server проходит start/stop/restart;
- JIT entitlement отсутствует;
- WebAssembly/Jimp/tiktoken проходят либо заменены совместимыми реализациями;
- `server.js` SillyTavern отвечает по HTTP во встроенном WKWebView;
- пользовательские данные переживают перезапуск приложения;
- задокументировано, что Safari не является надёжным foreground-клиентом.
