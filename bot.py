"""Morning Ben — Telegram-бот доставки утренних историй (компонент А).

Читает готовые истории из stories/*.json, отдаёт их по кнопке «Дальше ▶»,
ведёт state/user_state.json (позиция) и state/shown_history.json (лог
показанного, антиповтор). Очередь строится на лету: все валидные файлы
в stories/, которых ещё нет в shown_history, свежие — первыми.
"""

import html
import json
import logging
import os
import re
import tempfile
from datetime import date
from pathlib import Path

from dotenv import load_dotenv
from telegram import ReplyKeyboardMarkup, Update
from telegram.error import BadRequest
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

BASE_DIR = Path(__file__).resolve().parent
STORIES_DIR = BASE_DIR / "stories"
STATE_DIR = BASE_DIR / "state"
LOGS_DIR = BASE_DIR / "logs"
USER_STATE_FILE = STATE_DIR / "user_state.json"
SHOWN_HISTORY_FILE = STATE_DIR / "shown_history.json"

BTN_NEXT = "Дальше ▶"
BTN_SKIP = "Следующая история ⏭"
DIVIDER = "✨ на сегодня всё по этой теме"
QUEUE_EMPTY = "Истории на сегодня закончились, увидимся позже 🌙"
GREETING = "Доброе утро! ☀️ Жми «Дальше ▶» — полистаем."

KEYBOARD = ReplyKeyboardMarkup(
    [[BTN_NEXT, BTN_SKIP]], resize_keyboard=True, is_persistent=True
)

logger = logging.getLogger("morning-ben")


# --- файловое состояние -----------------------------------------------------


def _read_json(path: Path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default
    except (json.JSONDecodeError, OSError):
        logger.warning("Не смог прочитать %s, использую default", path)
        return default


def _write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def read_user_state() -> dict:
    state = _read_json(USER_STATE_FILE, {})
    if not isinstance(state, dict):
        state = {}
    return {
        "current_story_id": state.get("current_story_id"),
        "current_message_index": state.get("current_message_index", 0),
    }


def write_user_state(story_id: str | None, message_index: int) -> None:
    _write_json(
        USER_STATE_FILE,
        {"current_story_id": story_id, "current_message_index": message_index},
    )


def read_shown_history() -> list:
    history = _read_json(SHOWN_HISTORY_FILE, [])
    return history if isinstance(history, list) else []


def shown_ids() -> set[str]:
    return {e["id"] for e in read_shown_history() if isinstance(e, dict) and "id" in e}


def log_shown(story: dict, messages_seen: int, completed: bool) -> None:
    history = read_shown_history()
    history.append(
        {
            "id": story["id"],
            "topic": story.get("topic", ""),
            "date": date.today().isoformat(),
            "messages_seen": messages_seen,
            "completed": completed,
        }
    )
    _write_json(SHOWN_HISTORY_FILE, history)


# --- истории ----------------------------------------------------------------


def _valid_story(data) -> bool:
    return (
        isinstance(data, dict)
        and isinstance(data.get("id"), str)
        and data["id"]
        and isinstance(data.get("messages"), list)
        and len(data["messages"]) > 0
        and all(isinstance(m, str) and m.strip() for m in data["messages"])
    )


def load_stories() -> dict[str, dict]:
    """Все валидные истории с диска: id -> story (+ _mtime для сортировки)."""
    stories: dict[str, dict] = {}
    if not STORIES_DIR.is_dir():
        return stories
    for path in STORIES_DIR.glob("*.json"):
        data = _read_json(path, None)
        if not _valid_story(data):
            logger.warning("Пропускаю битый файл истории: %s", path.name)
            continue
        data["_mtime"] = path.stat().st_mtime
        stories[data["id"]] = data
    return stories


def pick_next(exclude: set[str]) -> dict | None:
    """Самая свежая непоказанная история: generated_at по убыванию, старые — в конце."""
    candidates = [s for s in load_stories().values() if s["id"] not in exclude]
    if not candidates:
        return None
    candidates.sort(
        key=lambda s: (str(s.get("generated_at", "")), s["_mtime"]), reverse=True
    )
    return candidates[0]


def resolve_current(state: dict) -> dict | None:
    """Текущая история из state, если она всё ещё валидна и не дочитана."""
    story_id = state.get("current_story_id")
    if not story_id or story_id in shown_ids():
        return None
    story = load_stories().get(story_id)
    if story is None or state["current_message_index"] >= len(story["messages"]):
        return None
    return story


# --- разметка ---------------------------------------------------------------


def to_html(text: str) -> str:
    """Telegram-markdown генератора (**жирный**, _курсив_) -> HTML."""
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text, flags=re.S)
    text = re.sub(r"__(.+?)__", r"<i>\1</i>", text, flags=re.S)
    text = re.sub(r"(?<![\w_])_([^_\n]+)_(?![\w_])", r"<i>\1</i>", text)
    text = re.sub(r"`([^`\n]+)`", r"<code>\1</code>", text)
    return text


