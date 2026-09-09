# lnuElytra Flutter 多学校版

基于 [mcitem/lnuElytra](https://github.com/mcitem/lnuElytra) 原作者 Flutter GUI（flutter_rust_bridge + cargokit）继续开发，
内置**多学校适配**：岭南师范学院、丽江师范学院（6 个选课标签页）、山东青年政治学院、广州商学院，也支持自定义服务器与自定义标签。

> 仅供技术学习研究使用，不保证可用性、成功率，一切风险与后果由使用者自行承担（AGPL-3.0）。

## 功能

- **登录**：账密登录 / Cookie 登录，选择学校或自定义服务器地址；登录成功自动保存 Cookie，会话失效自动重登。
- **自动抢课（监控）**：
  - 预设课程按**添加顺序 = 志愿顺序**排列，可上下调整；
  - **最多选 N 门**（0 = 全部）、**并行 / 按志愿顺序**、**轮询间隔(ms)** 可调；
  - 丽江师范等多标签学校支持**自动遍历标签**或指定目标标签；
  - 到点自动 `init` 直到选课开放，开放后持续轮询选课；
  - 支持**子教学班课程**（V2 丽江专用端点 → V1 通用端点自动回退）。
- **手动抢课**：搜索教学班（多标签自动切换）、一键抢课、子教学班回退。
- **批量多开**：登录页粘贴账号表格（从 Excel 复制），一键为每个账号弹出独立窗口自动登录抢课：
  - 推荐直接点击「选择 Excel 文件」导入 `.xlsx`，完全绕开剪贴板格式问题；也支持粘贴文本；
  - 支持带表头（`学号 / 密码 / 志愿一 / 志愿二 / ... / 服务器 / 标签`，列顺序不限，"微信名"等无关列自动忽略）或直接粘贴 `学号<TAB>密码<TAB>课程1,课程2` 的行；
  - Excel 多行单元格、全角/半角空格、说明行等脏数据自动清洗；
  - 可选 **启动前先验证登录**（只启动能登录的账号，错误账号自动跳过）；
  - 可选 **并行 / 按志愿顺序**、**立即开始抢课 / 仅填好预设不开始**、轮询间隔、每窗口最多选几门。

## 学校配置

学校定义在 `lib/models/school.dart`。每个学校：服务器地址 + 标签页列表（`xkkz_id`）。

```dart
School(
  id: 'lijiang',
  name: '丽江师范学院',
  server: 'http://newjw.lj-edu.cn/jwglxt',
  tabs: [
    SchoolTab('54FC1FF9A3362073E06371D2A8C0AD3A', '板块课(大学体育3（本科）)'),
    // ...
  ],
),
```

Rust 核心（含多学校扩展方法）位于 `rust/core/`，由 `rust/Cargo.toml` 以 path 依赖引入：
`lnu-elytra = { path = "core", features = ["__flutter", "reqwest_cookie_store", "tracing"] }`

## 编译（Windows 桌面版）

前置要求：

- Flutter SDK（stable，测试于 3.44.8）+ Dart
- Rust stable **MSVC** 工具链（`rustup toolchain list` 只保留 `stable-x86_64-pc-windows-msvc`）
- Visual Studio 2022+（含「使用 C++ 的桌面开发」与 Windows 10/11 SDK）
- 国内网络建议设置镜像：
  - `PUB_HOSTED_URL=https://pub.flutter-io.cn`
  - `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`

构建：

```sh
flutter pub get
flutter build windows --release
# 产物：build\windows\x64\runner\Release\lnu_elytra.exe
```

注意：项目路径请勿包含中文/空格（cargokit 用 cmd `echo` 生成 pubspec.yaml，中文路径会导致 Dart 解析失败）。

## 修改 Rust 桥接后重新生成绑定

```sh
cargo install flutter_rust_bridge_codegen --version 2.13.0-beta.5 --locked
flutter_rust_bridge_codegen generate
```

`rust/core/src/flutter.rs` 是 Rust → Dart 的桥接层（FClient），新增方法后需要重新生成
`rust/src/frb_generated.rs` 与 `lib/src/rust/` 下的 Dart 绑定。

## 目录

- `rust/core/` —— 多学校 Rust 核心（fork 自 lnuElytra 0.0.10，新增 switch_tab / 子教学班等）
- `rust/src/` —— FRB wrapper（rust_lib_lnu_elytra）
- `lib/models/school.dart` —— 学校配置
- `lib/views/login/` —— 登录页（学校选择）
- `lib/views/home/auto_grab/` —— 预设抢课（监控）
- `lib/views/home/manual_grab/` —— 手动抢课

## 鸣谢

- 原作者 [mcitem/lnuElytra](https://github.com/mcitem/lnuElytra)（AGPL-3.0）
- 多学校适配思路记录见 `lnuElytra-new/docs/school-adaptation/DEVELOPER_NOTES.md`（Python CLI 版开发笔记）
