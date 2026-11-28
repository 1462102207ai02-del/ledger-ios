# 记账 · 个人账本

一个只服务于一人的 iOS 记账 App，SwiftUI 原生开发，数据全部存本机，不联网、不上传。
Bundle ID：`com.mazexin.Bookkeeping`。签名保持干净，不含任何受限 entitlement；App Group 改为运行时动态发现。

## 功能

- **记一笔**：支出 / 收入、项目、金额、支付方式、日期时间（精确到分）、备注
  - 项目与支付方式改为**半透明遮罩 + 居中卡片弹窗**：纯文字平铺选项（不带图标）、支持搜索，项目再多也不用拉长列表
  - 弹窗内可**现场输入自定义项目**；该笔账单保存后，新项目自动归入对应分组（支出项目 / 收入项目 / 支付方式），之后可直接选用，也能在设置里改名或删除。取消记账不会留下孤立项目
  - 保存后保留项目与支付方式，键盘回到金额，方便连续记账
- **明细**：按日分组的倒序流水；可切换「全部记录 / 按日期」查看某一天；点击任意一笔进入**编辑**，可改类型、项目、金额、支付方式、时间、备注；左滑删除
- **统计**：可切换月份；本月支出 / 收入 / 结余；**本月每日支出**与**近 6 个月支出**柱状趋势图（Y 轴刻度、虚线网格与基线、日均参考线、峰值高亮、点击查看具体金额，纯 SwiftUI 自绘，不依赖 iOS 16 Charts）；按项目、按支付方式的支出排行（金额 + 真实占比）
- **小组件**：小 / 中 / 大三种尺寸，点击任意位置直达「记一笔」并自动聚焦金额；跨 0 点准时刷新「今日」数据
- **设置**：三大类项目（支出 / 收入 / 支付方式）以**可折叠分组**收纳，点开后增删改；重命名会同步更新历史账目；一键恢复预置；**导出 / 导入账本 JSON**

## 预置项目

- 支出：早餐、午餐、晚餐、宵夜、麻将、香烟、饮料、信用卡、花呗、借呗、京东白条、京东金条、分付
- 收入：工资、货款
- 支付方式：微信、支付宝、银行卡、现金

以上全部可在「设置」中自行增删改。记过的账以文字保存，删除项目不会丢失历史记录。支出与收入各自独立查重，允许同名项目。

## 数据

数据以 JSON 存于 `ledger_data.json`：优先写运行时发现的 App Group 共享容器（主 App 与小组件共用），不可用时回退到主 App 沙盒 `Documents/`。小组件还有一条独立的 Keychain 快照通道，见「只出一个包，两种装法都支持全部功能」。

- 所有写入为原子写，金额求和统一走 `Decimal`，避免 `Double` 累加误差。
- `schemaVersion` 用于兼容旧账本；旧文件会自动补写版本字段，旧路径数据会自动迁移到共享容器。
- **文件损坏时不会静默清空**：先把原文件另存为 `ledger_data.corrupt-<时间戳>.json`，再显示空白账本并在「设置」里告警。
- 「设置 → 导出账本 JSON」可通过系统分享面板存到「文件」等位置；「导入账本 JSON」会整体替换当前账本，覆盖前自动留一份 `ledger_data.backup-<时间戳>.json`。
- **卸载 App 仍会带走沙盒数据，请定期导出备份。**

## 快速记一笔

小组件通过 `ledger://add` 唤起主 App（URL Scheme 注册在 `LedgerApp/Info.plist`），主 App 切到「记一笔」并自动聚焦金额输入框。

## 如何构建 / 安装 IPA

源码本身不能直接在 Windows 上编译 iOS 包，构建交给 GitHub Actions：

1. 每次 `git push` 到 `main` 分支会自动触发构建；也可在仓库 Actions 页手动点 **Run workflow**。
2. 构建完成后，进入该次运行的页面，在底部 **Artifacts** 区下载 `LedgerApp-IPA`（一个 zip）。
3. 解压后得到**唯一一个** `LedgerApp.ipa`。

### 只出一个包，两种装法都支持全部功能

早期版本按「签名方式」拆成三个包，后来合并为单一通用包。当前版本把**签名骨架与权限解耦**：主 App 与小组件都做标准 ad-hoc 签名，**生成完整的 `_CodeSignature/CodeResources` 资源 seal，但不写入任何受限 entitlement**。

