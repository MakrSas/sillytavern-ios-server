# SillyTavern Server для iOS — технический прототип

Запланированные функции, включая импорт данных, файловый менеджер и две
Live Activities, описаны в [`docs/ROADMAP.md`](docs/ROADMAP.md).

Экспериментальное SwiftUI-приложение, которое встраивает Node.js через
NodeMobile и запускает настоящий HTTP-сервер только на `127.0.0.1`.

> Текущий статус: **Stage 3 / экспериментальная интеграция SillyTavern**.
> NodeMobile 22.9.0 и localhost уже подтверждены на физическом iPhone.
> Workflow включает официальный SillyTavern 1.18.0, однако новая Stage 3 IPA
> ещё должна пройти отдельный device-тест и не считается готовым релизом.

## Что уже реализовано

- полноценный Xcode-проект и общая схема сборки;
- SwiftUI-интерфейс со статусами «Не запущен», «Запускается», «Работает»,
  «Останавливается» и «Ошибка»;
- Objective-C++ мост к настоящему `node_start()`;
- захват `stdout` и `stderr`;
- настоящий SillyTavern 1.18.0 в отдельном Node Worker на `127.0.0.1`;
- автоматический выбор следующего свободного порта, если желаемый занят;
- `health`, запуск, остановка и перезапуск Worker с сервером SillyTavern;
- встроенный `WKWebView`, при котором приложение остаётся на переднем плане;
- экспериментальная кнопка Safari с обязательным предупреждением;
- sandbox-каталоги `Runtime`, `UserData`, `Updates`, `Backups` и `Logs`;
- сохранение и ограничение размера лога;
- проверка последнего официального релиза SillyTavern через GitHub API;
- проверяемая загрузка официального NodeMobile 18.20.4;
- отдельная GitHub Actions-сборка экспериментального NodeMobile 22.9.0;
- патчи host-инструментов и актуального набора статических библиотек Node 22
  для сборки iOS framework;
- упаковщик официального исходного архива SillyTavern без выполнения его
  shell-скриптов и без npm lifecycle scripts;
- предварительная компиляция frontend-библиотеки SillyTavern в доверенном CI;
- JS-кодеки PNG/JPEG и переносимый приблизительный токенизатор для режима
  iOS без WebAssembly;
- unsigned IPA, предназначенный для последующей подписи SideStore/AltStore.

## Профиль совместимости Stage 3

На 24 июля 2026 года:

- SillyTavern `1.18.0` требует Node.js `>= 20`;
- используемый мобильный порт Node основан на `22.9.0`;
- V8 запускается с `--jitless`, поэтому глобальный WebAssembly отсутствует;
- встроенный Undici заменён для запросов SillyTavern на `node-fetch`;
- Webpack выполняется в CI, а не на iPhone;
- PNG/JPEG/BMP/GIF/TIFF используют JS-кодеки;
- серверная обработка WebP и AVIF временно недоступна;
- tiktoken заменён обратимым байтовым токенизатором: его подсчёт приблизительный
  и не равен точным model token IDs;
- функции Transformers/ONNX, которым требуется WASM, пока не поддерживаются.

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
    └── nodejs-project/
        ├── main.js                 control server и Worker lifecycle
        ├── sillytavern-worker.cjs  совместимый bootstrap
        └── SillyTavern/            создаётся доверенным CI, в Git не хранится

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
6. проверит `otool -L` и наличие встроенного `NodeMobile.framework`;
7. соберёт unsigned `SillyTavernServer-unsigned.ipa`;
8. повторно проверит framework уже внутри IPA.

Node 18 используется только для проверки механизма встраивания. Он не подходит
для актуального SillyTavern.

### 2. Stage 3: Node 22 и SillyTavern 1.18.0

Вручную запустите workflow **Build experimental Node 22 and IPA**.

Он восстанавливает кэшированный `iphoneos-arm64` runtime, подготавливает
закреплённый официальный SillyTavern 1.18.0, применяет проверяемый
iOS-compatibility patch, компилирует frontend в CI и создаёт unsigned IPA.
Перед Xcode-сборкой выполняются отдельные jitless-тесты HTTP-клиента,
PNG/JPEG-кодеков и полный тест `health → stop → start → restart`.
Симулятор намеренно не входит в этот экспериментальный workflow: для
LiveContainer он не нужен, а полная сборка Node/V8 для второй архитектуры
удваивает время и расход диска.

NodeMobile закреплён на коммите
`106c51f95d55d1010de56a2ffd09bfb4ba819a47`, а официальный SillyTavern 1.18.0 —
на коммите `51ad27fb86d39a3daca3adaa970375c9670c12df` и SHA-256 исходного архива.
Workflow не следует за изменяемыми ветками и поэтому не начинает выполнять
новый код без ревью.

Node runtime и подготовленный payload имеют независимые cache keys. Изменение
Swift/JS-приложения не вызывает повторную часовую компиляцию Node.

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
6. Откройте страницу **внутри приложения** и убедитесь, что загрузился
   интерфейс SillyTavern, а не техническая smoke-page.
7. Проверьте stop/start/restart и занятый порт 8000.
8. Только отдельно проверьте Safari: iOS может сразу приостановить хост.

Без выполнения этих шагов проект нельзя считать проверенным на iOS.

Первый успешный запуск NodeMobile 18.20.4 на физическом iPhone зафиксирован в
[`docs/DEVICE_TEST_RESULT_2026-07-23.md`](docs/DEVICE_TEST_RESULT_2026-07-23.md).
Он подтвердил localhost HTTP, но также подтвердил отключённый WebAssembly.
Успешный Node 22 device-gate зафиксирован в
[`docs/DEVICE_TEST_RESULT_2026-07-24.md`](docs/DEVICE_TEST_RESULT_2026-07-24.md).

## Безопасность

- оба HTTP-сервера жёстко привязаны к `127.0.0.1`;
- в проекте нет JIT entitlement и фиктивных фоновых режимов;
- API-ключи отсутствуют;
- GitHub API используется без авторизации;
- runtime и исходники загружаются только с официальных репозиториев;
- архив NodeMobile 18 проверяется закреплённым SHA-256;
- архив SillyTavern 1.18.0 проверяется закреплённым SHA-256;
- упаковщик SillyTavern не запускает загруженные `.sh`/`.bat`;
- npm lifecycle scripts в упаковщике отключены.

## Известные ограничения

- запуск в Safari ненадёжен из-за suspension хост-приложения;
- Node runtime запускается один раз за жизненный цикл приложения;
- stop/restart пересоздают Worker SillyTavern внутри работающего runtime;
- менеджер установки обновлений намеренно отключён до device-теста Stage 3;
- резервное копирование и атомарная замена payload ещё не реализованы;
- Node 22.9.0 нельзя использовать как финальный runtime из-за возраста;
- WASM-функции Transformers/ONNX, WebP и AVIF пока недоступны;
- встроенный токенизатор даёт приблизительный, а не модельно-точный подсчёт;
- настоящий SillyTavern ещё не прошёл запуск на iPhone.
