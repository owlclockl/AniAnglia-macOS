# Codex Prompt — AniAnglia for macOS

> Используй этот файл как промпт для ChatGPT Codex, если хочешь продолжить разработку без Devin. Здесь описано всё, что Codex должен знать, чтобы продолжать работу с того места, где она остановилась.

## Кто ты и что делаешь
Ты — senior macOS разработчик. Твоя задача — продолжать развивать неофициальный клиент Anixart для macOS, лежащий в репозитории **`https://github.com/deerbyy/AniAnglia-macOS`** (ветка `main`).

## Что НЕЛЬЗЯ делать
1. Не трогать `https://github.com/deerbyy/Rolea` — это посторонний проект пользователя, ты туда не лезешь.
2. Не трогать `https://github.com/deerbyy/AniAnglia` — это **iOS-версия** приложения, она используется только как **референс** (там Objective-C++ код, ты его не портируешь).
3. **Не использовать `libanixart.xcframework`** — она существует только под iOS-arm64/iOS-simulator, нет macOS-слайса.
4. Не делать Mac Catalyst — пользователь явно отказался от этого варианта.
5. Не делать Objective-C++/UIKit/iOS-specific код. Только Swift / SwiftUI / AppKit (по необходимости).

## Стек, который используется
- **Swift 5.9 + SwiftUI**, минимум **macOS 13 Ventura**.
- **URLSession + Codable + async/await** для сети. Никаких сторонних HTTP-либ.
- **WKWebView** для плееров Kodik/Sibnet/VK/YouTube.
- **Keychain** (Security.framework) для токена.
- **NavigationSplitView** для основной навигации.
- Проект генерируется через **XcodeGen** (`brew install xcodegen && xcodegen generate`). `*.xcodeproj` в гите НЕ лежит — он в `.gitignore`.
- CI: GitHub Actions, runner `macos-14`, билд через `xcodebuild`, упаковка `.dmg` через `hdiutil`. См. `.github/workflows/build-dmg.yml`.

## API Anixart
- Базовый URL: **`https://api.anixart.tv`**
- User-Agent (обязательно): `AnixartApp/9.0 beta-11-25052914 (Android 11; SDK 30; arm64-v8a; samsung; ru_RU)`
- Авторизация: после `POST /auth/signIn` (form: login, password) сервер возвращает `profileToken.token` и `profile.id`. Дальше во **все запросы** добавляй query-параметры `?token=<token>&profile_id=<id>`. Если их нет — сервер вернёт код != 0 на защищённых эндпоинтах, но публичные (поиск, релиз, видео) работают и без авторизации.
- Все ответы имеют поле `code` (0 = ok, != 0 = ошибка). Сообщение в `message`.

### Ключевые эндпоинты, которые уже подключены

| Метод | Путь | Назначение |
|-------|------|-----------|
| GET | `/discover/watching/{page}` | Лента «Сейчас смотрят» |
| GET | `/discover/recommendations/{page}` | Персональные рекомендации |
| GET | `/release/{id}` | Один релиз |
| GET | `/release/random` | Случайный релиз |
| GET | `/video/release/{id}` | Видео-блоки релиза |
| POST | `/search/releases/{page}` | Поиск (form: query, searchBy=0) |
| POST | `/filter/{page}` | Каталог с фильтрами (JSON боди) |
| GET | `/episode/{releaseId}` | Список озвучек (`types`) |
| GET | `/episode/{releaseId}/{typeId}` | Список плееров (`sources`) |
| GET | `/episode/{releaseId}/{typeId}/{sourceId}` | Список серий |
| GET | `/profile/list/all/{profileId}/{cat}/{page}` | Закладки по категории (1–5) |
| GET | `/profile/list/add/{cat}/{releaseId}` | Добавить в категорию |
| GET | `/profile/list/delete/0/{releaseId}` | Убрать из закладок |
| GET | `/profile/{id}` | Профиль пользователя |
| POST | `/auth/signIn` | Авторизация (form: login, password) |
| GET | `/release/comment/all/{releaseId}/{page}?sort=N` | Комменты (sort: 0=новые, 1=старые, 2=топ) |
| GET | `/episode/watch/{releaseId}/{sourceId}/{position}` | Отметить серию просмотренной |
| GET | `/episode/unwatch/{releaseId}/{sourceId}/{position}` | Снять отметку просмотра |
| GET | `/history/{page}` | История просмотров (требует авторизацию) |
| POST | `/release/comment/add/{releaseId}` | Добавить комментарий (JSON: message, is_spoiler, parent_comment_id) |
| GET | `/release/comment/vote/{commentId}/{value}` | Лайк/дизлайк/снять (value: 1, -1, 0) |
| GET | `/release/vote/add/{releaseId}/{stars}` | Оценить релиз (1–5) |
| GET | `/release/vote/delete/{releaseId}` | Убрать оценку |

