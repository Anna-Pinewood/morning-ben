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
"

echo "=== $(date -Iseconds) generate run start (N=$N) ===" >> logs/generate.log
set +e
claude -p "$PROMPT" \
  --model sonnet \
  --dangerously-skip-permissions \
  >> logs/generate.log 2>&1
rc=$?
set -e
echo "=== $(date -Iseconds) generate run end (exit $rc) ===" >> logs/generate.log
exit $rc
