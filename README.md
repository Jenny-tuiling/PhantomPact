# 小朋友快乐玩mod：《影之刃零》本地 2–4 人合作

<p>
  <img alt="version" src="https://img.shields.io/badge/%E7%89%88%E6%9C%AC-2026.11.22--test-blue">
  <img alt="base" src="https://img.shields.io/badge/%E5%9F%BA%E4%BA%8E-Phantom%20Pact%20v1.7.3-lightgrey">
  <img alt="players" src="https://img.shields.io/badge/%E7%8E%A9%E5%AE%B6-2--4%20%E4%BA%BA%E6%9C%AC%E5%9C%B0-brightgreen">
  <img alt="platform" src="https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Windows%20%C2%B7%20Steam-blueviolet">
  <img alt="status" src="https://img.shields.io/badge/%E7%8A%B6%E6%80%81-%E8%B7%A8%E6%9C%BA%E5%99%A8%E6%B5%8B%E8%AF%95%E7%89%88-orange">
</p>

简体中文 | [English](#english)

这是《影之刃零》（**Phantom Blade Zero**，S-GAME）的**同一台电脑本地 2–4 人合作**扩展，基于粉丝联机模组
[Phantom Pact](https://github.com/yhsharaf/PhantomPact) **v1.7.3** 修改而来。

**不是跨电脑联网联机**——四个人坐在同一台机器前，各自一个手柄，用扩展显示器分屏游玩。
上游 Phantom Pact 的线上联机、PvP、PvPvE 全部保留原样，本分支只动本地多人这一块。

**下载：**[最新版本](https://github.com/Jenny-tuiling/PhantomPact/releases) ·
**安装：**[安装与游玩](#快速开始) ·
**与上游的差异：**[对比 v1.7.3](https://github.com/Jenny-tuiling/PhantomPact/compare/v1.7.3...cn/four-player-local) ·
**上游项目：**[yhsharaf/PhantomPact](https://github.com/yhsharaf/PhantomPact)

## 这是什么

《影之刃零》原本没有本地多人。上游 Phantom Pact 做了线上双人联机，并在 1.7.x 试验了本地分屏；
本分支把本地这条路推到 **2/3/4 人**：每人一套独立输入、一次手柄绑定、一个复活点，AI 可以接管缺席的队友。

同一个包里带两个底座，安装后在设置页切换（切换前必须退出游戏）：

| 底座 | 内容 | 用途 |
|---|---|---|
| `local`（默认安装） | 1.7.3 + 最近两轮本地多人修复 | 日常游玩 |
| `stable` | 稳定版 1.7.3 + 既有补丁 | 出问题时回退 |

## 功能

**本分支新增（本地多人）**

- 2 / 3 / 4 人同机合作，P2–P4 各自独立的输入路由，四套手柄互不串键
- 手柄绑定与摇杆**归中校准**：设备归属会保持，换设备点“更换手柄”，摇杆漂移点“归中校准”（松手约 4 秒）
- **AI 托管**：队友按 L3+RT 4 秒开关；只主动关闭或重启游戏才退出托管，中断后会继续。2/3/4 号可各自独立开关
- 1 号专用：L3+RT 锁定/解锁队友操作，R3+LT 召回全部队友，L3+R3 安全脱困
- 复活点修正与安全复活落点；唯一门交互拥有者、嵌套回调修正、控制器归还失败重试
- 皮肤：原始魂、辰辰、小宝、猪八戒、枫枫（不含帝皇、叶瞬光、Seed）
- 设置页重写（C# WinForms）：多人开关、人数与输入组合、逐人绑定/校准、选皮肤、设备检查、启动游戏
- 游戏工具：全员无敌 + 10 倍伤害（每次启动默认关闭）
- 安装器 / 卸载器：装前备份到游戏根目录 `FourPlayerBackups`，安装后被改动的文件不覆盖

**上游 Phantom Pact v1.7.3 已有（本分支未改动）**

- 线上双人联机：共享敌人、首领血条、战利品与尘、钟旁会合
- PvP 决斗 / 死斗 / PvPvE（F6）
- 游戏中 F5 联机面板、F4 分屏面板
- 中文 / English / العربية 三语界面

## 快速开始

1. 在 Steam 正常安装并**启动过一次**《影之刃零》，确认版本为 **build 26367565**（不匹配时安装器会停止，别绕过）。
2. 保存并退出游戏，关掉所有设备设置页。
3. 把 Release 里的 ZIP **完整解压**到普通文件夹，不要直接在压缩包里运行。
4. 双击 `Install.cmd`，选择游戏根目录（含 `platform` 与 `ProjectPBZ` 那层，Steam → 属性 → 已安装文件 → 浏览）。
5. 等“安装完成”。安装器会备份原文件，并在桌面创建「小朋友快乐玩mod - 多人设备设置」快捷方式。
6. 打开该快捷方式：勾选开启多人，选 2/3/4 人与输入组合；显示器先在 Windows 设成**扩展显示**。
7. 各玩家依次按自己手柄 **A** 加入；绑定会保持，不必每次重绑。
8. 选皮肤 → 完成设备检查 → 点击启动。游戏从 Steam 正常启动，进自己的存档。

## 按键

`L3`/`R3` = 按下左/右摇杆，`LT`/`RT` = 左/右扳机。触发后松开再按。

| 操作 | 按键 | 谁 |
|---|---|---|
| AI 托管开关 | 按住 L3 + RT 4 秒 | 队友（各自） |
| 锁定 / 解锁队友操作 | 按住 L3 + RT 3 秒 | 1 号 |
| 召回全部队友 | 按住 R3 + LT 3 秒 | 1 号 |
| 安全脱困（其他人回到 1 号身边） | 按住 L3 + R3 3 秒 | 1 号 |

完整键鼠操作与恢复视角说明在设置页「按键说明」和「游戏工具」。

## 已知问题

- 穿行地图在多人下仍有**光标 / 选点问题**，未宣称修复。
- 庞镇切图尚未实测通过；同时喝药归属、缺席路由、安全复活落点仍有风险。
- 猪八戒、枫枫的资源和构建已检查，游戏内**全部动作与场景尚未验收**。
- AI 在制作机上实测通过，新机器 / 其他游戏版本需自行验证。
- 本包**不含作者存档、手柄绑定和校准数据**，请用自己电脑的备份存档。

## 版本与兼容

- 基础版本：Phantom Pact **v1.7.3**；上游已到 v1.7.4 / v1.7.5，**不要拿本包的脚本混装 1.7.5**
- 游戏：Steam **build 26367565** 已验证；其他版本安装器会拦
- 与其它版本的多人模组**不要混装**，已装旧版请先按原包方式卸载
- 安装前建议备份 `ProjectPBZ/Saved/SaveGames`

## 卸载

退出游戏与设置页，双击 `Uninstall.cmd`，选择同一游戏根目录。恢复安装前文件并移除桌面入口；备份在 `FourPlayerBackups`。
卸载器遇到安装后被改动的文件会停止并提示路径（保护行为），按提示处理，不要强删备份。保留该解压目录直到卸载完成。

## 基本原则

- **不绕过 DRM。** 不碰 Denuvo，不修改游戏可执行文件；一切都通过 UE4SS 加载，运行在正版游戏之内。
- 每位玩家都需要拥有自己的《影之刃零》。
- 本仓库只有源码；**不包含任何游戏文件或素材**。

## 仓库结构

    mod/PBZCoop/Scripts/          本地合作核心（改自上游 + localfour / party_ai / party_controls 等）
    mod/PBZPartyPower/Scripts/    队伍能力扩展
    mod/PBZWardrobe/Scripts/      皮肤与演出模块
    native/                       原生层（four_route / party_input / screens / main_dll）
    native/tests/                 原生层单元测试
    tools/four-player-setup/      设备设置页（C# WinForms）
    docs/                         发布说明、上游沟通草稿

本分支 = 上游 `v1.7.3` + 1 个提交（见 [对比](https://github.com/Jenny-tuiling/PhantomPact/compare/v1.7.3...cn/four-player-local)）。
构建产物（DLL、安装器、皮肤资源）不进版本库，只作为 Release 附件分发。

## 致谢

- **[yhsharaf](https://github.com/yhsharaf)**：Phantom Pact 本体。本分支的全部基础都来自他——本地分屏、输入系统、
  皮肤管线、三语界面：https://github.com/yhsharaf/PhantomPact
- **Vercadi**：制作了 UE4SS for Phantom Blade Zero，让这款游戏的模组制作成为可能
- **UE4SS 团队**（[RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)）：运行时框架，MIT
- 皮肤管理器组件与第三方许可：见成品包内 `PartySetup/第三方致谢.txt`、`PartySetup/第三方许可/`、`原作者说明/`
- **S-GAME 及《影之刃零》开发者**：游戏本体

*玩家自制修改版，非官方作品，与 S-GAME 及上游作者无隶属或背书关系。喜欢的话，请先支持原作者。*

## English

Local 2–4 player co-op for **Phantom Blade Zero** (S-GAME) on **one machine** — multi-pad, multi-monitor.
Built on [Phantom Pact](https://github.com/yhsharaf/PhantomPact) **v1.7.3** by yhsharaf; this branch is
that tag plus one commit. Not networked co-op: the upstream online/relay path is untouched.

Adds per-player input routing for P2–P4, a WinForms pad bind/calibrate setup page, per-slot AI takeover,
revive-point fixes, and two skins. Installer ships as the release ZIP (Windows, Steam build 26367565).
Unofficial fan build; not affiliated with S-GAME or the upstream author. Binaries are release assets only —
this repository holds source.
