# Phantom Pact — 小朋友快乐玩mod（本地 4 人扩展）

玩家第三方修改版，基于 [Phantom Pact](https://github.com/yhsharaf/PhantomPact) **v1.7.3**。
**同一台电脑本地 2–4 人（多手柄 / 多显示器），不是跨电脑联网联机。**

- 上游基线：`yhsharaf/PhantomPact` tag `v1.7.3`（2026-11-13）
- 本版版本号：`2026.11.22-test`
- 验证环境：Steam build `26367565`
- 成品下载：见本仓库 **Releases** 页（ZIP 整包，含安装器与卸载器）

> 本仓库只放**源码**。`payload/`、`*.dll`、`*.exe` 等运行载荷不进版本库，一律走 Release 附件。

## 与上游 v1.7.3 的差异

- 2/3/4 人本地合作，P2–P4 独立输入路由（`native/four_route.hpp`、`native/party_input.hpp`）
- 设备设置页（WinForms）：手柄绑定、摇杆归中校准、皮肤选择、底座切换，位于 `tools/four-player-setup/`
- AI 托管：P2–P4 分槽开关，重启后保持；1 号锁定/召回/脱困
- 复活点修正与安全复活落点
- 新增皮肤：猪八戒、枫枫（走既有衣柜管线）
- 在线 / 中继路径未改动

## 目录

    mod/PBZCoop/Scripts/          本地合作核心（改自上游 + 新增 localfour / party_ai / party_controls 等）
    mod/PBZPartyPower/Scripts/    队伍能力扩展
    mod/PBZWardrobe/Scripts/      皮肤与演出模块
    native/                       原生层（four_route / party_input / screens / main_dll）
    native/tests/                 原生层单元测试（test_*.cpp）
    tools/four-player-setup/      设备设置页（C# WinForms）
    docs/                         发布说明、上游沟通模板、致谢

## 构建

沿用上游工具链：`tools/build-native.ps1`（原生层）、`.NET Framework csc`（设置页）。
完整打包与安装流程见 `docs/RELEASE-cn-2026.11.22.md`。

## 已知问题

- 穿行地图在多人下仍有光标 / 选点问题，未修复。
- 庞镇切图未实测通过；同时喝药归属、缺席路由、安全复活落点仍有风险。
- 猪八戒、枫枫资源与构建已检查，游戏内全部动作与场景尚未验收。

## 致谢与声明

- 上游 **Phantom Pact** by yhsharaf — https://github.com/yhsharaf/PhantomPact
- **UE4SS**（MIT）— 许可文本随成品包提供
- 玩家第三方修改版，与原作 S-GAME 及上游作者无隶属或背书关系，非官方作品。上游仓库当前未附许可证文件；本仓库保留全部上游来源说明，请勿移除后二次分发。
