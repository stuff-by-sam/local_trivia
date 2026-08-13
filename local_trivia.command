#!/bin/zsh
# TRIVIA launcher (Mac) — double-click to start the server and open the presenter.

cd "$(dirname "$0")" || exit 1

# Make sure node/npm are on PATH regardless of how they were installed
# (installer pkg, Homebrew, or nvm — GUI-launched shells don't source ~/.zshrc).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v npm >/dev/null 2>&1 && [ -s "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME/.nvm/nvm.sh"
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "Node.js is required but was not found."
  echo "Install the LTS version from https://nodejs.org then double-click this again."
  read -s -k '?Press any key to close.'
  exit 1
fi

URL="http://localhost:3000/present"

# If the server is already running, just open the presenter.
if curl -s -o /dev/null --max-time 1 http://localhost:3000/; then
  echo "TRIVIA server is already running — opening the presenter."
  open "$URL"
  exit 0
fi

# First run: install dependencies (needs internet once; offline ever after).
if [ ! -d node_modules ]; then
  echo "First run — installing dependencies (this can take a minute)…"
  npm install || { echo "npm install failed."; read -s -k '?Press any key to close.'; exit 1; }
fi

# In the background: open the presenter as soon as the server answers.
(
  for i in {1..120}; do
    if curl -s -o /dev/null --max-time 1 http://localhost:3000/; then
      open "$URL"
      exit 0
    fi
    sleep 0.5
  done
) &

echo "Starting TRIVIA — keep this window open while playing. Press Ctrl+C (or close the window) to stop."
npm start
read -s -k '?Server stopped. Press any key to close.'
