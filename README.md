# 记账 · 个人账本

一个只服务于一人的 iOS 记账 App，SwiftUI 原生开发，数据全部存本机，不联网、不上传。

## 功能

- **记一笔**：支出 / 收入、项目、金额、支付方式、日期时间、备注
- **明细**：按时间倒序流水，左滑删除
- **统计**：本月支出 / 收入 / 结余，按项目、按支付方式的支出排行
- **设置**：增删改支出项目、收入项目、支付方式；一键恢复预置

## 预置项目

- 支出：早餐、午餐、晚餐、宵夜、麻将、香烟、饮料、信用卡、花呗、借呗、京东白条、京东金条、分付
- 收入：工资、货款
- 支付方式：微信、支付宝、银行卡、现金

以上全部可在「设置」中自行增删改。记过的账以文字保存，删除项目不会丢失历史记录。

## 数据

数据以 JSON 存于 App 沙盒的 `Documents/ledger_data.json`。**卸载 App 数据会消失**，目前无导出功能（按需求未做备份）。

## 如何构建 IPA

源码本身不能直接在 Windows 上编译 iOS 包，构建交给 GitHub Actions：

1. 每次 `git push` 到 `main` 分支会自动触发构建；也可在仓库 Actions 页手动点 **Run workflow**。
2. 构建完成后，进入该次运行的页面，在底部 **Artifacts** 区下载 `LedgerApp-TrollStore`（一个 zip）。
3. 解压得到 `LedgerApp-TrollStore.ipa`，用 TrollStore 安装。

构建流程：XcodeGen 生成工程 → xcodebuild 编译未签名 app → `ldid -S` 伪签名 → 打包 ipa。伪签名正是 TrollStore 所需要的形式，无需开发者账号。

## 修改内置项目

编辑 `LedgerApp/Models.swift` 里的 `builtInExpense`、`builtInIncome`、`builtIn` 三个数组，push 后重新构建即可。
