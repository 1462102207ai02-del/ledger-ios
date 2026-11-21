#!/usr/bin/env bash
# 拉取 ocr-test 分支构建的 TrollStore ipa 到桌面（测试版，独立产物名）
# 用法：bash scripts/fetch-ocr-test.sh [commit短sha]
set -euo pipefail

WANT_SHA="${1:-}"
OWNER="1462102207ai02-del"
REPO="ledger-ios"
ARTIFACT_NAME="LedgerAppTest-TrollStore"

detect_desktop() {
  if [ -d "/c/Users/$(whoami)/Desktop" ]; then echo "/c/Users/$(whoami)/Desktop"
  elif [ -n "${USERPROFILE:-}" ] && [ -d "$(cygpath -u "$USERPROFILE" 2>/dev/null)/Desktop" ]; then cygpath -u "$USERPROFILE"/Desktop
  elif [ -d "$HOME/Desktop" ]; then echo "$HOME/Desktop"
  else echo "$HOME"; fi
}
DESKTOP="$(detect_desktop)"

TOKEN=""
if [ -s /tmp/gh_token ]; then TOKEN="$(cat /tmp/gh_token)"; fi
if [ -z "$TOKEN" ]; then
  TOKEN="$(printf "protocol=https\nhost=github.com\n\n" | git credential fill 2>/dev/null | grep '^password=' | cut -d= -f2-)"
  [ -n "$TOKEN" ] && printf '%s' "$TOKEN" > /tmp/gh_token
fi
if [ -z "$TOKEN" ]; then echo "❌ 未找到 GitHub token"; exit 1; fi

API="https://api.github.com/repos/$OWNER/$REPO"
HDR=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

echo "==> 查找成功构建$( [ -n "$WANT_SHA" ] && echo " (commit $WANT_SHA)" )..."
RUN_JSON="$(curl -s --max-time 30 "${HDR[@]}" "$API/actions/runs?status=success&per_page=20")"
RUN_ID="$(echo "$RUN_JSON" | WANT="$WANT_SHA" python -c "
import sys,json,os
d=json.load(sys.stdin); want=os.environ['WANT']
for r in d.get('workflow_runs',[]):
    if want and r['head_sha'].startswith(want): print(r['id']); break
    if not want: print(r['id']); break
" 2>/dev/null || true)"
if [ -z "$RUN_ID" ]; then echo "❌ 还没有该 commit 的成功构建"; exit 1; fi
echo "    构建 #$RUN_ID"

echo "==> 查找 ipa 产物..."
ART_JSON="$(curl -s --max-time 30 "${HDR[@]}" "$API/actions/runs/$RUN_ID/artifacts")"
ART_ID="$(echo "$ART_JSON" | ART_NAME="$ARTIFACT_NAME" python -c "
import sys,json,os
d=json.load(sys.stdin); name=os.environ['ART_NAME']
for a in d.get('artifacts',[]):
    if a['name']==name and not a.get('expired'): print(a['id']); break
" 2>/dev/null || true)"
if [ -z "$ART_ID" ]; then echo "❌ 未找到产物 $ARTIFACT_NAME"; exit 1; fi
echo "    产物 #$ART_ID"

echo "==> 下载并解压..."
TMP="$(mktemp -d)"
curl -sL --max-time 180 "${HDR[@]}" -o "$TMP/artifact.zip" "$API/actions/artifacts/$ART_ID/zip"
unzip -qo "$TMP/artifact.zip" -d "$TMP/out"
IPA="$(find "$TMP/out" -name '*.ipa' -type f | head -1)"
if [ -z "$IPA" ]; then echo "❌ 解压后未找到 ipa"; exit 1; fi

TARGET="$DESKTOP/快捷记账OCR测试版.ipa"
cp "$IPA" "$TARGET"
echo "✅ 已放到桌面：$TARGET"
ls -lh "$TARGET" | awk '{print "    大小: "$5}'