#### `/filter/{page}` JSON-боди (поля опциональные):
```json
{
  "sort": 3,                  // 0=обновлению, 1=оценка, 2=год, 3=популярность
  "category": 1,              // 1=сериал, 2=фильм, 3=OVA, 4=ONA, 5=спешл
  "status": 1,                // 1=вышел, 2=анонс, 3=онгоинг
  "start_year": 2015,
  "end_year": 2024,
  "country": "Япония",
  "genres": ["экшн", "фэнтези"],
  "is_genres_exclude_mode": false
}
```

### Эндпоинты, которые ещё не подключены, но точно есть
- `/release/comment/replies/{parentId}/{page}` — ответы на комментарий
- `/release/comment/edit/{commentId}` (POST) — редактирование своего комментария
- `/release/comment/delete/{commentId}` — удаление своего
- `/profile/friend/all/{profileId}/{page}`, `/profile/friend/request/...` — друзья
- `/profile/preference/{type}` — настройки уведомлений профиля
- Примечание: API Anixart **не имеет** эндпоинта `/notification/all` — уведомления реализованы только через пуш-уведомления.

Для полного списка (~150 эндпоинтов) можно посмотреть iOS-исходник:
- `https://github.com/deerbyy/AniAnglia/tree/main/AniAnglia/Libraries/aateam/libanixart/include/anixart` — там лежат C++ заголовки с DTO и URL.
- Или через `strings deerbyy/AniAnglia .../libanixart.a | grep '^/'`.

## Что уже сделано (v0.6 — текущий статус)

**Скелет (v0.1):**
- Каркас: SwiftUI, NavigationSplitView, сайдбар.
- API-клиент `AnixartAPI` (`Sources/AniAnglia/Networking/`), публичный `auth: AuthStore`, методы `get/post/postJSON`.
- Модели: `Release`, `Video`, `Profile`, `Episode/EpisodeType/EpisodeSource` (Codable, snake_case → camelCase via `.convertFromSnakeCase`).
- **НЕ добавляй** явные `CodingKey` override для snake_case-полей — стратегия работает против вас (вызывает двойное переименование).
- AuthStore с Keychain.
- CI workflow (`.github/workflows/build-dmg.yml`): **macos-15** (Xcode 16) → xcodegen → xcodebuild Release → hdiutil → `.dmg`.

