#!/usr/bin/env bash
# Morning Ben — вотчер очереди: каждые 10 секунд считает непоказанные
# истории (stories/*.json минус shown_history) и, если их меньше порога,
# запускает генерацию. Кулдаун защищает от цикла перезапусков, если
# генерация падает.
#
# Переменные окружения:
#   MIN_UNSEEN — порог (default 2): триггер, когда непоказанных меньше
#   TOPUP_N    — сколько историй догенерировать за раз (default 5)
set -euo pipefail
cd "$(dirname "$0")"

MIN_UNSEEN="${MIN_UNSEEN:-2}"
TOPUP_N="${TOPUP_N:-5}"
COOLDOWN=600
last_run=0

echo "$(date -Iseconds) вотчер запущен: порог=$MIN_UNSEEN, пополнение=$TOPUP_N"

count_unseen() {
  python3 - <<'PY'
import json, glob
try:
    shown = {e.get("id") for e in json.load(open("state/shown_history.json"))}
except Exception:
    shown = set()
n = 0
for p in glob.glob("stories/*.json"):
    try:
        d = json.load(open(p))
        if d.get("id") and d["id"] not in shown and d.get("messages"):
            n += 1
    except Exception:
        pass
print(n)
PY
}

while true; do
  unseen="$(count_unseen)"
  now="$(date +%s)"
  if [ "$unseen" -lt "$MIN_UNSEEN" ] && [ $((now - last_run)) -ge "$COOLDOWN" ]; then
    echo "$(date -Iseconds) непоказанных: $unseen < $MIN_UNSEEN — запускаю generate.sh $TOPUP_N"
    ./generate.sh "$TOPUP_N" || echo "$(date -Iseconds) generate.sh упал (см. logs/generate.log)"
    last_run="$(date +%s)"
    echo "$(date -Iseconds) пополнение завершено, непоказанных теперь: $(count_unseen)"
  fi
  sleep 10
done
