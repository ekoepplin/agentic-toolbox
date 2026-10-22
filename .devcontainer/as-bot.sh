#!/usr/bin/env bash
# as-bot <command> [args...] — run an agent CLI as the optional bot GitHub
# identity, so its commits, pushes and `gh` calls land on that account.
#
#   BOT_GIT_USER   GitHub login of the bot           (fallback: PI_GIT_USER)
#   BOT_GIT_EMAIL  commit email                      (fallback: PI_GIT_EMAIL,
#                  then <user>@users.noreply.github.com)
#   BOT_GH_TOKEN   the bot's PAT, scopes repo+workflow (fallback: PI_GH_TOKEN)
#
# Unset → the command runs as-is under the personal identity. Scoped to this
# process only: git commits made from the shell itself keep the personal
# identity. Without a token, pushes fail instead of falling back to another
# login: the credential helpers are replaced, gh gets its own empty config
# dir, and no other GitHub token is passed through (the owner's human tokens,
# GITHUB_ROBOT_MAC_MINI / GITHUB_TOKEN_MACBOOK, are removed).
#
# Installed in the image as /usr/local/bin/as-bot (the shell's `pi` and
# `claude` go through it); the ralph scripts call this file from the base.
set -euo pipefail

# In a workbench, sshd sessions start with a fresh environment, so compose's
# BOT_*/PI_* never reach them; the dock step persists those vars here.
# The process environment wins when it has them.
bot_env="$HOME/.config/as-bot.env"
if [[ -z ${BOT_GIT_USER:-}${PI_GIT_USER:-} && -r $bot_env ]]; then
  # shellcheck source=/dev/null
  source "$bot_env"
fi

user="${BOT_GIT_USER:-${PI_GIT_USER:-}}"
[[ -n $user ]] || exec "$@"

email="${BOT_GIT_EMAIL:-${PI_GIT_EMAIL:-$user@users.noreply.github.com}}"
token="${BOT_GH_TOKEN:-${PI_GH_TOKEN:-}}"
[[ -n $token ]] || echo "as-bot: BOT_GH_TOKEN not set; commits stay $user, pushes will fail" >&2

unset GITHUB_ROBOT_MAC_MINI GITHUB_TOKEN_MACBOOK
export GIT_AUTHOR_NAME="$user" GIT_AUTHOR_EMAIL="$email"
export GIT_COMMITTER_NAME="$user" GIT_COMMITTER_EMAIL="$email"
export GH_TOKEN="$token" GITHUB_TOKEN="$token" GH_CONFIG_DIR="$HOME/.config/gh-$user"
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
export GIT_CONFIG_KEY_1=credential.https://github.com.helper
export GIT_CONFIG_VALUE_1="!f() { test \"\$1\" = get && test -n \"\$GH_TOKEN\" && echo username=$user && echo \"password=\$GH_TOKEN\"; }; f"
exec "$@"
