#!/usr/bin/env bash
# Morning Ben — установка mcp-pinterest (поиск картинок для историй).
#
# Клонирует terryso/mcp-pinterest в vendor/ (закреплённый коммит), патчит:
#   1) путь к Chrome можно задать через $MCP_PINTEREST_CHROME_PATH
#      (иначе на Linux он захардкожен как /usr/bin/google-chrome);
#   2) console.log → console.error в MCP-сервере (иначе мусор в stdout
#      ломает JSON-RPC канал строгим клиентам);
# и собирает. На Linux дополнительно: Chrome в userspace через
# @puppeteer/browsers и недостающие системные библиотеки распаковкой
# deb-пакетов в ~/chrome-libs (sudo не нужен). Идемпотентен.
set -euo pipefail
cd "$(dirname "$0")"

REPO="https://github.com/terryso/mcp-pinterest"
PIN_COMMIT="b2b1b3961910ea454dbb161535d31583fc98b599"
DIR="vendor/mcp-pinterest"

# --- клон + патчи + сборка --------------------------------------------------

if [ ! -d "$DIR/.git" ]; then
  mkdir -p vendor
  git clone "$REPO" "$DIR"
fi
git -C "$DIR" checkout -q "$PIN_COMMIT"

# Патч 1: env-переопределение пути к Chrome (в начало getChromePath).
if ! grep -q MCP_PINTEREST_CHROME_PATH "$DIR/pinterest-scraper.js"; then
  perl -0pi -e 's/(getChromePath\(\) \{\n)/$1    if (process.env.MCP_PINTEREST_CHROME_PATH) return process.env.MCP_PINTEREST_CHROME_PATH;\n/' \
    "$DIR/pinterest-scraper.js"
  grep -q MCP_PINTEREST_CHROME_PATH "$DIR/pinterest-scraper.js" \
    || { echo "Патч 1 не применился — проверь vendor/mcp-pinterest/pinterest-scraper.js" >&2; exit 1; }
fi

# Патч 2: stdout сервера — только JSON-RPC, диагностика в stderr.
perl -pi -e 's/console\.log\(/console.error(/g' "$DIR/pinterest-mcp-server.ts"

(cd "$DIR" && npm install --silent && npm run build >/dev/null)
[ -f "$DIR/dist/pinterest-mcp-server.js" ] \
  || { echo "Сборка не дала dist/pinterest-mcp-server.js" >&2; exit 1; }

# --- Linux: Chrome в userspace + библиотеки ---------------------------------

if [ "$(uname)" = "Linux" ]; then
  CHROME="$(ls -d "$HOME"/.cache/puppeteer/chrome/*/chrome-linux64/chrome 2>/dev/null | head -1 || true)"
  if [ -z "$CHROME" ]; then
    echo "Ставлю Chrome в ~/.cache/puppeteer (без sudo)…"
    npx --yes @puppeteer/browsers install chrome@stable >/dev/null
    CHROME="$(ls -d "$HOME"/.cache/puppeteer/chrome/*/chrome-linux64/chrome | head -1)"
  fi

  LIBDIR="$HOME/chrome-libs"
  export LD_LIBRARY_PATH="$LIBDIR/usr/lib/x86_64-linux-gnu:$LIBDIR/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  if ldd "$CHROME" 2>/dev/null | grep -q "not found"; then
    echo "Докачиваю недостающие библиотеки Chrome в $LIBDIR…"
    mkdir -p "$LIBDIR/debs"
    (
      cd "$LIBDIR/debs"
      apt-get download libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
        libcups2 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxrandr2 \
        libgbm1 libxkbcommon0 libpango-1.0-0 libcairo2 libasound2 \
        libatspi2.0-0 libpixman-1-0 libxrender1 libthai0 libharfbuzz0b \
        libfribidi0 libdatrie1 libgraphite2-3 libwayland-server0 \
        libxcb-render0 libxcb-shm0 libfontconfig1 libfreetype6 libpng16-16 \
        libavahi-client3 libavahi-common3 libwayland-client0 \
        libpangocairo-1.0-0 libpangoft2-1.0-0 libxcb-randr0 libxi6 \
        >/dev/null 2>&1 || true
      for d in *.deb; do dpkg -x "$d" "$LIBDIR"; done
    )
    if ldd "$CHROME" 2>/dev/null | grep "not found"; then
      echo "Всё ещё не хватает библиотек (см. выше) — добавь их пакеты в список" >&2
      exit 1
    fi
  fi
  "$CHROME" --version
fi

echo "OK: mcp-pinterest готов ($DIR/dist/pinterest-mcp-server.js)"
