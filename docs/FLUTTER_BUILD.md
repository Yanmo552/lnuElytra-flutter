# 编译 / 开发笔记（Flutter 多学校版）

## 1. 环境清单（本机已验证）

| 组件 | 版本/位置 | 说明 |
|---|---|---|
| Flutter | 3.44.8 stable，`C:\flutter` | 已加入 PATH（User） |
| Dart | 3.12.2（随 Flutter） | |
| Rust | 1.96.0 **MSVC** | `rustup toolchain list` 必须只剩 `stable-x86_64-pc-windows-msvc` |
| Visual Studio | 2026 Community（`C:\Program Files\Microsoft Visual Studio\18\Community`） | 含 C++ 桌面开发 + Win10 SDK |
| flutter_rust_bridge_codegen | 2.13.0-beta.5 | `cargo install` 安装 |

国内镜像（必须设置，否则 pub.dev / storage.googleapis.com 连不上）：
```
PUB_HOSTED_URL=https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

## 2. 踩过的坑（重要）

### 2.1 项目路径不能含中文
cargokit 的 `run_build_tool.cmd` 用 `echo > pubspec.yaml` 生成临时 pubspec（含 path 依赖的绝对路径），
中文路径（如 `C:\Users\郑\Desktop\刷课网站逆向\...`）会被按 GBK 写入，Dart 按 UTF-8 解析直接失败：
```
Failed to decode data using encoding 'utf-8', path = '.\pubspec.yaml'
```
**解决**：把整个 Flutter 项目放到纯 ASCII 路径（本机用 `C:\lnu_elytra`）。

### 2.2 默认 Rust 工具链必须是 MSVC
本机曾同时装有 `stable-x86_64-pc-windows-gnu` 和 `stable-x86_64-pc-windows-msvc`。
cargokit 解析 `rustup run stable` 时取 `rustup toolchain list` 的**第一个**匹配 `stable-` 前缀的工具链，
GNU 排在前面就会用 GNU 工具链去编 MSVC target，随后报：
```
error calling dlltool 'dlltool.exe': program not found
```
**解决**：`rustup toolchain uninstall stable-x86_64-pc-windows-gnu`，只留 MSVC。

### 2.3 首次 flutter --version 卡住
首次运行会 `pub upgrade` flutter 工具，连不上 pub.dev 会一直重试。设置镜像即可。

## 3. 多学校 Rust 桥接

- 核心代码：`rust/core/`（lnuElytra 0.0.10 + 学校扩展）
- 桥接层：`rust/core/src/flutter.rs`（FClient，`#[cfg(feature="__flutter")]`）
- 学校扩展方法（对比上游新增）：
  - `switch_tab(xkkz_id)` —— 切换选课标签页
  - `select_course_subclass(course_id, course_do_id, kcmc, xkkz_id)` —— 子教学班 V1（通用）
  - `select_course_subclass_v2(jxb_id, do_jxb_id, jxbzls)` —— 子教学班 V2（丽江专用端点）
  - `fetch_subclass_ids(do_jxb_id)` —— 获取子教学班 ID
  - `cookies()` —— 读取当前会话 Cookie（自动重登用）
- `Course` 新增字段：`kcmc`（课程名）；`Jxb` 新增字段：`jxbmc`（完整教学班名）

改完 `flutter.rs` 后必须重新生成绑定：
```
flutter_rust_bridge_codegen generate
```

## 4. 学校标签（xkkz_id）对照

### 丽江师范学院 `http://newjw.lj-edu.cn/jwglxt`
| 标签 | xkkz_id |
|---|---|
| 板块课(大学体育3（本科）) | 54FC1FF9A3362073E06371D2A8C0AD3A |
| 板块课(本科班艺术课程) | 54FB211AA28C06F3E06370D2A8C08E99 |
| 板块课(公共艺术课程（2025版）) | 54FC1FF9A35A2073E06371D2A8C0AD3A |
| 板块课(大学体育3) | 54FC39B26F3B2436E06371D2A8C0EF8F |
| 通识选修课 | 54FB211AA25206F3E06370D2A8C08E99 |
| 专业选修课 | 54E788F21E323231E06370D2A8C01FAA |

### 其他学校
- 岭南师范：`http://jw.lingnan.edu.cn`（无标签）
- 山东青年政治学院：`https://jw.sdyu.edu.cn/jwglxt`（无标签）
- 广州商学院：`http://jwxt.gcc.edu.cn`（无标签）

## 5. 抢课流程（自动监控）

1. 登录（账密或 Cookie）→ 自动保存 Cookie
2. 添加预设课程（按志愿顺序），设置最多选 N 门 / 并行或顺序 / 轮询间隔 ms / 目标标签
3. 点「开始监控」：
   - `init()` 轮询直到选课开放（`NotyetStarted` = 未开放，继续等；登录失效 → 自动用 Cookie 重登）
   - 开放后每轮：按志愿解析课程（多标签学校自动遍历标签）→ 精确匹配 `-XXXX` 后缀教学班 → `select_course`
   - 返回「该教学班有子教学班未选」→ 自动走 V2 → V1 子班选课
   - 返回「对不起，当前未开放选课」→ 继续轮询
   - 返回「超过…」→ 判定已达上限，放弃该课
4. 会话失效（LoginFailed/CookieError）→ 自动重登，不中断监控

## 6. 测试账号（仅用于开发验证，勿外传滥用）

- 丽江师范：`202543401056 / lili111213`（或 `202530412016 / xyw200724`）
- 山东青年：`202502710104 / Qwh17238～`
- 岭南师范：`202401764147 / ZHANGabc6470813@`

## 7. 发布

```
flutter build windows --release
# 产物目录 build\windows\x64\runner\Release\（exe + dll + data 一起分发）
```