**Экраны:**
- **Главная**: «Сейчас смотрят» (`/discover/watching/0`) + «Рекомендации» (если авторизован).
- **Каталог** (НОВОЕ): `CatalogView` с фильтрами сортировки/категории/статуса/года. Пагинация через «Показать ещё». POST `/filter/{page}`.
- **Поиск**: debounced, фокус на TextField автоматически (`@FocusState`).
- **Релиз**: постер + метаданные + видео-блоки + кадры. НОВОЕ: кнопки «Смотреть» и выпадающее меню закладок (5 категорий + «Убрать»).
- **Серии** (НОВОЕ): `EpisodesView` — пикер озвучек (`types`), пикер плееров (`sources`), список серий с бейджами «просмотрено». Плеер в sheet через WKWebView, http→https rewrite, схема-лесс URL `//...` обрабатывается.
- **Скриншоты**: полноэкранный просмотрщик с навигацией ←/→.
- **Закладки**: список по категориям (1–5), из экрана релиза добавляем/убираем.
- **Профиль**: статистика + login form.
- **Настройки** (`Cmd+,`): Основные (НОВОЕ: «Очистить кэш» работает — `RemoteImageCache.shared.clear()`), Воспроизведение, О программе.
- **Тулбар** (НОВОЕ): `⚡️ Случайный релиз` (Cmd+Shift+R) и `🔎 Поиск` (Cmd+K — фокус на вкладку с поиском).
- **Иконка** (v0.2): своя иконка (пурпурный градиент + play-треугольник + «A»), все размеры 16—1024 в `Resources/Assets.xcassets/AppIcon.appiconset`.
- **Исправление краша Swift Concurrency (v0.3)**: `async let` + `defer` вызывал фатальный `swift_task_dealloc → asyncLet_finish_after_task_completion`. Рефактор на простой последовательный `try await` в `HomeView.load()` и `ReleaseDetailView.load()`. **НИКОГДА** не используй `async let` вместе с `defer` в @MainActor контексте.
- **Глобальный вход (v0.3)**: `Features/Account/AccountToolbar.swift` — кнопка в тулбаре справа. Когда не вошёл — «Войти» вызывает sheet `LoginSheet`. Когда вошёл — показывает аватар + логин с меню «Открыть профиль / Выйти». Читаемые ошибки логина (code 2/3/4/5).
- **Комментарии (v0.4)**: `Features/Release/CommentsView.swift` встроен в `ReleaseDetailView`. Сортировка топ/новые/старые, ленивая пагинация, раскрытие спойлеров.
- **История просмотров (v0.4)**: новый таб в сайдбаре (`SidebarItem.history`), `Features/History/HistoryView.swift`. Требует авторизацию (`/history/{page}`).
- **Отметка серии просмотренной (v0.4)**: кнопка-галочка в `EpisodeRow`. Оптимистичный апдейт с откатом при ошибке. Авто-пометка при закрытии плеера.
- **Мультиселект жанров (v0.5)**: `Features/Catalog/GenresPickerButton.swift` — popover с чекбоксами на 45 жанров из `Models/AnixartGenres.swift` (извлечены из iOS-источника `LibanixartApi.mm`). Переключатель «Исключить выбранные» (`is_genres_exclude_mode`).
- **Отправка комментариев + лайки (v0.5)**: композер в `CommentsView` с TextEditor и спойлер-флагом. Под каждым комментарием — кнопки thumbs up/down (`/release/comment/vote/{id}/{value}`).
- **Оценка релиза звёздами (v0.5)**: 5 звёзд на `ReleaseDetailView` (только для авторизованных). Тап по той же звезде убирает оценку. `Release.yourVote` добавлен в модель.
- **Фикс сайдбара (v0.6)**: в предыдущей версии кнопки сайдбара не отвечали из-за `Section` + Optional binding. Теперь `List(SidebarItem.allCases, id: \.self, selection: $selection)` — это стабильный паттерн на macOS. **НЕ** используй `.tag(Optional(item))` + `Section` — съедает тапы.
- **Полный экран Профиля (v0.6)**: аватар + логин + статус + дата регистрации + кнопки Обновить/Выйти. Сетка статистики кликабельна. Дальше 5 секций-превью (по всем категориям закладок) — горизонтальный скролл с до 8 карточками плюс кнопка «Все →» переходит на вкладку Закладки с нужной категорией.
- **Централизованный navigationDestination (v0.6)**: `navigationDestination(for: Release.self)` вынесен на коронь NavigationStack в ContentView — из любого вложенного экрана (в т.ч. из Профиля) можно писать `NavigationLink(value: release)`. Дублирующие `navigationDestination(for: Release.self)` из дочерних вью удалены.
- **AppState.selectSidebar / openRelease (v0.6)**: новые helpers для навигации между вкладками с опциями (например «открыть Закладки с категорией 'Brosheno'»).
- **Фикс полноэкранного видео (v0.6.1)**: у WKWebView на macOS HTML5 element fullscreen по умолчанию ВЫКЛЮЧЕН — кнопка «на весь экран» у встроенных плееров (Kodik/Sibnet/VK/YouTube) молча не работала. Исправлено: `config.preferences.isElementFullscreenEnabled = true` в `WebView` (NSViewRepresentable) в `VideoPlayerSheet.swift`. Публичный API с macOS 12.3, таргет 13.0 — доступен без проверки availability. Не удалять эту строку при рефакторинге плеера.
- **Фикс подписки на AuthStore (v0.6.2)**: `AuthStore` — отдельный ObservableObject; чтение `appState.auth.isAuthenticated` через `@EnvironmentObject AppState` НЕ подписывает вью на его изменения — после входа/выхода экраны не перерисовывались («Закладки» оставались на «Нужен вход», в релизе не появлялись звёзды/меню закладок, серии нельзя было отмечать, композер комментариев не показывался). Фикс: в `AniAngliaApp` добавлен `.environmentObject(appState.auth)`, а все экраны, читающие auth в body, получили `@EnvironmentObject private var auth: AuthStore` (Home, Bookmarks, History, Profile, ReleaseDetail, Episodes, Comments). ПРАВИЛО: если вью читает auth в body — используй `@EnvironmentObject var auth: AuthStore`, а не `appState.auth`.
- **Фикс гонок ответов (v0.6.2)**: epoch-guard в `SearchViewModel.performSearch` и `BookmarksViewModel.load` — устаревший ответ больше не перезаписывает свежие результаты. В `CatalogViewModel` страница инкрементируется ТОЛЬКО после успешного ответа (раньше `page += 1` до запроса оставлял дыру в выдаче при ошибке сети), `reload` больше не делит состояние с `loadMore`. Годы в фильтре каталога вычисляются динамически (до текущего года), а не захардкожены.
- **CI (v0.6.2)**: триггеры `push`/`pull_request` расширены паттернами `arena/**`, чтобы PR из arena-веток получали проверку сборки.

