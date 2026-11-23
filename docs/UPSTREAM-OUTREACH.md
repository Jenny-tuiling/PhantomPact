# 给上游的沟通模板（issue / PR）

用途：告知原作者你做了一个本地 4 人版，问要不要合入。
**不要在 issue 里贴成品包或网盘链接**，只描述改动范围 + 你 fork 的 release 页。

---

## 方案 A：Issue（推荐先用这个）

标题：

```
[Feature] Local 4-player split-screen extension on top of v1.7.3
```

正文（英文，作者是英文母语仓库，附中文一段即可）：

```markdown
Hi — first, thanks for Phantom Pact; the local co-op path in 1.7.3 is what made this possible.

I built a local 4-player extension on top of **v1.7.3** and have been testing it on a single
machine with 4 controllers (multi-monitor, one PC — not networked co-op). Repo:
<https://github.com/<your-account>/PhantomPact> (branch `cn/four-player-local`, tag `cn-2026.11.22`)

What it changes:

- **Input routing**: per-player input routes for P2/P3/P4 (`native/four_route.hpp`,
  `native/party_input.hpp`), each pad keeps its slot across rebinds.
- **Party setup UI**: a WinForms setup page that binds/calibrates pads per player
  (stick recenter), picks skins, and launches through Steam. Lives in its own folder,
  nothing in the existing UI path is replaced.
- **AI takeover**: per-slot on/off for AI control of P2–P4 (hold L3+RT), survives
  restarts, plus a lock/recall/free-self key set on P1.
- **Revive / respawn**: revive-point corrections and a safer party respawn anchor.
- **Two skins added** (Zhu Bajie, Fengfeng) using the existing wardrobe pipeline.

Scope: ~[N] Lua files touched under `mod/PBZCoop/Scripts/`, ~[N] new native headers,
one new tool folder. Nothing removed; the online/relay path is untouched.

Two questions:

1. Is a local 4-player mode something you'd want upstreamed, or is it out of scope for
   this project? Either answer is fine — I'll keep publishing it as a fork either way.
2. If you do want it, would you prefer one PR or a series (input routing → setup UI →
   AI takeover → revive)? The setup UI is Windows/WinForms and may not fit your build
   pipeline, so I can split it out.

Known gaps on my side: the free-travel map still has cursor/target-selection issues with
multiple local players, and one cutscene transition zone is untested. I'm not claiming
those are fixed.

中文摘要：

在 v1.7.3 基础上做了单机本地 4 人（4 手柄、多显示器、同一台电脑）扩展：每人独立输入
路由、手柄绑定与摇杆归中校准的设置页、P2–P4 的 AI 托管开关、复活点修正，以及两个新皮肤。
在线/中继部分完全没动。想确认这个方向是否值得合入上游；如果不合，我会继续以 fork 形式
自行发布，不影响上游。
```

---

## 方案 B：Pull Request（作者说欢迎之后再用）

```powershell
cd E:\游戏补丁\PhantomPact-cn
git fetch upstream --tags
git rebase upstream/main          # 先对齐，冲突多在 mod/PBZCoop/Scripts 与 native/
git push --force-with-lease
```

开 PR 时：

- base：`yhsharaf/PhantomPact:main` ← compare：`<你的账号>:cn/four-player-local`
- 标题：`Local 4-player: per-player input routing, party setup UI, AI takeover`
- 描述：把方案 A 的正文精简成改动清单 + 测试方法（说明是 1 台机器 4 手柄实测，附 build 号 26367565）
- **只提源码**：不要带 `payload/`、`*.dll`、`*.exe`、ZIP。二进制走 Release。
- 如果 diff 太大，拆成 3–4 个 PR，第一个只放 `native/four_route.hpp` + `party_input.hpp`。

---

## 不该做的

- 不要在 issue 里要求作者“帮我发布/帮我打包/给我签名”。
- 不要用 `v1.7.3` 或 `v1.7.4` 这种上游 tag 名发自己的 Release，tag 用你自己的前缀（如 `cn-2026.11.22`）。
- 不要改包名冒充官方，也不要删掉 `原作者说明/` 和第三方许可文件。