async def send(update: Update, text: str, formatted: bool = True, **kwargs) -> None:
    if not formatted:
        await update.message.reply_text(text, **kwargs)
        return
    try:
        await update.message.reply_text(text=to_html(text), parse_mode="HTML", **kwargs)
    except BadRequest:
        logger.warning("HTML-разметка не прошла, шлю как есть: %r", text[:80])
        await update.message.reply_text(text, **kwargs)


# --- механика ---------------------------------------------------------------


async def advance_to_next_story(update: Update) -> None:
    """Пересканировать очередь и переключиться; если пусто — сказать об этом."""
    nxt = pick_next(shown_ids())
    if nxt is None:
        write_user_state(None, 0)
        await send(update, QUEUE_EMPTY, formatted=False)
    else:
        write_user_state(nxt["id"], 0)


async def on_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    state = read_user_state()
    story = resolve_current(state)
    if story is None:
        story = pick_next(shown_ids())
        write_user_state(story["id"] if story else None, 0)
    if story is None:
        await send(update, QUEUE_EMPTY, formatted=False, reply_markup=KEYBOARD)
    else:
        await send(update, GREETING, formatted=False, reply_markup=KEYBOARD)


async def on_next(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    state = read_user_state()
    story = resolve_current(state)
    if story is None:
        story = pick_next(shown_ids())
        if story is None:
            write_user_state(None, 0)
            await send(update, QUEUE_EMPTY, formatted=False)
            return
        state = {"current_story_id": story["id"], "current_message_index": 0}

    idx = state["current_message_index"]
    await send(update, story["messages"][idx])
    idx += 1
    write_user_state(story["id"], idx)

    if idx >= len(story["messages"]):
        log_shown(story, messages_seen=idx, completed=True)
        await send(update, DIVIDER, formatted=False)
        await advance_to_next_story(update)


async def on_skip(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    state = read_user_state()
    story = resolve_current(state)
    if story is not None:
        log_shown(story, messages_seen=state["current_message_index"], completed=False)
        await send(update, DIVIDER, formatted=False)
        await advance_to_next_story(update)
    else:
        # Текущей истории нет — ведём себя как «Дальше»: подхватить и показать.
        await on_next(update, context)


def main() -> None:
    load_dotenv(BASE_DIR / ".env")
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    owner_chat_id = os.environ.get("OWNER_CHAT_ID")
    if not token or not owner_chat_id:
        raise SystemExit("TELEGRAM_BOT_TOKEN и OWNER_CHAT_ID должны быть в .env")

    LOGS_DIR.mkdir(exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(LOGS_DIR / "bot.log", encoding="utf-8"),
        ],
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)

    owner = filters.Chat(chat_id=int(owner_chat_id))
    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", on_start, filters=owner))
    app.add_handler(
        MessageHandler(owner & filters.Regex(f"^{re.escape(BTN_NEXT)}$"), on_next)
    )
    app.add_handler(
        MessageHandler(owner & filters.Regex(f"^{re.escape(BTN_SKIP)}$"), on_skip)
    )

    logger.info("Morning Ben запущен, слушаю long polling")
    app.run_polling(allowed_updates=["message"])


if __name__ == "__main__":
    main()
