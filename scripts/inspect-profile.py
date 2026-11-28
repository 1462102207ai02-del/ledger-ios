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

    def covers(pattern, bundle_id):
        """pattern 是否授权 bundle_id。精确 ID 不授权任何子域。"""
        if pattern == "*":
            return True
        if pattern.endswith(".*"):
            head = pattern[:-1]  # 保留末尾的点
            return bundle_id.startswith(head)
        return pattern == bundle_id

    main_covered = covers(bundle_pattern, MAIN_ID) if app_id else False
    widget_covered = covers(bundle_pattern, WIDGET_ID) if app_id else False
    if app_id:
        print("  覆盖主 App ID  :", "是" if main_covered else "否 ⚠️ 工具会改写主 App Bundle ID")
        print("  覆盖 Widget ID :", "是 ✅" if widget_covered else "否 ❌")

    print("  --- 关键 entitlements ---")
    for key in ("get-task-allow", "aps-environment",
                "com.apple.security.application-groups",
                "keychain-access-groups",
                "com.apple.developer.team-identifier"):
        val = ent.get(key)
        if val is not None:
            print(f"    {key:45s} = {val}")

    groups = ent.get("com.apple.security.application-groups") or []
    if len(groups) > 1:
        print("  ℹ️  带多个 App Group（常见于多开 / 企业签名证书，用于实例隔离）。")

    print("  --- 结论 ---")
    if not app_id:
        print("  !! 描述文件里没有 application-identifier，无法重签")
    elif widget_covered:
        print("  ✅ 这份描述文件同时授权主 App 与 .widget。")
        print("     只要工具递归重签 PlugIns/LedgerWidget.appex，主包就能带小组件安装。")
        print("     签名时不要改 Bundle Identifier、不要开多开。")
        if not main_covered:
            print("     ⚠️ 但它不授权主 App 原本的 ID，工具仍会改写主 App ID；")
            print("        需确认 widget ID 被同步改成新主 App ID 的前缀子域。")
    else:
        print("  ❌ 这份描述文件不授权 com.mazexin.Bookkeeping.widget → 0xE8008016")
        if not is_wildcard:
            print("     精确 App ID 不授权任何子域：即使工具把 widget 改成")
            print("     " + bundle_pattern + ".widget，仍不在授权范围内。")
        if not main_covered:
            print("     ⚠️ 且 App ID 与主 App 原本的 ID 不一致，全能签必然改写主 App ID")
            print("        才能装上（去掉 PlugIns 的诊断包能装就是证据）；而 appex ID 不会")
            print("        跟着改，既不是新主 App ID 的前缀子域、也不在授权范围内 → 双重不匹配。")
        print("     → 这套证书下带小组件的包物理上装不上，改包也没用。")
        print("     解法：① 找证书下发方换一份通配符 App ID 的描述文件；")
        print("           ② 用桌面 快捷记账-无小组件-诊断用.ipa（A/B 已验证可装）；")
        print("           ③ 或 TrollStore 装主包（带小组件）。")

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
