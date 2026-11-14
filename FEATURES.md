# 功能清单

这里列出本维护版相对 [原版 PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 新增的功能和修复。

- [x] 已完成，并已合入 `release`
- [ ] 进行中或计划中

原版本身的功能见 [README](README.md)。

## iPhone Duo 适配

第一版适配已冻结为 [`iphone-duo-v1`](https://github.com/ShionjiART/PiliPlus/releases/tag/iphone-duo-v1)。

- [x] 合上和展开时自动切换布局，旋转和开合都会跟着调整
- [x] 首页、动态、我的使用系统原生的 Liquid Glass 标签栏，并放进竖状态栏
- [x] 页面、播放器控件和直播间都避开竖状态栏
- [x] 左右切换标签时，下一页从竖状态栏下面滑进来（透过竖栏上的玻璃按钮能看到），停下后内容仍避开竖状态栏（[#42](https://github.com/ShionjiART/PiliPlus/pull/42)）
- [x] 合上时播放器底部的进度条铺满整行（摄像头只在竖栏顶部，挡不到），下面一排按钮仍避开竖栏，合上全屏也一样（[#35](https://github.com/ShionjiART/PiliPlus/pull/35)）。控件隐藏时的细进度条起初改成避开竖栏（[#24](https://github.com/ShionjiART/PiliPlus/pull/24)），后来改回铺满（[#35](https://github.com/ShionjiART/PiliPlus/pull/35)）
- [x] 视频页隐藏时间和 Wi-Fi，内容铺满竖状态栏的位置（合上和展开都是）
- [x] 展开后视频页右栏加宽，相关视频的 ⋮ 按钮不再被遮住
- [x] 动态流合上时单列、展开时双列，不再因为合上状态启动就一直是单列（[#23](https://github.com/ShionjiART/PiliPlus/pull/23)）
- [x] 保存评论和动态的图片不再比直板手机宽：最多 402pt，和普通 iPhone 一致（[#20](https://github.com/ShionjiART/PiliPlus/pull/20)）
- [x] 旋转或开合时页面不会被重置
- [x] 之前手动打开过「横屏适配」的用户，升级后仍保持打开
- [x] 修复真机合上时启动卡在启动画面
- [x] 视频页偶尔右侧留出空白（时间和 Wi-Fi 没隐藏）：每次都和系统重新同步竖状态栏状态，回到前台时重新确认（[#18](https://github.com/ShionjiART/PiliPlus/pull/18)）
- [x] 直接打开的页面也避开竖状态栏，修复通讯录页标签栏伸到竖栏下面（[#4](https://github.com/ShionjiART/PiliPlus/pull/4)）
- [x] 修复开启「改用侧边栏」后首页搜索栏和头像消失：iOS 26 起的 iPhone 由系统标签栏负责导航，这个设置不再生效并在设置里置灰（普通 iPhone 也适用）（[#19](https://github.com/ShionjiART/PiliPlus/pull/19)）
- [x] 合上时二级页面在竖状态栏显示返回键；首页等一级页面和视频页不显示，弹窗不影响（[#21](https://github.com/ShionjiART/PiliPlus/pull/21)）。页面左上角的返回键起初保留，后来去掉（[#28](https://github.com/ShionjiART/PiliPlus/pull/28)）
- [x] 一级页面的竖状态栏顶部放头像，以及搜索和私信的组合按钮，私信带未读角标；未登录时不显示私信，头像点了去登录；首页顶部的头像在 Duo 上去掉（[#22](https://github.com/ShionjiART/PiliPlus/pull/22)）
- [x] 视频页的底部弹窗（长按评论的菜单、分享、收藏、缓存、转发、播放器设置等）和页面一样铺满竖状态栏的位置，右边不再留出一条（[#25](https://github.com/ShionjiART/PiliPlus/pull/25)）
- [x] 动态详情页的点赞、评论、分享、转发放进竖状态栏，带简短的数量（1.2万、1千万、1.2亿）；发评论单独一个按钮放在最下面，代替页面上的悬浮按钮；底部操作栏保留（[#26](https://github.com/ShionjiART/PiliPlus/pull/26)）。后来顺序改为点赞、评论、转发（带数量）、分享（只有图标），按钮变矮，通话时也不会被收进 ⋯ 菜单（[#33](https://github.com/ShionjiART/PiliPlus/pull/33)）
- [x] Duo 上首页顶部的搜索栏、消息按钮和头像那一行去掉（都已在竖状态栏里），分区标签移到最上面（[#27](https://github.com/ShionjiART/PiliPlus/pull/27)）
- [x] 二级页面只保留竖状态栏里的返回键，页面左上角的去掉，标题和左边留出间距；竖状态栏的头像点了弹出账号切换，未登录时去「我的」页面登录（[#28](https://github.com/ShionjiART/PiliPlus/pull/28)）
- [x] 合上时首页、「我的」等页面顶部不再多出一段空白：状态栏在竖栏里时，不再给屏幕顶部留位置（[#31](https://github.com/ShionjiART/PiliPlus/pull/31)）
- [x] 在账号切换里选了匿名后，点竖栏头像仍弹出账号切换，可以切回原账号；一个账号都没有时才去「我的」登录。竖栏头像图片放大，留白收窄（[#32](https://github.com/ShionjiART/PiliPlus/pull/32)）
- [x] 动态详情页顶部不再空出一条：作者直接在最上面，往上滑过作者后顶栏才浮出来，标签栏停在顶栏下面（[#33](https://github.com/ShionjiART/PiliPlus/pull/33)）
- [x] 音乐详情页顶部也不再空出一条：歌曲卡片直接在最上面，往上滑过后顶栏才浮出来，评论栏停在顶栏下面（[#41](https://github.com/ShionjiART/PiliPlus/pull/41)）
- [x] 合上时视频页暂停后往上滑、播放器收成一条工具栏，右边的 ⋮ 不再被摄像头挡住：按钮和播放器控件一样避开左右安全区（[#40](https://github.com/ShionjiART/PiliPlus/pull/40)）
- [x] 移植 [Stasert](https://github.com/Stasert) 的竖栏导航等功能：能用的都已移植，其余几项决定不移植，逐项记录见 [#2](https://github.com/ShionjiART/PiliPlus/issues/2)

## 播放

- [x] iOS 支持 AV1 硬解，更省电、发热更小；不支持的设备自动用软解（[#6](https://github.com/ShionjiART/PiliPlus/pull/6)）
- [x] iOS 锁屏或切到后台再回来后，自动恢复硬解（[#5](https://github.com/ShionjiART/PiliPlus/pull/5)）
- [x] iOS 上 HDR 和杜比视界视频改用系统播放器播放，画面和官方客户端一致，不再过曝（[#12](https://github.com/ShionjiART/PiliPlus/pull/12)）
- [x] 可选所有视频都用系统播放器（实验性）（[#12](https://github.com/ShionjiART/PiliPlus/pull/12)）
- [x] 系统播放器支持画中画、截图和字幕（[#13](https://github.com/ShionjiART/PiliPlus/pull/13)）
- [x] 修复部分 HDR 真彩、杜比视界视频无法用系统播放器播放，或在播放信息里显示成 SDR（[#13](https://github.com/ShionjiART/PiliPlus/pull/13)）
- [x] 离线缓存的 HDR、杜比视界视频也用系统播放器播放（[#36](https://github.com/ShionjiART/PiliPlus/pull/36)）
- [x] 「所有视频」模式下尽量都用系统播放器（包括普通画质的 HEVC 和离线缓存）；系统播放器加载超时或没有画面时自动切回内置播放器（[#38](https://github.com/ShionjiART/PiliPlus/pull/38)）
- [x] 修复打开视频偶尔整块黑屏或有声音没画面（原版也有，见 [bggRGjQaUbCoE/PiliPlus#3246](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3246)）：被盖住或已关闭的视频页不再抢用播放器，初始化失败时显示封面可点击重试（[#16](https://github.com/ShionjiART/PiliPlus/pull/16)）

## 离线缓存

- [x] 修复网络不好时缓存「瞬间完成」但视频不完整：下载完核对文件大小，断了自动续传，续传多次仍不完整就标为失败；续传时换了视频流会从头下载（[#15](https://github.com/ShionjiART/PiliPlus/pull/15)）

## 投屏

- [x] 修复 iOS 投屏一直「搜索设备失败」、不弹局域网授权（[#9](https://github.com/ShionjiART/PiliPlus/pull/9)）
- [x] 支持 AirPlay 投屏，和现有的局域网投屏并存（[#14](https://github.com/ShionjiART/PiliPlus/pull/14)）

## 关于和更新

- [x] 关于页的源码、提交、问题反馈链接和检查更新改用本仓库：不再提示下载没有 iPhone Duo 适配的原版安装包；刚装上的版本也不会被当成有新版本（[#44](https://github.com/ShionjiART/PiliPlus/pull/44)）

## 开发

- [x] 每次提 PR 时自动检查代码并运行测试（[#8](https://github.com/ShionjiART/PiliPlus/pull/8)）
- [x] 修复原版中 2 个一直失败的测试（[#7](https://github.com/ShionjiART/PiliPlus/pull/7)）
- [x] 维护指南 [`CLAUDE.md`](CLAUDE.md)（[#3](https://github.com/ShionjiART/PiliPlus/pull/3)、[#10](https://github.com/ShionjiART/PiliPlus/pull/10)）

## 已提交给原版

- 切回前台后自动恢复硬解：[bggRGjQaUbCoE/PiliPlus#3584](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3584)
- iOS 支持 AV1 硬解（询问是否采用）：[bggRGjQaUbCoE/PiliPlus#3585](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3585)

## 本地定制整合（v3 + v22，待实机确认）

- 在 v3 `duo-2.2.0-1` 上整合 v22 的页面与竖栏交互，方向逻辑完全采用 v3；竖栏符号、头像和私信入口优先沿用 v3。
- 二级页隐藏三项主导航；视频页返回与 Home 组合、全屏独立；外屏按钮放在视频下方并跟随系统锚点避让。
- 内屏非全屏状态图标常驻；外屏播放展开隐藏、暂停或收起显示；全屏均隐藏。按钮与状态图标分开管理。
- 普通 Duo 页面顶部 12pt，内容到竖栏 4pt；外屏视频顶部无额外占位，全屏无竖栏安全区。
- 评论入口为右下角常驻液态玻璃按钮；回顶独立；路由侧滑期间边缘透明且保留页面状态。
- 可选固定内屏双栏；默认使用 v3 自适应布局，窗口宽度不足 820pt 时回退，避免竖拿时视频过窄。
- 保留 v3 的系统播放器、HDR/杜比、AV1 硬解/恢复、AirPlay、下载完整性与更新源修复。
- R3 已提交至 Stasert/PiliPlus；Release 发布准备中。

### R2 本地测试修复

- 外观新增「竖栏内容边距」：0–32pt，默认 4pt，保存后即时生效；全屏不受影响。
- 修复首页推荐页和横向卡片加载骨架叠加旧右侧留白的问题，页面外侧统一使用可调边距。
- 竖栏查看评论、回复和发表评论图标向上微调 1pt；按钮点击区域、数量文字、动画和页面归属保持不变。
- 修复外屏动态详情评论区的灰白色错误占位层：移除刷新指示器外多余的 Obx，刷新指示器按 v3 自行监听状态。


### R3 本地测试修复

- 排查动态首页、UP 动态、动态话题、UP 搜索动态、我的回复的列数判断：改用页面当前视口并还原 UI 缩放，避免读取全局第一视图的过渡尺寸；列数不再缓存过期折叠策略，加载骨架与内容统一规则。
- 评论编辑器、弹窗和键盘出现时临时隐藏底层竖栏按钮，编辑器和键盘均关闭后恢复，避免操作按钮挤压堆叠。
- 全屏退出和页面重新出现时核对系统实际竖栏；系统重建并丢失按钮时复用原控件恢复，修复仅比较缓存而无法重建的问题；离开视频页清除竖栏残留的全屏状态。
- v3 方向、系统播放器和 HDR 播放实现保持原样。偶发双栏的实机触发条件及 HDR 实际播放链路仍需测试版验证；尚未上传 GitHub。


### 本仓库发布准备

- 关于页源码、当前提交、更新记录及检查更新统一改用 Stasert/PiliPlus，主线分支为 main。
- 保留 release v3 来源说明；发布安装包内记录实际提交号，文件名带相同提交号，避免重复提示当前版本更新。
