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

早期版本按「签名方式」拆成三个包，后来合并为单一通用包。当前版本进一步把**签名与权限解耦**：主 App 与小组件都只做纯 `ldid -S` ad-hoc 签名，**不写入任何受限 entitlement**。

### 为什么 p12 自签以前装不上

`com.apple.security.application-groups` 属于受限 entitlement。旧版把它硬写进两个可执行文件的签名里，而你的 p12 / provisioning profile 不会带 `group.com.mazexin.Bookkeeping`（App Group ID 全局唯一、只属于注册它的开发者团队）。重签工具若继承原 entitlements，安装校验就会因「entitlement 未被 profile 授权」失败——这是最典型的自签安装失败原因。现在签名里已经彻底没有这个键。

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
| 真证书自签 | 工具重签覆盖 | 全部（同一份代码） | 有；不再因受限 entitlement 安装失败 |

### p12 自签安装与验证清单

1. 用**支持 `PlugIns` appex 重签**的工具（ESign / Feather / Sideloadly / AltStore 等）。若工具会跳过插件，小组件自然不会出现。
2. profile 的 App ID 需能覆盖 `com.mazexin.Bookkeeping.widget`；用通配符 App ID，或让工具自动改写 appex 的 Bundle ID。Bundle ID 与 profile 不匹配是另一类常见安装失败。
3. 若工具支持自定义 entitlements，可给主 App 与 widget **注入同一个 App Group**（名字任意），App 会自动识别并使用，小组件数据最完整。
4. 装好后**先打开一次主 App**，让 Keychain 快照写入；再添加 / 刷新小组件。
5. 若仍安装失败，请记录工具名称与具体报错（`0xE8008015` / `ApplicationVerificationFailed` / entitlements 相关字样等），据此继续定位——这类信息与打包无关，需要真机日志才能定性。

构建流程：XcodeGen 生成工程 → xcodebuild 编译未签名 app → 一次 `ldid -S` 对主 App 与 widget 做纯净 ad-hoc 签名 → CI 校验签名里不含 `com.apple.security.application-groups` → 打包成单个 IPA → 上传 artifact。取包也可直接跑 `bash scripts/fetch-ipa.sh [commit短sha]`，会把通用版放到桌面 `快捷记账.ipa`。

## 修改内置项目

编辑 `LedgerApp/Models.swift` 里的 `builtInExpense`、`builtInIncome`、`builtIn` 三个数组，push 后重新构建即可。
