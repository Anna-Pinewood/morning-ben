# Morning Ben

Утренний Telegram-бот: короткие истории из интересных фактов, листаются
кнопкой «Дальше ▶». Дизайн: `docs/superpowers/specs/2026-07-19-morning-ben-mvp-design.md`.

Два независимых процесса, связанных только через файловую систему:

- **`bot.py`** — бот-доставка (long polling). Читает готовые `stories/*.json`,
  отдаёт по кнопке, ведёт `state/user_state.json` (позиция) и
  `state/shown_history.json` (лог показанного, антиповтор). Отвечает только
  владелице (`OWNER_CHAT_ID`), остальным молчит. Любой свободный текст
  (не команда и не кнопка) — обратная связь: копится в
  `state/feedback.json` и влияет на следующие генерации.
- **Генератор** — sonnet-агент, который выполняет промпт `generate_stories.md`
  (+ `interests.md`, `examples.md`, `state/shown_history.json`, темы ещё не
  показанных историй и три самых свежих сообщения обратной связи с датами)
  и пишет N новых файлов в `stories/`. Два равнозначных
  входа в одну и ту же логику:
  - воркфлоу **`/generate-stories N`** (`.claude/workflows/generate-stories.js`) —
    из любой Claude Code-сессии в этой папке;
  - скрипт **`./generate.sh N`** — из терминала, headless
    `claude -p --model sonnet`.

## Требования

- **uv** (менеджер Python) — https://docs.astral.sh/uv/getting-started/installation/
  Нужную версию Python (3.12+) uv скачает сам при `uv sync`.
- **Node.js LTS + Claude Code CLI** — только для генератора:
  `npm install -g @anthropic-ai/claude-code`, затем один раз интерактивно
  запустить `claude` и залогиниться (Pro/Max-аккаунт). Токен кешируется,
  дальше headless-запуски работают без интерактива.
- **`.env`** в корне проекта (см. `.env.example`):
  - `TELEGRAM_BOT_TOKEN` — токен от @BotFather
  - `OWNER_CHAT_ID` — telegram chat_id владелицы
- **mcp-pinterest** (картинки в историях) — ставится одной командой:
  `./setup_pinterest.sh`. Клонирует и собирает сервер в `vendor/`
  (не в гите), на Linux дополнительно ставит Chrome в `~/.cache/puppeteer`
  и его библиотеки в `~/chrome-libs` — всё без sudo. Без него генератор
  работает, просто истории будут без картинок.

## Установка и запуск

```bash
cd morning-ben
uv sync                       # создаст .venv и поставит зависимости
cp .env.example .env          # и вписать реальные значения (если ещё нет)

./generate.sh 5               # сгенерировать 5 историй (число — параметр)
uv run bot.py                 # запустить бота (long polling, работает вечно)
```

Проверка: написать боту `/start` с аккаунта владелицы — придёт приветствие
и клавиатура. `/start` нужен только в самом начале (достать клавиатуру);
дальше вся навигация — кнопками, лента бесконечная.

## Работа на сервере: tmux, одна команда

Всё серверное хозяйство поднимается одной командой из папки проекта:

```bash
./start_all.sh
```

Она создаёт tmux-сессию **`morning-ben`** с двумя окнами; каждое обёрнуто
в перезапускающий цикл — упавший процесс сам поднимется через 5 секунд:

| Окно | Что делает | Лог |
|------|-----------|-----|
| 0 `bot` | телеграм-бот, long polling | `logs/bot.log` |
| 1 `watcher` | `watch_stories.sh` — вся генерация: раз в 10 с считает непоказанные истории; меньше `MIN_UNSEEN` (15) — догенерирует `TOPUP_N` (5) через `generate.sh`; кулдаун 10 мин. Очередь сама держится на уровне порога, генерится столько, сколько читается | `logs/watcher.log` + `logs/generate.log` |

Шпаргалка:

```bash
tmux attach -t morning-ben                           # посмотреть; Ctrl-b 0/1 — окна, Ctrl-b d — выйти
tmux kill-session -t morning-ben && ./start_all.sh   # перезапустить всё
```

**Если сервер перезагрузился** — tmux-сессия не восстанавливается сама,
нужно зайти и поднять заново:

```bash
ssh <server>
cd workspace/morning-ben
./start_all.sh
```

Бот подхватывает новые файлы историй на лету — после генерации ничего
перезапускать не нужно.

## Переподнять бота на новом сервере с нуля

Порядок проверен на Ubuntu 22.04, обычный юзер **без sudo**:

```bash
# 1. Код
git clone https://github.com/Anna-Pinewood/morning-ben.git && cd morning-ben

# 2. Python-часть
curl -LsSf https://astral.sh/uv/install.sh | sh   # если uv ещё нет
uv sync

# 3. Node + Claude Code (генератор)
#    через nvm, чтобы без sudo:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
nvm install --lts
npm install -g @anthropic-ai/claude-code
claude   # один раз интерактивно: залогиниться, потом выйти

# 4. Картинки (Pinterest). Ставит vendor/, на Linux — ещё Chrome в
#    ~/.cache/puppeteer и его библиотеки в ~/chrome-libs, всё без sudo:
./setup_pinterest.sh
./check_pinterest.sh          # должен напечатать "OK: ... 3 ссылок"

# 5. Секреты
cp .env.example .env          # вписать TELEGRAM_BOT_TOKEN и OWNER_CHAT_ID

# 6. Запуск
./generate.sh 5               # первая пачка историй (~10-20 мин с картинками)
./start_all.sh                # tmux: бот + вотчер
```

