#!/usr/bin/env bash
# Morning Ben — ночной прогон: вечный цикл, каждый день в 21:03 по Москве
# генерирует N историй (default 20). Живёт в tmux-окне, не в cron.
set -euo pipefail
cd "$(dirname "$0")"
N="${1:-20}"

while true; do
  now="$(date +%s)"
  target="$(TZ=Europe/Moscow date -d "21:03" +%s)"
  if [ "$target" -le "$now" ]; then
    target="$(TZ=Europe/Moscow date -d "tomorrow 21:03" +%s)"
  fi
  echo "$(date -Iseconds) следующий прогон: $(TZ=Europe/Moscow date -d "@$target" '+%Y-%m-%d %H:%M мск'), сплю $((target - now)) с"
  sleep $((target - now))
  echo "$(date -Iseconds) ночной прогон: generate.sh $N"
  ./generate.sh "$N" || echo "$(date -Iseconds) generate.sh упал (см. logs/generate.log)"
done