## Что НЕ сделано (TODO)
- [ ] Ответы на комментарии (`/release/comment/replies/{id}/{page}`) + редактирование/удаление своих.
- [ ] Друзья и заявки (`/profile/friend/all/...`).
- [ ] Настройки профиля (изменение логина/пароля, аватара).
- [ ] Авто-пагинация в закладках/поиске (сейчас всегда page=0).
- [ ] Настоящая подпись + нотарификация для распространения вне Gatekeeper.
- [ ] Поиск в истории/закладках.

## Как продолжать работу
1. Клонируй: `git clone https://github.com/deerbyy/AniAnglia-macOS.git`
2. `brew install xcodegen` (если ещё нет).
3. `xcodegen generate` → `open AniAnglia.xcodeproj`.
4. Реализуй фичу.
5. Закоммить, запушь в `main` — CI соберёт DMG.
6. **В этом же коммите обнови `CODEX_PROMPT.md`** (этот файл) — раздел «Что уже сделано» / «Что НЕ сделано», чтобы следующий разработчик/Codex/agent знал текущий статус.

## Стиль кода
- camelCase, тип-аннотации только когда не выводятся.
- ViewModel → `@MainActor final class`, `@Published` поля, async-методы.
- Views — `View`, без `body` логики наружу.
- Никаких force-unwrap (`!`) в продакшен-коде кроме компиле-тайм гарантий (URL литералы и т.д.).
- Никаких сторонних SPM-зависимостей без согласования с пользователем.

## Контакт
Пользователь GitHub: **deerbyy** (по-русски обращается на «ты», по-нику — «ПЕ4ЕНЮХА»). Любит лаконичные ответы без воды, ценит когда сразу делается, а не обсуждается.
