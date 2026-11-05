# StarReader Native

Нативная iOS-читалка на **SwiftUI**. Проект создаётся отдельно от старого StarReader (Capacitor/WKWebView).

## Принципы

- Нативный интерфейс SwiftUI; никакого WKWebView, HTML, CSS, JavaScript или Capacitor.
- Локальная библиотека, без обязательной регистрации, облака и подписки.
- Отдельный Bundle ID: `dev.starreader.personalreader.native` — Preview устанавливается рядом со старым приложением.
- Импорт резервной копии StarReader Qt Transfer с проверкой манифеста, SHA-256, допустимых путей и ограничений ZIP.
- Исходный ZIP сохраняется в контейнере приложения как дополнительная резервная копия.
- Сборка unsigned IPA выполняется GitHub Actions на macOS; подпись для личной установки выполняется через Sideloadly.

## Текущий этап

**N0 — SwiftUI Preview (начальная реализация):**
- библиотека «Произведение → Том → Глава»;
- импорт ZIP из приложения «Файлы»;
- локальное хранение и сохранение позиции чтения;
- нативное чтение в режиме прокрутки;
- workflow сборки unsigned IPA.

Постраничная пагинация, заметки, закладки, поиск, темы оформления и полное погружение относятся к следующим итерациям. Они не считаются реализованными в этой начальной сборке.

## Сборка

GitHub Actions → **Build unsigned iOS IPA**. После успешного запуска скачай артефакт `StarReaderNative-unsigned-ipa`, распакуй ZIP и установи IPA через Sideloadly.

Для локальной генерации проекта на Mac:

```bash
brew install xcodegen
xcodegen generate --spec project.yml
xcodebuild -resolvePackageDependencies -project StarReaderNative.xcodeproj -scheme StarReaderNative
```

## Формат переноса

Ожидается ZIP формата `starreader-qt-library-transfer`, schema 1:
- `starreader-library-manifest.json`;
- `data/qt_library.json` (schema 2);
- `data/preview_state.json` (schema 1);
- `originals/*.docx` (если присутствуют в библиотеке).

Неизвестные поля JSON сохраняются без переписывания при импорте. Перед заменой текущей библиотеки приложение показывает сводку и требует подтверждения.