Грабли, на которые уже наступали:
- **Бот должен быть один**: long polling конфликтует — прежде чем поднимать
  на новом сервере, погасить старого (`tmux kill-session -t morning-ben`
  на старом сервере).
- В неинтерактивном ssh `claude`/`node` не в PATH — `start_all.sh` сам
  сорсит nvm, а вот при ручных вызовах `generate.sh` по ssh нужно
  `. ~/.nvm/nvm.sh` сначала.
- **Не перезапускать бота через `pkill -f bot.py`** — это убивает весь
  tmux-сервер вместе с вотчером. Только
  `tmux kill-session -t morning-ben && ./start_all.sh`.
- `state/` и `stories/` не в гите: на новом сервере бот стартует с чистой
  очередью. Если нужно перенести накопленное — скопировать эти папки со
  старого сервера руками (rsync/scp), пока боты погашены.

## Картинки: как устроено и как чинить

Цепочка (обрыв в любом звене = истории без картинок, но всё остальное
работает — картинки задизайнены как «приправа», их отсутствие не ошибка):

```
generate.sh
  └─ claude -p --mcp-config .mcp.json --strict-mcp-config
       └─ node vendor/mcp-pinterest/dist/pinterest-mcp-server.js   (MCP, stdio)
            └─ headless Chrome → скрапит pinterest.com/search
                 → ссылки i.pinimg.com → соннет кладёт их в JSON истории
stories/*.json: {"type": "image", "url": "https://i.pinimg.com/736x/..."}
  └─ bot.py: reply_photo(url) — телеграм сам скачивает по URL;
     не смог — молча пропустил и показал следующее сообщение
```

Правила для генератора — раздел «Картинки (Pinterest)» в
`generate_stories.md`: зрелищные темы — до 5 «вайбовых» картинок по
английским запросам («norway aesthetic»), научпоп — до 2 схем
(«... diagram»); не подряд, не первым/последним сообщением;
`/originals/` → `/736x/` (originals в ~5-20% отдаёт 403, 736x живой всегда).

**Отладка — сверху вниз:**

1. `./check_pinterest.sh` — прогоняет всю нижнюю половину цепочки
   (сервер → Chrome → Pinterest → ссылки) с теми же env, что generate.sh.
   - Печатает `OK … 3 ссылок` → низ цепочки жив, проблема в верхней
     половине: смотреть `logs/generate.log` (что соннет ответил про
     картинки) и `logs/bot.log` (`grep 'Картинка не отправилась'`).
   - `FAIL: vendor не собран` → `./setup_pinterest.sh`.
   - `FAIL: Chrome не запускается` → `ldd <путь_к_chrome> | grep "not found"`
     покажет недостающие библиотеки; добавить их пакеты в список в
     `setup_pinterest.sh` и перезапустить его (мы это уже проходили:
     докачивались libxcb-randr0 и libxi6).
   - `FAIL: … пусто дважды` → капча или блок VPS-IP со стороны Pinterest
     (проверить тот же запрос локально с домашнего IP; лечится
     `export MCP_PINTEREST_PROXY_SERVER=http://…` перед generate.sh),
     либо Pinterest сменил вёрстку — тогда смотреть
     `vendor/mcp-pinterest/dist/pinterest-scraper.js` (селектор
     `img[src*=pinimg.com]`).
   - `ВНИМАНИЕ, не-JSON в stdout` → патчи слетели (обновили вендора?) —
     перезапустить `./setup_pinterest.sh`, он патчит идемпотентно.
2. Знать про особенности:
   - **Первый поиск после старта сервера бывает «холостым»** (0 результатов
     без ошибки) — это норма, в промпте и в check-скрипте заложен повтор.
   - Ошибок сервер почти никогда не кидает: любая беда выглядит как
     «Found 0 images» («тихий ноль»).
   - Один поиск ~11-25 с; генерация истории с картинками ~2-4 мин — это
     ожидаемо, не зависание.
3. Апстрим `terryso/mcp-pinterest` закреплён на коммите (см. `PIN_COMMIT`
   в `setup_pinterest.sh`) и патчится в двух местах: путь к Chrome из
   `$MCP_PINTEREST_CHROME_PATH` (иначе только `/usr/bin/google-chrome`) и
   `console.log → console.error` (иначе мусор в JSON-RPC stdout). Обновляя
   пин — перечитать оба патча.

## Как устроены данные

- `stories/*.json` — истории **копятся**, старые не удаляются. Формат:
  `{"id", "topic", "generated_at", "messages": [...]}`. Элемент `messages` —
  либо строка (текст), либо `{"type": "image", "url": ...}` — картинка с
  Pinterest, одно нажатие «Дальше ▶» = одна картинка. Мёртвую ссылку бот
  молча пропускает и показывает следующее сообщение. Битые файлы бот
  пропускает и логирует.
- Очередь строится на лету: всё из `stories/`, чего нет в
  `shown_history.json`. Свежие (`generated_at`) — первыми, старые — в конце.
- Дочитала очередь — бот говорит «истории закончились»; следующее нажатие
  «Дальше ▶» снова проверит диск и отдаст новое, если появилось.
- `state/shown_history.json` — антиповтор и лёгкий фидбек
  (`completed: false` при малом `messages_seen` = «тема не зашла»);
  генератор читает его при каждом прогоне.
- `state/feedback.json` — обратная связь: каждое свободное сообщение боту
  копится как `{"date", "text"}`; в промпт генератора идут только три
  самых свежих (свежие важнее старых). Писать можно что угодно: какие
  темы хочется чаще, что не понравилось в историях, пожелания к тону.
- Логи: `logs/bot.log`, `logs/generate.log`.
