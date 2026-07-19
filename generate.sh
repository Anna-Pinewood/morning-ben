#!/usr/bin/env bash
# Morning Ben — генератор историй (компонент Б-simple).
#
# Использование: ./generate.sh [N]
#   N — сколько историй сгенерировать за прогон (по умолчанию 5).
#
# Собирает промпт из generate_stories.md + interests.md + examples.md +
# state/shown_history.json и зовёт headless Claude Code (sonnet), который
# пишет N файлов stories/*.json. Старые истории не трогаются — они копятся,
# антиповтор идёт через shown_history и темы ещё не показанных историй.
# Лог — logs/generate.log. Запускается руками или по cron.
set -euo pipefail
cd "$(dirname "$0")"

N="${1:-5}"
case "$N" in
  ''|*[!0-9]*) echo "Использование: $0 [N] — N должно быть числом" >&2; exit 2 ;;
esac

mkdir -p stories state logs
[ -f state/shown_history.json ] || echo "[]" > state/shown_history.json

# Pinterest MCP (картинки в историях): на Linux у Chrome нестандартный путь
# и библиотеки в userspace (см. setup_pinterest.sh) — прокидываем через env,
# они дойдут до Chrome сквозь claude → MCP-сервер → puppeteer.
PINTEREST_MCP_ARGS=()
if [ -f vendor/mcp-pinterest/dist/pinterest-mcp-server.js ]; then
  PINTEREST_MCP_ARGS=(--mcp-config .mcp.json --strict-mcp-config)
  if [ "$(uname)" = "Linux" ]; then
    CHROME_BIN="$(ls -d "$HOME"/.cache/puppeteer/chrome/*/chrome-linux64/chrome 2>/dev/null | head -1 || true)"
    [ -n "$CHROME_BIN" ] && export MCP_PINTEREST_CHROME_PATH="$CHROME_BIN"
    [ -d "$HOME/chrome-libs" ] && export LD_LIBRARY_PATH="$HOME/chrome-libs/usr/lib/x86_64-linux-gnu:$HOME/chrome-libs/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
else
  echo "ВНИМАНИЕ: vendor/mcp-pinterest не собран (./setup_pinterest.sh) — истории будут без картинок" >&2
fi

# Темы историй, которые уже лежат в очереди, но ещё не показаны —
# их тоже нельзя повторять, иначе подряд выпадут две истории об одном.
PENDING_TOPICS="$(python3 - <<'PYEOF'
import glob, json
try:
    shown = {e.get("id") for e in json.load(open("state/shown_history.json"))}
except Exception:
    shown = set()
for p in sorted(glob.glob("stories/*.json")):
    try:
        d = json.load(open(p))
        if d.get("id") not in shown and d.get("topic"):
            print("- " + d["topic"])
    except Exception:
        pass
PYEOF
)"
[ -n "$PENDING_TOPICS" ] || PENDING_TOPICS="(пока нет)"

# Обратная связь: свободные сообщения Ольги боту (state/feedback.json).
# В промпт идут только три самых свежих, с датами.
FEEDBACK="$(python3 - <<'PYEOF'
import json
try:
    entries = json.load(open("state/feedback.json"))
except Exception:
    entries = []
if isinstance(entries, list):
    for e in entries[-3:][::-1]:
        if isinstance(e, dict) and e.get("text"):
            print(f"- [{e.get('date', '?')}] {e['text']}")
PYEOF
)"
[ -n "$FEEDBACK" ] || FEEDBACK="(пока нет)"

PROMPT="$(sed "s/{{N_STORIES}}/$N/g" generate_stories.md)

---

Ниже — содержимое файлов, на которые ссылается промпт выше. Читать их с
диска не нужно, всё уже здесь. Твоя задача — только записать ровно $N
готовых JSON-файлов в директорию stories/.

## interests.md

$(cat interests.md)

## examples.md

$(cat examples.md)

## state/shown_history.json

\`\`\`json
$(cat state/shown_history.json)
\`\`\`

## Темы уже сгенерированных, но ещё не показанных историй

Эти истории уже ждут в очереди — их темы не повторяй так же, как и темы
из shown_history:

$PENDING_TOPICS

## Обратная связь от Ольги

Её сообщения боту про то, какие истории она хочет видеть (свежие первыми,
свежие важнее старых). Применяй по правилам из раздела «Как понимать
обратную связь»: тематические пожелания сдвигают пропорции (больше, но не
вся пачка), стилевые — действуют на все истории:

$FEEDBACK
"

echo "=== $(date -Iseconds) generate run start (N=$N) ===" >> logs/generate.log
set +e
claude -p "$PROMPT" \
  --model sonnet \
  --dangerously-skip-permissions \
  ${PINTEREST_MCP_ARGS+"${PINTEREST_MCP_ARGS[@]}"} \
  >> logs/generate.log 2>&1
rc=$?
set -e
echo "=== $(date -Iseconds) generate run end (exit $rc) ===" >> logs/generate.log
exit $rc
