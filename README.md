# SillyTavern Server для iOS — технический прототип

Экспериментальное SwiftUI-приложение, которое встраивает Node.js через
NodeMobile и запускает настоящий HTTP-сервер только на `127.0.0.1`.

> Текущий статус: **Stage 2 / технический прототип**. Проект пока не содержит
> SillyTavern и не считается готовым приложением. JavaScript-протокол проверен
> локально, но сборка NodeMobile и запуск на физическом iPhone ещё должны пройти
> в GitHub Actions и на устройстве.

## Что уже реализовано

- полноценный Xcode-проект и общая схема сборки;
- SwiftUI-интерфейс со статусами «Не запущен», «Запускается», «Работает»,
  «Останавливается» и «Ошибка»;
- Objective-C++ мост к настоящему `node_start()`;
- захват `stdout` и `stderr`;
- локальный Node.js smoke-server на `127.0.0.1`;
- автоматический выбор следующего свободного порта, если желаемый занят;
- `health`, запуск, остановка и перезапуск HTTP-сервера;
- встроенный `WKWebView`, при котором приложение остаётся на переднем плане;
- экспериментальная кнопка Safari с обязательным предупреждением;
- sandbox-каталоги `Runtime`, `UserData`, `Updates`, `Backups` и `Logs`;
- сохранение и ограничение размера лога;
- проверка последнего официального релиза SillyTavern через GitHub API;
- проверяемая загрузка официального NodeMobile 18.20.4;
- отдельная GitHub Actions-сборка экспериментального NodeMobile 22.9.0;
- упаковщик официального исходного архива SillyTavern без выполнения его
  shell-скриптов и без npm lifecycle scripts;
- unsigned IPA, предназначенный для последующей подписи SideStore/AltStore.

## Почему SillyTavern ещё не включён

На 23 июля 2026 года:

- SillyTavern `1.18.0` требует Node.js `>= 20`;
- последний опубликованный NodeMobile для iOS — `18.20.4`;
- незавершённый мобильный порт Node 22 основан на `22.9.0`;
- актуальная ветка Node 22 уже дошла до `22.23.1`;
- SillyTavern импортирует WASM-кодеки Jimp и `tiktoken`, а V8 на iOS-устройстве
  без исполняемых страниц ограничивает или отключает WebAssembly.

Поэтому Node 22 сначала должен:

1. собраться как iOS XCFramework;
2. запустить smoke-server на физическом iPhone;
3. пройти отдельные тесты `WebAssembly`, Jimp и `tiktoken`;
4. быть обновлён с устаревшего экспериментального 22.9.0 до поддерживаемого
   патч-релиза;
5. только затем получить payload SillyTavern.

Подробности: [технический отчёт](docs/TECHNICAL_REPORT.md).

## Структура

```text
SillyTavernServer/
├── App/                  SwiftUI entry point
├── Models/               статусы и ответы control API
├── Runtime/              NodeMobile bridge и controller
├── Services/             sandbox-каталоги
├── Views/                сервер, логи, настройки, WKWebView
└── Resources/
    └── nodejs-project/   настоящий Node.js smoke-server

Vendor/
└── NodeMobile.xcframework/   создаётся скриптом или CI, в Git не хранится

scripts/
├── prepare-node18-runtime.sh
├── build-node22-slice.sh
├── package-ipa.sh
└── package-sillytavern.sh
```

## Сборка в GitHub Actions

### 1. Доказательство интеграции на опубликованном NodeMobile 18

Запустите workflow **Build Stage 2 prototype IPA**.

Он:

1. проверит JavaScript;
2. прогонит локальный тест `health → stop → start → restart`;
3. скачает официальный NodeMobile 18.20.4;
4. проверит SHA-256 архива;
5. соберёт приложение для симулятора;
6. соберёт unsigned `SillyTavernServer-unsigned.ipa`.

Node 18 используется только для проверки механизма встраивания. Он не подходит
для актуального SillyTavern.

### 2. Экспериментальный Node 22

Вручную запустите workflow **Build experimental Node 22 and IPA**.

Он параллельно собирает:

- `iphoneos-arm64`;
- `iphonesimulator-arm64`;

после чего создаёт `NodeMobile.xcframework` и unsigned IPA.

Исходник закреплён на конкретном коммите
`106c51f95d55d1010de56a2ffd09bfb4ba819a47`. Workflow не следует за
изменяемой веткой и поэтому не начинает выполнять новый код без ревью.

Этот workflow может завершиться ошибкой: upstream PR Node 22 не закончен, а
его исходная матрица использовала старые Xcode/macOS. Такая ошибка будет
результатом исследования, а не основанием объявлять IPA готовым.

## Локальная сборка на macOS

Требуются macOS, Xcode 16.4 и command line tools:

```bash
chmod +x scripts/*.sh
scripts/prepare-node18-runtime.sh
scripts/package-ipa.sh
```

Если `Vendor/NodeMobile.xcframework` уже существует, подготовительный скрипт
откажется его перезаписывать.

## Тест на iPhone

1. Подпишите unsigned IPA через SideStore или AltStore.
2. Установите и откройте приложение.
3. Нажмите «Запустить».
4. В логах должны появиться `ST_CONTROL_READY` и `ST_SERVER_READY`.
5. Версия runtime должна совпасть с собранной.
6. Откройте страницу **внутри приложения**.
7. Проверьте stop/start/restart и занятый порт 8000.
8. Только отдельно проверьте Safari: iOS может сразу приостановить хост.

Без выполнения этих шагов проект нельзя считать проверенным на iOS.

## Безопасность

- оба HTTP-сервера жёстко привязаны к `127.0.0.1`;
- в проекте нет JIT entitlement и фиктивных фоновых режимов;
- API-ключи отсутствуют;
- GitHub API используется без авторизации;
- runtime и исходники загружаются только с официальных репозиториев;
- архив NodeMobile 18 проверяется закреплённым SHA-256;
- упаковщик SillyTavern не запускает загруженные `.sh`/`.bat`;
- npm lifecycle scripts в упаковщике отключены.

## Известные ограничения

- запуск в Safari ненадёжен из-за suspension хост-приложения;
- Node runtime запускается один раз за жизненный цикл приложения;
- stop/restart относятся к HTTP-серверу внутри работающего runtime;
- менеджер установки обновлений намеренно отключён до проверки Node 22;
- резервное копирование и атомарная замена payload ещё не реализованы;
- Node 22.9.0 нельзя использовать как финальный runtime из-за возраста;
- настоящий SillyTavern ещё не прошёл запуск на iPhone.
