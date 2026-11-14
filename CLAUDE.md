# 维护指南

这是 [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的个人长期维护版，主要加入了 iPhone Duo（折叠屏 iPhone）适配。下面的规则适用于所有改动，人和 AI 都一样。

本文件的维护规则在作者本机的 Claude 记忆里也有一份。修改其中任何一处时，两边要一起更新，保持一致。

## 分支

| 分支 | 用途 |
|---|---|
| `release` | 默认分支，长期主线。所有新改动都合并到这里 |
| `main` | 只同步上游，不放自己的改动 |

最初的 Duo 适配已冻结为标签 [`iphone-duo-v1`](https://github.com/ShionjiART/PiliPlus/releases/tag/iphone-duo-v1)，原来的 `feat/iphone-duo` 分支已删除。

## 标签

标签用来标记版本，不用来标记单个改动：

- 打出来给人用的安装包，打一个标签并发布 Release，标签名为 `duo-<上游版本号>-<序号>`，例如 `duo-2.2.0-1`。同一个上游版本每发一次序号加一，上游升级版本后从 1 重新开始。之前发布的 `iphone-duo-v1`、`iphone-duo-v2` 保持原名。
- 安装包文件名为 `PiliPlus_ios_<标签>_<日期>_<9 位提交号>_unsigned.ipa`，例如 `PiliPlus_ios_duo-2.2.0-2_20261115_835223c8e_unsigned.ipa`；同时附上同名的 `.sha256` 校验文件。文件名里的 `ios` 和提交号不能省：App 的「检查更新」靠 `ios` 找到 iOS 安装包，靠提交号判断已经装的是不是这一版。
- 没有合并就放弃、但想留着的分支，删除前先打标签 `archive/分支名`，否则它的提交会丢失。
- fork 时从上游复制来了约 150 个标签。自己的标签统一用 `iphone-duo-`、`duo-`、`archive/` 开头，以便区分。

## 每个改动的流程

1. 从 `release` 开一个短分支，按用途加前缀：`feat/`（功能）、`fix/`（修复）、`sync/`（同步上游）、`docs/`（文档）。
2. 多个改动同时进行时，每个都在自己的 git worktree 里做，不要在同一个文件夹里切换分支。
3. 改完后跑 `flutter analyze` 和相关测试。涉及界面的改动，在 iPhone Duo 模拟器上检查合上、展开和旋转；并行时每个任务新建自己的模拟器，不要共用。
4. 在本仓库开 PR 合并到 `release`，说明改了什么、为什么改、怎么测的。用户能感受到的功能和修复，在同一个 PR 里更新 [`FEATURES.md`](FEATURES.md)：新增一条或把对应的条目打勾，并附上 PR 链接。
5. 用 merge commit 合并，不用 squash。合并后删除分支（本地和 GitHub 上都删）；改动记录保留在 PR 页面，需要时可以从 PR 页面恢复分支。还要用的分支先保留，例如准备提给上游的分支。

## 提交

- 作者统一为 `sssakuya <moe@sssakuya.moe>`。
- 备注用中文，第一行带前缀：`功能:`、`修复:`、`同步:`、`文档:`。正文简短说明为什么改。
- 提交、PR 和评论里都不加 AI 署名（例如 `Co-Authored-By: Claude` 或 “Generated with Claude Code”）。

示例：

```text
修复: 折叠后页面状态丢失

旋转或折叠时安全区在 0 和非 0 之间变化，页面会被重建。
现在始终使用同一套结构。
```

## 同步上游

在 `sync/` 分支上把上游 `main` 合并进来，再按上面的流程合并到 `release`。只用 merge，不用 rebase，这样不需要强制推送。

和 Duo 无关的修复，可以从上游 `main` 开分支，方便以后提给上游；同时也合并到 `release`。给上游提 PR 前要先经过作者同意。

## 构建

- 本项目只能用打过补丁的 Flutter SDK 编译，补丁见 `lib/scripts/patch.ps1`。`pubspec.yaml` 锁定了具体的 Flutter 版本。
- 打过补丁的 SDK 和 pub 缓存要和其他项目分开放，不要改动其他项目共用的 SDK。
- 上游升级 Flutter 版本后，把单独的 SDK 切到新版本，再重新应用补丁。
- 在干净的构建目录里编译模拟器时，`flutter build ios --config-only` 可能要跑两次：第一次可能会在 `ios/Flutter/Generated.xcconfig` 里写入 `EXCLUDED_ARCHS[sdk=iphonesimulator*]=i386 arm64`，导致 arm64 模拟器编译失败。
- `macos/Flutter/` 下的 `.xcconfig` 会在编译时被自动修改，不要提交。

## 进度

- 相对原版新增的功能和修复，见 [`FEATURES.md`](FEATURES.md)。
- 正在移植的功能和完成情况，见 [Issue #2](https://github.com/ShionjiART/PiliPlus/issues/2)。每完成一项，在 Issue 里勾选并附上 PR 链接。
- 每个分支的用途记录在作者本机的 Claude 记忆里（分支记录），新建、合并或删除分支时更新。
