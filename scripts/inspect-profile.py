#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
检查 .mobileprovision（或证书 zip / 目录）能否用于重签带小组件的 IPA。

用法：
    python scripts/inspect-profile.py <文件.mobileprovision | 证书.zip | 目录>
    python scripts/inspect-profile.py C:/Users/Administrator/Desktop/证书.zip

输出：App ID 是通配符还是精确 ID、Team ID、entitlements、有效期、UDID，
并直接给出「这份描述文件能不能签带 LedgerWidget.appex 的包」的结论。

不需要任何第三方库，Python 3 标准库即可。描述文件是 CMS DER 容器，
内嵌的 XML plist 可以直接定位取出，因此也不依赖 openssl。
"""

import datetime
import io
import os
import plistlib
import sys
import zipfile

MAIN_ID = "com.mazexin.Bookkeeping"
WIDGET_ID = "com.mazexin.Bookkeeping.widget"


def extract_plist(raw: bytes):
    """从 CMS 容器里取出内嵌 plist。优先 XML，其次 binary plist。"""
    start = raw.find(b"<?xml")
    if start >= 0:
        end = raw.find(b"</plist>", start)
        if end >= 0:
            return raw[start:end + len(b"</plist>")]
    start = raw.find(b"bplist00")
    if start >= 0:
        return raw[start:]
    return None


def parse(raw: bytes):
    payload = extract_plist(raw)
    if not payload:
        return None
    try:
        return plistlib.loads(payload)
    except Exception:
        return None


def collect(path: str):
    """返回 [(来源名, 原始字节)]。支持单文件、zip、目录。"""
    out = []
    if os.path.isdir(path):
        for root, _, files in os.walk(path):
            for name in files:
                if name.lower().endswith((".mobileprovision", ".zip")):
                    out.extend(collect(os.path.join(root, name)))
        return out

    low = path.lower()
    if low.endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            for name in z.namelist():
                if name.lower().endswith(".mobileprovision"):
                    out.append((f"{os.path.basename(path)}!/{name}", z.read(name)))
        return out

    with open(path, "rb") as f:
        out.append((os.path.basename(path), f.read()))
    return out


def fmt_date(value):
    if isinstance(value, datetime.datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return str(value)


def describe(label: str, raw: bytes):
    d = parse(raw)
    print("=" * 66)
    print("来源:", label)
    if not d:
        print("  !! 无法解析：这不是有效的 .mobileprovision，或被加密/损坏")
        return

    print("  名称          :", d.get("Name") or d.get("AppIDName") or "(无)")
    print("  Team ID       :", (d.get("TeamIdentifier") or ["?"])[0])
    print("  创建 / 过期   :", fmt_date(d.get("CreationDate", "?")), "→",
          fmt_date(d.get("ExpirationDate", "?")))
    print("  UUID          :", d.get("UUID", "?"))

    devices = d.get("ProvisionedDevices") or []
    note = "企业/通用分发，不限制设备" if d.get("ProvisionsAllDevices") else "需包含本机 UDID"
    print("  UDID 数量     :", len(devices), "（" + note + "）")

    ent = d.get("Entitlements") or {}
    app_id = ent.get("application-identifier", "")
    team_prefix = (d.get("ApplicationIdentifierPrefix") or [""])[0]
    bundle_pattern = app_id[len(team_prefix) + 1:] if app_id.startswith(team_prefix + ".") else app_id

    print("  application-identifier :", app_id or "(无)")
    print("  App ID 模式   :", bundle_pattern or "(无)")
    is_wildcard = "*" in bundle_pattern
    print("  App ID 类型   :", "通配符 ✅" if is_wildcard else "精确 ID ❌")

    print("  --- 关键 entitlements ---")
    for key in ("get-task-allow", "aps-environment",
                "com.apple.security.application-groups",
                "keychain-access-groups",
                "com.apple.developer.team-identifier"):
        val = ent.get(key)
        if val is not None:
            print(f"    {key:45s} = {val}")

    print("  --- 结论 ---")
    if not app_id:
        print("  !! 描述文件里没有 application-identifier，无法重签")
    elif is_wildcard:
        print("  ✅ 通配符 App ID：可同时覆盖主 App 与 .widget 扩展。")
        print("     只要重签工具递归签 PlugIns/LedgerWidget.appex，主包就能带小组件安装。")
        print("     若全能签仍装不上，几乎可以确定是工具只签了主 App / 改写了主 App Bundle ID")
        print("     却没同步改写 appex 的 Bundle ID（扩展 ID 必须是主 App ID 的前缀）。")
    else:
        print("  ❌ 精确 App ID：只授权", bundle_pattern)
        print("     com.mazexin.Bookkeeping.widget 不在授权范围内 → 安装时 0xE8008016")
        print("     → 「无法安装，请稍后再试」。这就是 A/B 诊断确认的根因。")
        print("     解法：① 找证书下发方换一份通配符 App ID 的描述文件；")
        print("           ② 或让工具为 .widget 单独生成描述文件；")
        print("           ③ 或使用桌面上去掉 PlugIns 的 快捷记账-无小组件-诊断用.ipa。")

    if ent.get("com.apple.security.application-groups"):
        print("  ℹ️  该描述文件带 App Group：小组件数据可走共享容器（最完整）。")
    elif ent.get("keychain-access-groups"):
        print("  ℹ️  该描述文件带 Keychain 组：小组件数据可走 Keychain 快照兜底。")
    else:
        print("  ℹ️  未带 App Group / Keychain 组：小组件可能显示空数据，仍可点击直达「记一笔」。")
    print()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("提示：也可直接把 .mobileprovision 或证书 zip 放到桌面后把路径告诉我，我来跑。")
        return 1
    items = []
    for arg in sys.argv[1:]:
        items.extend(collect(arg))
    if not items:
        print("没有找到任何 .mobileprovision。请传入 .mobileprovision 文件或包含它的 zip。")
        return 1
    for label, raw in items:
        describe(label, raw)
    print("=" * 66)
    print("主 App ID :", MAIN_ID)
    print("Widget ID :", WIDGET_ID, "（必须是主 App ID 的前缀子域）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
