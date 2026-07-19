#!/usr/bin/env bash
# Morning Ben — диагностика цепочки картинок (mcp-pinterest).
#
# Запускает MCP-сервер как subprocess (как это делает claude в generate.sh),
# делает один реальный поиск и печатает ссылки. Выставляет те же env, что
# generate.sh. Если здесь работает, а истории без картинок — проблема выше
# по цепочке (промпт/клод), если не работает — ниже (сервер/Chrome/сеть).
#
# Использование: ./check_pinterest.sh ["запрос"]
set -euo pipefail
cd "$(dirname "$0")"

[ -f vendor/mcp-pinterest/dist/pinterest-mcp-server.js ] \
  || { echo "FAIL: vendor не собран — запусти ./setup_pinterest.sh" >&2; exit 1; }

if [ "$(uname)" = "Linux" ]; then
  CHROME_BIN="$(ls -d "$HOME"/.cache/puppeteer/chrome/*/chrome-linux64/chrome 2>/dev/null | head -1 || true)"
  [ -n "$CHROME_BIN" ] && export MCP_PINTEREST_CHROME_PATH="$CHROME_BIN"
  [ -d "$HOME/chrome-libs" ] && export LD_LIBRARY_PATH="$HOME/chrome-libs/usr/lib/x86_64-linux-gnu:$HOME/chrome-libs/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  if [ -n "${CHROME_BIN:-}" ]; then
    "$CHROME_BIN" --version || { echo "FAIL: Chrome не запускается; смотри ldd \"$CHROME_BIN\" | grep 'not found'" >&2; exit 1; }
  else
    echo "FAIL: Chrome не найден в ~/.cache/puppeteer — запусти ./setup_pinterest.sh" >&2; exit 1
  fi
fi

QUERY="${1:-norway aesthetic}" python3 - <<'PY'
import json, os, subprocess, sys

query = os.environ["QUERY"]
proc = subprocess.Popen(
    ["node", "vendor/mcp-pinterest/dist/pinterest-mcp-server.js"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    text=True,
)

def rpc(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()

def read_resp():
    while True:
        line = proc.stdout.readline()
        if not line:
            sys.exit("FAIL: сервер умер; stderr:\n" + proc.stderr.read()[-2000:])
        line = line.strip()
        if not line:
            continue
        try:
            return json.loads(line)
        except json.JSONDecodeError:
            # Не-JSON в stdout: патч 2 из setup_pinterest.sh не применён.
            print("ВНИМАНИЕ, не-JSON в stdout (сломает клод):", line[:100])

rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2024-11-05", "capabilities": {},
    "clientInfo": {"name": "check", "version": "0"}}})
print("initialize:", read_resp()["result"]["serverInfo"])
rpc({"jsonrpc": "2.0", "method": "notifications/initialized"})

links = []
for attempt in (1, 2):  # первый поиск после старта бывает холостым
    rpc({"jsonrpc": "2.0", "id": 1 + attempt, "method": "tools/call", "params": {
        "name": "pinterest_search", "arguments": {"keyword": query, "limit": 3}}})
    texts = [b.get("text", "") for b in read_resp()["result"]["content"]]
    links = [t.split("Link: ", 1)[1] for t in texts if "Link: " in t]
    if links:
        break
    print(f"попытка {attempt}: 0 ссылок" + ("" if attempt == 2 else ", повторяю…"))

proc.terminate()
if not links:
    sys.exit(f"FAIL: '{query}' — пусто дважды. Похоже на капчу/блок IP или "
             "смену вёрстки Pinterest. Прокси: env MCP_PINTEREST_PROXY_SERVER.")
print(f"OK: '{query}' → {len(links)} ссылок")
for u in links:
    print(" ", u.replace("/originals/", "/736x/"))
PY
