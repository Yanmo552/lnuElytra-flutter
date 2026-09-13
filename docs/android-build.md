# Android (APK) 构建指南

面向仓库：`C:\lnu_elytra`（Flutter 主程序，GitHub: `Yanmo552/lnuElytra-flutter`）
产物：`build\app\outputs\flutter-apk\`

## 1. 环境要求

| 组件 | 版本 / 路径 |
| --- | --- |
| Flutter | 3.44.8 stable (`C:\flutter`) |
| JDK | Microsoft JDK 21 (`C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot`) |
| Android SDK | `C:\Android\sdk` |
| NDK | `28.2.13676358`（必须与 `flutter.ndkVersion` 一致） |
| Rust | stable-x86_64-pc-windows-msvc (1.96.0) + 4 个 Android target |

Rust 需要安装的 target：

```
rustup target add --toolchain stable-x86_64-pc-windows-msvc \
  aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
```

## 2. 构建命令

```powershell
$env:Path="C:\flutter\bin;"+$env:Path
$env:PUB_CACHE="C:\pubcache"
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
$env:FLUTTER_SUPPRESS_ANALYTICS="true"
$env:JAVA_HOME="C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot"
Set-Location C:\lnu_elytra

# 通用包（所有 ABI，约 69 MB）
flutter --no-version-check build apk --release

# 分包（推荐分发，体积小很多）
flutter --no-version-check build apk --release --split-per-abi
```

| 产物 | 体积 | 用途 |
| --- | --- | --- |
| `app-release.apk` | 68.9 MB | 通用版，任何机型 |
| `app-arm64-v8a-release.apk` | 24.4 MB | 现代手机（首选） |
| `app-armeabi-v7a-release.apk` | 19.3 MB | 老旧 32 位机型 |
| `app-x86_64-release.apk` | 26.9 MB | 模拟器 |

## 3. 踩过的坑（重要，重装环境必看）

### 3.1 rustup 镜像返回 404 → cargokit 构建失败

现象：cargokit 报 `component download failed ... 404`，最终 APK 里**不含**
`librust_lib_lnu_elytra.so`（构建仍显示成功，属于静默错误，务必验证产物）。

原因：工具链的 `multirust-channel-manifest.toml` 里写死了清华源地址，
`RUSTUP_DIST_SERVER` 环境变量对它无效。

解决：把该文件里的下载地址整体替换为可用镜像（rsproxy.cn 实测可用）：

```
文件：C:\Users\<用户>\.rustup\toolchains\stable-x86_64-pc-windows-msvc\lib\rustlib\multirust-channel-manifest.toml
替换：https://mirrors.tuna.tsinghua.edu.cn/rustup/dist/  →  https://rsproxy.cn/dist/
```

替代方案：`mirrors.ustc.edu.cn/rust-static/dist`、`mirrors.sjtug.sjtu.edu.cn/rust-static/dist` 同样可用。
`static.rust-lang.org` 在本机实测会卡在 0 字节。

### 3.2 路径含中文 → ninja 构建失败

现象：`:jni:buildCMakeRelWithDebInfo` 报
`FindFirstFileExA(c:/users/郑/...): 文件名、目录名或卷标语法不正确`。

原因：pub 缓存默认在 `C:\Users\郑\AppData\Local\Pub\Cache`，路径里的中文
会让 ninja / CMake 出错。

解决：把 pub 缓存搬到纯 ASCII 路径。

```powershell
robocopy "C:\Users\郑\AppData\Local\Pub\Cache" "C:\pubcache" /E
# 删掉复制过来的过时 CMake 缓存（里面存的是旧绝对路径）
Remove-Item -Recurse -Force "C:\pubcache\hosted\pub.flutter-io.cn\jni-1.0.3\android\.cxx"
[Environment]::SetEnvironmentVariable("PUB_CACHE","C:\pubcache","User")
flutter pub get
```

### 3.3 NDK 缺 `package.xml` → cargokit 想重新下载 600 MB

现象：日志出现 `INFO: Installing NDK 28.2.13676358`，随后卡在
`android-ndk-r28c-windows.zip`（0 字节）。

原因：`cargokit/build_tool/lib/src/android_environment.dart:57` 的
`ndkIsInstalled()` 只检查 `<sdk>/ndk/<版本>/package.xml`。
手工解压的 NDK 只有 `source.properties`，没有 `package.xml`。

解决：在 `C:\Android\sdk\ndk\28.2.13676358\` 下补一个 `package.xml`：

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?><ns2:repository
 xmlns:ns2="http://schemas.android.com/repository/android/common/02"
 xmlns:ns5="http://schemas.android.com/repository/android/generic/02"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<license id="license-2802B623" type="text"/>
<localPackage path="ndk;28.2.13676358" obsolete="false">
<type-details xsi:type="ns5:genericDetailsType"/>
<revision><major>28</major><minor>2</minor><micro>13676358</micro></revision>
<display-name>NDK (Side by side) 28.2.13676358</display-name>
<uses-license ref="license-2802B623"/>
</localPackage></ns2:repository>
```

### 3.4 Rust edition 2024 的 `#[no_mangle]`

`rust/src/android_init.rs` 只在 Android 目标下编译，Windows 构建不会暴露该问题。
edition 2024 必须写成 `#[unsafe(no_mangle)]`，否则报
`error: unsafe attribute used without unsafe`。已修复。

### 3.5 明文 HTTP

学校教务系统基本都是 `http://`，Android 9+ 默认禁止明文流量。
`android/app/src/main/AndroidManifest.xml` 里 `<application>` 已加
`android:usesCleartextTraffic="true"`。

### 3.6 Gradle 下载慢

`android/gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl`
已换成腾讯云镜像：`https://mirrors.cloud.tencent.com/gradle/gradle-8.14-bin.zip`。

## 4. 签名

`android/app/build.gradle.kts` 从 `local.properties`（或环境变量）读取签名信息，
`local.properties` 已被 `.gitignore` 忽略，不会进版本库。

```
keystore : C:\lnu_elytra_android_keystore\lnu_elytra.jks
alias    : lnuelytra
store/key: lnuelytra2026
```

**务必备份 keystore**，丢了就无法覆盖安装升级。

## 5. 构建后自检（必做）

```powershell
python -c "import zipfile;z=zipfile.ZipFile(r'build\app\outputs\flutter-apk\app-release.apk');print([n for n in z.namelist() if 'rust_lib_lnu_elytra' in n])"
```

应当输出 3 个 ABI 的 `lib/<abi>/librust_lib_lnu_elytra.so`。
**如果为空，说明 Rust 没编进去，装上去一启动就崩。**

再验证签名：

```powershell
C:\Android\sdk\build-tools\36.0.0\apksigner.bat verify build\app\outputs\flutter-apk\app-release.apk
```

## 6. 与 Windows 端的差异

- Cookie 存储是内存态（`CookieStoreRwLock::default()`），没有磁盘路径问题。
- 日志导出走 `share_plus` 分享面板（`lib/components/log_panel.dart`）。
- `main()` 的 `args` 在 Android 下为空，自动启动参数逻辑会跳过。