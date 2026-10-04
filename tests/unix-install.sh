#!/usr/bin/env bash
set -euo pipefail
REPO="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
export XDG_STATE_HOME="$HOME/state"
export LMSTUDIO_CODEX_HOME="$HOME/codex"
export SHELL=/bin/bash
mkdir -p "$HOME" "$TEST_ROOT/mock-bin" "$TEST_ROOT/package with spaces"
cp -R "$REPO/install" "$TEST_ROOT/package with spaces/install"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/mock-bin/lms"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/mock-bin/codex"
chmod +x "$TEST_ROOT/mock-bin/"*
export PATH="$TEST_ROOT/mock-bin:$HOME/.local/bin:$PATH"
bash "$TEST_ROOT/package with spaces/install/install.sh"
lm-studio --help | grep -q 'Continue tasks in a session'
bash "$TEST_ROOT/package with spaces/install/install.sh"
bash "$TEST_ROOT/package with spaces/install/uninstall.sh"
test ! -e "$HOME/.local/bin/lm-studio"
printf '#!/usr/bin/env bash\necho foreign\n' > "$HOME/.local/bin/lm-studio"
if bash "$TEST_ROOT/package with spaces/install/install.sh"; then
  echo 'Installer overwrote a foreign command' >&2
  exit 1
fi
grep -q foreign "$HOME/.local/bin/lm-studio"
