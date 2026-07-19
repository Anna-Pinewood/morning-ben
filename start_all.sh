#!/usr/bin/env bash
# Morning Ben — поднять всё одной командой (например, после перезагрузки
# сервера). Создаёт tmux-сессию morning-ben с двумя окнами:
#   0 bot     — телеграм-бот (uv run bot.py)
#   1 watcher — генерация: держит очередь непоказанных не ниже порога
# Каждое окно обёрнуто в перезапускающий цикл — упавший процесс поднимется
# сам через 5 секунд.
set -euo pipefail
cd "$(dirname "$0")"

# claude лежит в nvm, uv — в ~/.local/bin
[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"

SESSION=morning-ben
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Сессия уже запущена. Посмотреть: tmux attach -t $SESSION"
  echo "Перезапустить всё: tmux kill-session -t $SESSION && ./start_all.sh"
  exit 0
fi

mkdir -p logs
tmux new-session  -d -s "$SESSION" -n bot \
  "while true; do uv run bot.py; echo 'бот упал, перезапуск через 5с'; sleep 5; done"
tmux new-window -t "$SESSION" -n watcher \
  "while true; do ./watch_stories.sh 2>&1 | tee -a logs/watcher.log; sleep 5; done"

echo "Запущено. Окна: tmux attach -t $SESSION (Ctrl-b 0/1 — окна, Ctrl-b d — выйти)"