### 为什么 p12 自签报「无法安装，请稍后再试」

这个提示是 iOS 最泛化的安装失败文案，不含错误码，说明校验在早期就被拒。**已由真机 A/B 确诊**：把主包里 `PlugIns` 删掉生成的 `快捷记账-无小组件-诊断用.ipa`，用**同一套 p12、同一个重签工具、同一台设备**签名后**安装成功**。这是单变量对照，因此：

- ✅ **根因 100% 是 `PlugIns/LedgerWidget.appex` 这个独立签名实体**未被正确重签 / 未被 profile 授权。
- ✅ 主 App 二进制、证书、UDID、开发者模式、设备残留**全部清白**——否则诊断包也装不上。
- ✅ 「旧版残留 / 换签名身份拒绝覆盖」这条在本次 A/B 中同样被排除，降级。
- ✅ 不可能 Swift 代码问题：安装阶段 `installd` 不执行任何 App/Widget 代码。

TrollStore 之所以正常，是因为它走 CoreTrust **绕过 provisioning profile 校验**，appex 有没有 profile、entitlements 对不对都放行；p12 自签走标准 `installd`，要求**每个 app extension 各有一份匹配的 profile**。

| # | 原因 | 状态 | 处理 |
| --- | --- | --- | --- |
| 1 | appex 是独立签名实体：独立 Bundle ID `com.mazexin.Bookkeeping.widget`、独立签名、独立 entitlements；精确 App ID 的 profile 只授权 `com.mazexin.Bookkeeping` → `0xE8008016` | **✅ A/B 确诊** | 用通配符 App ID + 支持递归签 `PlugIns` 的工具 |
| 2 | 设备上旧版残留 / 换签名身份无法覆盖 | A/B 已排除（本次） | 仅当换过证书才需先卸载 |
| 3 | 硬编码 `com.apple.security.application-groups` | 已修复 | 签名里无此键，App Group 运行时动态发现 |
| 4 | 缺 `_CodeSignature/CodeResources` 资源 seal | 已修复 | `codesign -s -`，先签 appex 再签主 App |

拆包事实：主 App 与 appex 二进制的 `__entitlements` 段**都为空**（连 `application-identifier` 都没有），整个 IPA **不含任何 `embedded.mobileprovision`**。重签工具必须自己从 profile 生成**两套**完整权限集并分别签名；只会「沿用原 entitlements」或只签主 App 的工具必然失败。这不是 Widget 代码问题，Widget 侧也未调用任何 `NS_EXTENSION_UNAVAILABLE` API。

### 关键答案：怎么在不换证书的前提下保留小组件

「独立签名实体」的反面**不是**把 Widget 代码并进主 App 二进制——iOS 架构不允许，WidgetKit 要求小组件必须是独立 `.appex`。真正的反面是：**让 appex 不再需要独立授权**。

用一份**通配符 App ID** 的 profile（如 `com.mazexin.*` 或 `*`），它就同时覆盖 `com.mazexin.Bookkeeping` 与 `com.mazexin.Bookkeeping.widget`。两个 bundle 仍各自签名，但共享同一个授权域，`installd` 不再把扩展当成「没有 profile 的外来物」。配合工具**递归重签 `PlugIns`**，主包 `快捷记账.ipa` 就能带完整小组件装上。

> 也就是说：**包本身不用改**，要改的是 profile 的 App ID 类型和工具里的扩展签名开关。

| 账号 / 工具情况 | 结论 |
| --- | --- |
| **免费个人 Apple ID** | Apple 不允许签 App Extension，物理上无解。只能自签去组件 |
| 付费账号 + 通配符 App ID | 换 profile + 工具开启递归签 appex → 主包直接可用，带小组件 |
| 付费账号 + 精确 App ID | 需为 `.widget` 单独建 App ID / profile，或让工具自动改写扩展 Bundle ID |
| 工具会跳过 / 自动删除 `PlugIns`（如勾了 "Remove App Extensions"） | 关掉该选项或换工具（Sideloadly / AltStore / Feather / ESign 高级模式） |

### 小组件数据怎么传（不再硬依赖 App Group）

