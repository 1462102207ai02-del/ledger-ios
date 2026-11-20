#!/usr/bin/env bash
# 从 GitHub Actions 拉取最新一次成功构建的 TrollStore ipa 到桌面
# 用法：bash scripts/fetch-ipa.sh
set -euo pipefail

OWNER="1462102207ai02-del"
REPO="ledger-ios"
ARTIFACT_NAME="LedgerApp-TrollStore"

# 自动探测桌面路径（Windows Git Bash / macOS / Linux）
detect_desktop() {
  if [ -d "/c/Users/$(whoami)/Desktop" ]; then echo "/c/Users/$(whoami)/Desktop"
  elif [ -n "${USERPROFILE:-}" ] && [ -d "$(cygpath -u "$USERPROFILE" 2>/dev/null)/Desktop" ]; then cygpath -u "$USERPROFILE"/Desktop
  elif [ -d "$HOME/Desktop" ]; then echo "$HOME/Desktop"
  else echo "$HOME"; fi
}
DESKTOP="$(detect_desktop)"

# 优先读缓存 token（避免凭证管理器反复弹窗），没有再回退到 git credential
TOKEN=""
if [ -s /tmp/gh_token ]; then TOKEN="$(cat /tmp/gh_token)"; fi
if [ -z "$TOKEN" ]; then
  TOKEN="$(printf "protocol=https\nhost=github.com\n\n" | git credential fill 2>/dev/null | grep '^password=' | cut -d= -f2-)"
  [ -n "$TOKEN" ] && printf '%s' "$TOKEN" > /tmp/gh_token
fi
if [ -z "$TOKEN" ]; then
  echo "❌ 未找到 GitHub token，请先确保 git 已登录（credential.helper=manager）"
  exit 1
fi

API="https://api.github.com/repos/$OWNER/$REPO"
HDR=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

echo "==> 查找最近一次成功构建..."
RUN_JSON="$(curl -s --max-time 30 "${HDR[@]}" "$API/actions/runs?status=success&per_page=10")"
RUN_ID="$(echo "$RUN_JSON" | python -c "
import sys,json
d=json.load(sys.stdin)
runs=d.get('workflow_runs',[])
print(runs[0]['id'] if runs else '')
" 2>/dev/null || true)"
if [ -z "$RUN_ID" ]; then
  echo "❌ 还没有成功的构建。请先在仓库 Actions 页等待构建变绿，或检查编译日志。"
  exit 1
fi
echo "    构建 #$RUN_ID"

echo "==> 查找 ipa 产物..."
ART_JSON="$(curl -s --max-time 30 "${HDR[@]}" "$API/actions/runs/$RUN_ID/artifacts")"
ART_ID="$(echo "$ART_JSON" | python -c "
import sys,json
d=json.load(sys.stdin)
for a in d.get('artifacts',[]):
    if a['name']=='$ARTIFACT_NAME' and not a.get('expired'):
        print(a['id']); break
" 2>/dev/null || true)"
if [ -z "$ART_ID" ]; then
  echo "❌ 该构建没有找到名为 $ARTIFACT_NAME 的有效产物（可能已过期）。"
  exit 1
fi
echo "    产物 #$ART_ID"

echo "==> 下载并解压..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -sL --max-time 180 "${HDR[@]}" -o "$TMP/artifact.zip" "$API/actions/artifacts/$ART_ID/zip"
unzip -qo "$TMP/artifact.zip" -d "$TMP/out"

IPA="$(find "$TMP/out" -name '*.ipa' -type f | head -1)"
if [ -z "$IPA" ]; then
  echo "❌ 解压后未找到 ipa 文件。"
  exit 1
fi

TARGET="$DESKTOP/LedgerApp-TrollStore.ipa"
cp "$IPA" "$TARGET"
echo "✅ 已放到桌面：$TARGET"
ls -lh "$TARGET" | awk '{print "    大小: "$5}'
