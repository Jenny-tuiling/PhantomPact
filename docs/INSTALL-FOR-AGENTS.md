# 给 AI 助手的安装指令（直接复制这段）

> 本文件是给「让 AI 帮我装这个 mod」时用的粘贴模板。目的是避免 AI 去 clone 仓库、
> 跑上游 `tools/` 脚本，或者从上游 Phantom Pact 的 1.7.5 装错版本。

---

请按下面执行，**不要做清单以外的事**：

1. 只下载这一个文件（不要 `git clone`，不要用 GitHub 的 Download ZIP）：

   ```
   https://github.com/Jenny-tuiling/PhantomPact/releases/download/cn-2026.11.22-r1/PBZ-KidsCoop-4P-2026.11.22-r1.zip
   ```

2. 校验大小与 SHA256（不匹配就停下来，不要继续）：

   ```
   大小     21,116,482 字节
   SHA256   60def7bf35a2c53baeb3009db37bf0d47628d80d9ed05c6731f286a02879b3e6
   ```

   PowerShell：`Get-FileHash .\PBZ-KidsCoop-4P-2026.11.22-r1.zip -Algorithm SHA256`
   Linux/macOS：`sha256sum PBZ-KidsCoop-4P-2026.11.22-r1.zip`

3. 解压到一个普通文件夹（不要解压进游戏目录，不要在压缩包里运行）。

4. 确认游戏根目录：包含 `platform` 和 `ProjectPBZ`，并且 `platform\steam\PBZ.exe` 存在。
   游戏必须是 Steam **build 26367565**（安装器会自己校验 `PBZ.exe` 的 SHA256）。

5. 退出游戏与所有设置页后，在该文件夹运行：

   ```
   Install.cmd        （或在 PowerShell 里：powershell -ExecutionPolicy Bypass -File .\Install.ps1）
   ```

   按提示选择游戏根目录。看到「安装完成」即可。

6. 安装完成后，桌面会出现「小朋友快乐玩mod - 多人设备设置」快捷方式。

## 绝对不要做的事

- ❌ `git clone` 本仓库，或下载 GitHub 的 "Download ZIP"（那是源码，不是安装包）
- ❌ 运行仓库里 `tools/` 下的任何 `.ps1`（那是上游 Phantom Pact 的开发脚本，装不全）
- ❌ 从 `yhsharaf/PhantomPact` 或 Nexus 装 1.7.4 / 1.7.5 —— 本包基点是 **1.7.3**，混装会坏
- ❌ 在已有其它版本多人模组的机器上直接覆盖安装（先按原包方式卸载）
- ❌ 修改 `payload\` 里的任何文件后再安装（安装器会校验 686 个文件的 SHA256）

## 装完之后

- 打开桌面快捷方式 → 勾选「开启多人」→ 选 2/3/4 人 → 各玩家按手柄 A 加入 → 选皮肤 → 启动
- 显示器先在 Windows 设置成「扩展显示」
- 出问题先看：`platform\steam\ue4ss\Mods\PBZCoop\local_base_error.txt` 与 `ue4ss\UE4SS.log`
- 卸载：双击同一文件夹里的 `Uninstall.cmd`，选同一个游戏根目录
