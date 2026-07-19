# Morning Ben

Утренний Telegram-бот: короткие истории из интересных фактов, листаются
кнопкой «Дальше ▶». Дизайн: `docs/superpowers/specs/2026-07-19-morning-ben-mvp-design.md`.

Два независимых процесса, связанных только через файловую систему:

- **`bot.py`** — бот-доставка (long polling). Читает готовые `stories/*.json`,
  отдаёт по кнопке, ведёт `state/user_state.json` (позиция) и
  `state/shown_history.json` (лог показанного, антиповтор). Отвечает только
  владелице (`OWNER_CHAT_ID`), остальным молчит.
- **Генератор** — sonnet-агент, который выполняет промпт `generate_stories.md`
  (+ `interests.md`, `examples.md`, `state/shown_history.json` и темы ещё не
  показанных историй) и пишет N новых файлов в `stories/`. Два равнозначных
  входа в одну и ту же логику:
  - воркфлоу **`/generate-stories N`** (`.claude/workflows/generate-stories.js`) —
    из любой Claude Code-сессии в этой папке; после генерации отдельный агент
    валидирует схему всех файлов;
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

## Постоянная работа бота на сервере

Бот — systemd unit (автоперезапуск; state переживает рестарты):

```ini
# /etc/systemd/system/morning-ben.service
[Unit]
Description=Morning Ben telegram bot
After=network-online.target

[Service]
WorkingDirectory=/path/to/morning-ben
ExecStart=/usr/local/bin/uv run bot.py
Restart=always
RestartSec=5
User=<user>

[Install]
WantedBy=multi-user.target
```

## Регулярная генерация

Бот подхватывает новые файлы на лету, без рестарта — частота генерации
может быть любой. Планировщик — внутри Claude, не OS-cron:

- **Локально (Claude Desktop):** Routines → New routine → Local, папка
  проекта, расписание Daily, инструкция:
  «Запусти воркфлоу generate-stories с args 5».
- **Headless-сервер:** таймер (systemd timer) дёргает
  `claude -p "Запусти воркфлоу generate-stories с args 5" --dangerously-skip-permissions`
  из папки проекта, либо просто `./generate.sh 5` — результат одинаковый.

## Как устроены данные

- `stories/*.json` — истории **копятся**, старые не удаляются. Формат:
  `{"id", "topic", "generated_at", "messages": [...]}`. Битые файлы бот
  пропускает и логирует.
- Очередь строится на лету: всё из `stories/`, чего нет в
  `shown_history.json`. Свежие (`generated_at`) — первыми, старые — в конце.
- Дочитала очередь — бот говорит «истории закончились»; следующее нажатие
  «Дальше ▶» снова проверит диск и отдаст новое, если появилось.
- `state/shown_history.json` — антиповтор и лёгкий фидбек
  (`completed: false` при малом `messages_seen` = «тема не зашла»);
  генератор читает его при каждом прогоне.
- Логи: `logs/bot.log`, `logs/generate.log`.
