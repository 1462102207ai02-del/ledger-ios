#!/usr/bin/env bash
# 后台监听：等待最新一次构建结束，成功后自动把 ipa 拉到桌面
# 这是"云端无法主动推送到本机"的替代方案——由本机轮询感知并拉取
set -uo pipefail

OWNER="1462102207ai02-del"
REPO="ledger-ios"
BASELINE_ID="44662273158"   # 触发前最后一次运行的 id，只认比它更新的

TOKEN="$(printf "protocol=https\nhost=github.com\n\n" | git credential fill 2>/dev/null | grep '^password=' | cut -d= -f2-)"
if [ -z "$TOKEN" ]; then echo "❌ 无 token"; exit 1; fi
API="https://api.github.com/repos/$OWNER/$REPO"
HDR=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAX=$((25*60))   # 最多等 25 分钟
ELAPSED=0

echo "==> 开始监听构建（基线 run #$BASELINE_ID）..."
while [ "$ELAPSED" -lt "$MAX" ]; do
  JSON="$(curl -s --max-time 30 "${HDR[@]}" "$API/actions/runs?per_page=5")"
  INFO="$(echo "$JSON" | python -c "
import sys,json
base=int('$BASELINE_ID')
d=json.load(sys.stdin)
for r in d.get('workflow_runs',[]):
    if int(r['id'])>base:
        print('%s|%s|%s' % (r['id'], r['status'], r['conclusion'] or ''))
        break
" 2>/dev/null || true)"

  if [ -n "$INFO" ]; then
    ID="${INFO%%|*}"; REST="${INFO#*|}"; STATUS="${REST%%|*}"; CONCL="${REST#*|}"
    echo "    run #$ID  status=$STATUS  conclusion=$CONCL  (${ELAPSED}s)"
    if [ "$STATUS" = "completed" ]; then
      if [ "$CONCL" = "success" ]; then
        echo "==> 构建成功，拉取 ipa 到桌面..."
        bash "$SCRIPT_DIR/fetch-ipa.sh"
        exit 0
      else
        echo "❌ 构建结束但未成功（conclusion=$CONCL）。需要查看编译日志修复。"
        exit 2
      fi
    fi
  else
    echo "    等待新构建出现... (${ELAPSED}s)"
  fi
  sleep 30
  ELAPSED=$((ELAPSED+30))
done
echo "⏱️ 监听超时（25 分钟），构建仍未结束。"
exit 3
