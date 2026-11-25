# 小朋友快乐玩mod · 2026.11.25 安装指南

[下载完整安装包](https://github.com/Jenny-tuiling/PhantomPact/releases/download/cn-2026.11.25-clean/PBZ-KidsCoop-4P-2026.11.25-clean.zip) · [版本说明](https://github.com/Jenny-tuiling/PhantomPact/releases/tag/cn-2026.11.25-clean) · [首页与已知问题](README.md)

同一台 Windows 电脑、本地 2–4 人、多显示器合作。基于 PhantomPact v1.7.3。无需 GPT 或开发工具。

1. 游戏需为 Steam build **26367565**，正常启动过游戏。版本不匹配时停止，不要绕过检查。
2. 备份自己的 `ProjectPBZ/Saved/SaveGames`，退出游戏和全部设置页。装过其他多人版本的电脑先按原包方式卸载。
3. 完整解压下载的 ZIP，双击 **Install.cmd**，选择包含 `platform` 和 `ProjectPBZ` 的 PBZ 游戏根目录。
4. 安装成功后桌面自动创建 **小朋友快乐玩mod - 多人设备设置** 快捷方式。
5. 显示器设为扩展显示；设置页开启多人，选 2/3/4 人及输入组合。不启用多人则为单人。
6. 各玩家依次按手柄 **A** 加入，已绑定设备不必每次重新绑定。断线重连保持归属。换设备用“更换手柄”。
7. 摇杆偏移时，在玩家卡片顶部点 **归中校准**，松开摇杆约 4 秒。换手柄先恢复默认再校准。
8. 选择皮肤，完成设备检查，启动并进入自己的存档。

包内含完整补丁、对应源码、安装卸载器和逐项测试方法。不包含游戏本体、个人存档和个人设备配置。外观为魂主角、辰辰、小宝、猪八戒、枫枫。

默认本地测试底座；退出游戏后可在游戏工具切换“1.7.3＋既有补丁”。不要混装其他版本文件。GitHub 的 Source code ZIP 是仓库源码，不是完整安装包。

## 校验

文件：`PBZ-KidsCoop-4P-2026.11.25-clean.zip`  
大小：**20,410,963 字节**  
SHA256：`587042642b5105d97f7a20b1a69b67c4a011311ebce414cbda5220dce13c2700`

## 卸载

退出游戏和设置页；若切换过底座，先切回安装时的本地底座。运行原解压目录的 **Uninstall.cmd**，选择同一游戏目录。修改过的文件会受到保护并停止卸载；保留当前文件和 `FourPlayerBackups` 备份再核对。

## 已知限制

这是清理测试版和回退基线，未包含被撤回的队友复活输入实验补丁。队友复活仍可能打断 1 号动作；多人穿行地图光标、选点和部分切图流程仍需测试。安装验证通过不等于全地图或所有电脑稳定性保证。完整说明见首页和包内测试文档。

## English

Download the complete installer ZIP linked above, extract it, close the game and setup, run **Install.cmd**, and choose the PBZ root directory. The installer creates a desktop shortcut. Requires Steam build **26367565**. Configure extended monitors, 2–4 players, controllers and skins in the setup app. Run **Uninstall.cmd** from the retained extracted package to uninstall. The GitHub source ZIP is not the complete installer. Read the known limitations on the homepage before testing.