# 轻镜录屏 · AI 上手助手

> 装好轻镜，交给你的 AI，它一步一步带你用起来。

一个 AI Skill（Claude Code、Codex 等通用）。装好 Mac 截图录屏软件「轻镜录屏 LightRecord」以后，把它交给你的 AI，AI 会像坐在你旁边一样带你：检查电脑、第一次打开、打开权限、准备字幕要用的语音模型、截第一张图拖进聊天框、录第一段带字幕的讲解视频。

**免费公开，禁止商用，按现状提供。作者不提供售后、安装协助或一对一答疑。** 遇到问题，把屏幕上的提示交给你的 AI，按 SKILL.md 里的「出错时怎么办」排查。

觉得哪里不顺手，就让你的 AI 在这个基础上改，改成适合你自己的样子。

轻镜录屏官网：https://lightrecord.nativeailab.cn/

## 怎么用

**用 Claude Code、Codex 这类能在 Mac 上运行命令的 AI（推荐）**

1. 下载这个仓库：点页面上的「Code → Download ZIP」，或者直接下载 https://github.com/vickysy/lightrecord-ai-onboarding/archive/refs/heads/main.zip ，双击解压。
2. 打开 AI，把解压出来的文件夹拖进对话框，跟它说：

   > 请读这个文件夹里的 SKILL.md，按它一步一步带我用轻镜录屏。

3. AI 要运行命令、联网下载字幕模型时，会先问你，同意就行。

**想以后随时叫出来：装成 skill**

```bash
# Claude Code
git clone https://github.com/vickysy/lightrecord-ai-onboarding.git ~/.claude/skills/lightrecord-onboarding
# Codex
git clone https://github.com/vickysy/lightrecord-ai-onboarding.git ~/.codex/skills/lightrecord-onboarding
```

之后说一句「带我用轻镜」就行。

**网页版、手机上的 AI**

把 SKILL.md 发给它（上传文件，或者复制粘贴全文）。它不能替你运行命令，只能口头教你。字幕模型先在轻镜里点「下载语音模型」；下不下来，再用浏览器下载，然后在轻镜里点「导入模型」。

## 它会做什么，不会做什么

会：

- 检查 macOS 版本（需要 15 或以上）、芯片、轻镜装在哪、版本够不够新、磁盘空间。
- 带你过第一次打开：确认安装包来自官网，再在「隐私与安全性」里点「仍要打开」；打开屏幕录制、麦克风、摄像头权限。
- 准备讲解字幕用的语音模型（约 488 MB）：按顺序试魔搭社区、hf-mirror、Hugging Face，断了接着下，下完核对大小和 SHA-256。
- 带你截第一张图拖进聊天框，录 20 秒讲解，在字幕检查页改错字，导出带字幕成片。
- 出错时一项一项排查：下载慢、校验不通过、权限没开、录不到声音。

不会：

- 替你点系统设置里的「仍要打开」和权限开关，替你输入密码。
- 关闭或绕过 Mac 的安全保护。
- 上传你的截图和录屏。想让它读识别出来的字幕帮你找错字时，它会先问你同意。

讲解字幕从轻镜 1.14 开始才有。装的是更早的版本，截图和录屏照常能用，字幕的步骤先跳过。

## 文件

- `SKILL.md`：给 AI 读的说明，一步一步带用户操作。
- `scripts/lightrecord.sh`：检查电脑、下载和核对字幕模型的脚本。只用 macOS 自带的工具，不改系统设置，不要管理员密码，只往 `~/Library/Application Support/LightRecord/Speech/` 里放模型文件。

本仓库不包含语音模型。模型是 whisper.cpp 格式的 Whisper small 多语言版（`ggml-small.bin`），由脚本或轻镜从公开地址下载。

## 许可

© 2026 木妈AIdea。采用 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh-hans)（知识共享 署名-非商业性使用-相同方式共享 4.0 国际）许可，完整条款见 [LICENSE](LICENSE)。

- 可以：免费使用，自己修改，把改过的版本分享给别人。
- 要求：注明来自木妈AIdea，并附上本仓库链接；分享改过的版本时，也用同样的许可。
- 不可以：用于商业目的，比如拿去售卖，或者放进收费的课程、产品、服务里。

## 作者

木妈AIdea · [mumaaidea.com](https://mumaaidea.com)