| 优先级 | 通道 | 生效条件 | 说明 |
| --- | --- | --- | --- |
| 1 | App Group 共享容器 | 重签 profile / 工具注入了任意 App Group | App Group ID **运行时从 `embedded.mobileprovision` 动态解析**，不再写死；主 App 与小组件用同一个值，数据最完整 |
| 2 | Keychain 快照 | profile 带 `keychain-access-groups`（多数自签 profile 默认带） | 主 App 每次保存账本或冷启动时写一份精简快照，小组件读不到共享容器时读它 |
| 3 | 空态 | 以上都不可用 | 小组件显示空数据，点它可直达「记一笔」 |

补充两点实证约束，避免再走弯路：

- **不用剪贴板兜底**：Apple 明确「后台无法读取剪贴板」是策略限制，而 Widget 的 TimelineProvider 正是后台进程；且命名剪贴板自 iOS 10 起非持久化、只在创建它的进程内可用。所以 `UIPasteboard` 方案在真机上必然失效。
- **快照按当前日期重算**：快照里存的是精简后的账目记录（最近 150 条），今日 / 本月汇总由小组件按刷新当天重新计算，跨 0 点不会显示昨天的数字。

| 安装方式 | 签名 | 主 App 功能 | 小组件 |
| --- | --- | --- | --- |
| TrollStore / TrollFools | 包内纯净 ad-hoc 签名 | 全部 | 有；共享容器 / Keychain 任一可用即完整显示 |
| 真证书自签（付费账号 + 递归签 appex） | 工具重签覆盖 | 全部（同一份代码） | 有 |
| 真证书自签（免费个人账号 / 只签主 App 的工具 / 精确 App ID） | 工具重签覆盖 | **✅ A/B 已验证可装**（去掉 `PlugIns` 后） | 需去掉 `PlugIns` 才能装，装了也没小组件 |

### p12 自签安装与验证清单

1. ✅ **A/B 已完成（用户真机验证）**：`快捷记账-无小组件-诊断用.ipa` 用同一套 p12 / 同一工具 / 同一设备**签名安装成功** → 根因确诊为 appex，主 App 与证书全部清白。
2. 现在设备上装的是 **p12 签的无组件版**。后续用同一套 p12 重签主包覆盖安装，签名身份一致，原则上**不需要再卸载**；若覆盖失败再卸载重试。
3. 要保留小组件：换**通配符 App ID** 的 profile，并确认工具**递归重签全部 `PlugIns`**（Sideloadly / AltStore / Feather / ESign 高级模式）。主 App 与扩展必须同一个 Team。
4. 若工具支持自定义 entitlements，可给主 App 与 widget **注入同一个 App Group**（名字任意），App 会自动识别并使用，小组件数据最完整。
5. 装好后**先打开一次主 App**，让 Keychain 快照写入；再添加 / 刷新小组件。
6. 若仍失败，记录工具名称与具体报错（`0xE8008016` invalid entitlements / `0xE8008015` / `ApplicationVerificationFailed` 等）。

> **最坏情况已经可用**：桌面 `快捷记账-无小组件-诊断用.ipa` 可直接当作自签正式包（主 App 全部功能在，仅无桌面小组件）；TrollStore 继续用 `快捷记账.ipa`（带小组件）。这是按「能力」分两个包，与早期按签名方式乱拆三个包不是一回事。
>
> 补充：`0xE8008016` 在带 Widget 的 IPA 上极常见，公开案例明确指出「扩展 target 用了另一个团队或缺少对应能力的描述文件」「第三方工具重签的包」是主因；免费个人账号则根本无法签 App Extension。

构建流程：XcodeGen 生成工程 → xcodebuild 编译未签名 app → `codesign -s -` 先签 widget appex、再签主 App，生成完整 `_CodeSignature/CodeResources` 且不写任何 entitlement → CI 硬校验「两个 bundle 都有 seal」和「签名里不含 `com.apple.security.application-groups`」→ 打包成单个 IPA → 上传 artifact。取包也可直接跑 `bash scripts/fetch-ipa.sh [commit短sha]`，会把通用版放到桌面 `快捷记账.ipa`。

## 修改内置项目

编辑 `LedgerApp/Models.swift` 里的 `builtInExpense`、`builtInIncome`、`builtIn` 三个数组，push 后重新构建即可。
