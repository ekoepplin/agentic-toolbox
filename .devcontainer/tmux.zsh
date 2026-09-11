#!/usr/bin/env zsh
# Mobile session handoff — sourced from ~/.zshrc on every shell login.
# SSH login  → fzf picker of existing tmux sessions (or create new)
# Local login → create a new session immediately
[[ -n "$TMUX" || -n "$NOTMUX" ]] && return

_tmux_random_name() {
  local adjectives=(brave clever dancing elegant fierce graceful happy ingenious jolly keen lively merry nimble optimal radiant swift tranquil witty zealous)
  local animals=(alpaca bear cat eagle fox goat hawk jaguar kangaroo leopard lynx owl panda penguin raccoon shark tiger wolf)
  echo "${adjectives[$RANDOM % ${#adjectives[@]} + 1]}-${animals[$RANDOM % ${#animals[@]} + 1]}"
}

_tmux_pick_session() {
  if command -v fzf &>/dev/null; then
    { echo "+ new session"; tmux ls -F "#{session_name}: #{session_windows} windows" 2>/dev/null; } \
      | fzf --height 40% --reverse --prompt="tmux session> "
  else
    echo "+ new session"
  fi
}

if [[ -n "$SSH_CONNECTION" ]]; then
  selection=$(_tmux_pick_session)
  if [[ "$selection" == "+ new session" ]]; then
    exec tmux new-session -s "$(_tmux_random_name)"
  elif [[ -n "$selection" ]]; then
    exec tmux attach-session -t "$(echo "$selection" | cut -d: -f1)"
  fi
else
  exec tmux new-session -s "$(_tmux_random_name)"
fi
