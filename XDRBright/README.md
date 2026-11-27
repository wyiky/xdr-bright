# XDR Bright

一个常驻 macOS 菜单栏的免费小工具：给内建 XDR 显示器解锁 HDR 亮度，
不需要 DisplayBuddy、Vivid 或任何付费 App。

## 用法

1. 打开 `XDR Bright.app`（首次打开若被 Gatekeeper 拦截，右键 → 打开）
2. 菜单栏出现太阳图标
3. 点图标 → **开启 HDR 增亮**
4. 亮度键照常可调；需要调增亮档位时在菜单里选一档（30%）或二档（50%）
5. 想开机自动运行，勾选 **登录时启动**

## 原理

- 按 `1 + 0.00535 × 档位` 生成 256 点 gamma 传输表并写入（采样数必须是 256，1024 会被系统截断）
- 同时挂一个 1×1 的 EDR 头空间窗口，让系统进入 EDR 输出模式；少了这一半只会发灰/过曝
- 每 2 秒核对一次 gamma 末端，被系统改掉会自动重施
- gamma 表绑定在 App 进程上：退出或崩溃会自动还原，不会把屏幕留在过亮状态

## 要求

- macOS 14 或更新
- 内建 XDR 屏的 MacBook Pro / Pro Display XDR / Studio Display XDR 效果最明显；
  普通外接屏只会裁剪高光，不会真的更亮

## 自己编译

```bash
./script/build_app.sh          # 生成 dist/XDR Bright.app 和 dist/XDR-Bright.zip
./script/build_app.sh install  # 安装到 /Applications 并启动
```

## 注意

- **菜单栏放不下时图标会被收进溢出区**：macOS 26 会在菜单栏右侧显示一个 `«` 箭头，
  新图标会被藏进去。看不到太阳时，先点 `«`，或清理几个其它菜单栏图标。
- 本项目与 SparkMiniMonitor 共用同一套 `HDRBrightness` 核心包，**不要和 SparkMiniMonitor 的太阳按钮同时开**，两者会互相覆盖 gamma 表（最后一个生效）。
- 分发给别人时，对方首次打开需要右键 → 打开，或执行
  `xattr -d com.apple.quarantine "/Applications/XDR Bright.app"`。
