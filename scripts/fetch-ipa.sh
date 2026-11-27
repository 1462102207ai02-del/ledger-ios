#!/usr/bin/env bash
# 从 GitHub Actions 拉取成功构建的通用 IPA 到桌面
# 用法：bash scripts/fetch-ipa.sh [commit短sha]  传了则只拉指定 commit 的构建
#
# 现在只产出一个通用包 LedgerApp.ipa：TrollStore 直装与真证书工具重签共用。
set -euo pipefail

WANT_SHA="${1:-}"

OWNER="1462102207ai02-del"
REPO="ledger-ios"
# 新工作流用 LedgerApp-IPA；保留旧名以兼容历史构建
ARTIFACT_NAMES=("LedgerApp-IPA" "LedgerApp-TrollStore")
IPA_NAME="LedgerApp.ipa"

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

echo "==> 查找成功构建$( [ -n "$WANT_SHA" ] && echo " (commit $WANT_SHA)" )..."
RUN_JSON="$(curl -s --max-time 30 "${HDR[@]}" "$API/actions/runs?status=success&per_page=20")"
RUN_ID="$(echo "$RUN_JSON" | WANT="$WANT_SHA" python -c "
import sys,json,os
d=json.load(sys.stdin)
want=os.environ['WANT']
runs=d.get('workflow_runs',[])
if want:
    for r in runs:
        if r['head_sha'].startswith(want):
            print(r['id']); break
else:
    if runs: print(runs[0]['id'])
" 2>/dev/null || true)"
if [ -z "$RUN_ID" ]; then
  echo "❌ 还没有成功的构建。请先在仓库 Actions 页等待构建变绿，或检查编译日志。"
  exit 1
fi
echo "    构建 #$RUN_ID"

echo "==> 查找 ipa 产物..."
ART_JSON="$(curl -s --max-time 30 "${HDR[@]}" "$API/actions/runs/$RUN_ID/artifacts")"
ART_NAMES="$(IFS='|'; echo "${ARTIFACT_NAMES[*]}")"
export ART_NAMES
ART_ID="$(echo "$ART_JSON" | python -c "
import sys,json,os
d=json.load(sys.stdin)
names=set(os.environ['ART_NAMES'].split('|'))
for a in d.get('artifacts',[]):
    if a['name'] in names and not a.get('expired'):
        print(a['id']); break
" 2>/dev/null || true)"
if [ -z "$ART_ID" ]; then
  echo "❌ 该构建没有找到有效的 IPA 产物（可能已过期）。"
  exit 1
fi
echo "    产物 #$ART_ID"

echo "==> 下载并解压..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -sL --max-time 180 "${HDR[@]}" -o "$TMP/artifact.zip" "$API/actions/artifacts/$ART_ID/zip"
unzip -qo "$TMP/artifact.zip" -d "$TMP/out"

IPA="$(find "$TMP/out" -name "$IPA_NAME" -type f | head -1)"
# 兼容旧构建（TrollStore 版文件名）
if [ -z "$IPA" ]; then
  IPA="$(find "$TMP/out" -name '*.ipa' -type f | head -1)"
fi
if [ -z "$IPA" ]; then
  echo "❌ 解压后未找到 ipa 文件。"
  exit 1
fi

TARGET="$DESKTOP/快捷记账.ipa"
cp "$IPA" "$TARGET"
echo "✅ 通用版已放到桌面：$TARGET（TrollStore 直装 / 真证书重签共用）"
ls -lh "$TARGET" | awk '{print "    大小: "$5}'
