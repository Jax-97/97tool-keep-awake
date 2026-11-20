import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let helperPath = "/usr/local/bin/keepawake-lid"
    let setupName = "启用合盖继续跑.command"
    let selfPID = String(ProcessInfo.processInfo.processIdentifier)

    var window: NSWindow!
    var systemAssertion: Process?     // caffeinate -isu ：系统不睡
    var displayAssertion: Process?    // caffeinate -d   ：屏幕常亮
    var pendingRearm = false          // 熄屏后，等用户唤醒再把常亮装回去
    var sleepRequestedAt = Date.distantPast
    var startedAt = Date()
    var ticker: Timer?

    let dot = NSView()
    let titleLabel = NSTextField(labelWithString: "☕ 电脑不会睡眠")
    let clockLabel = NSTextField(labelWithString: "00:00:00")
    let statusLabel = NSTextField(labelWithString: "已阻止：空闲睡眠 · 系统睡眠")

    let screenSwitch = NSSwitch()
    let screenLabel = NSTextField(labelWithString: "跟随系统自动熄屏")
    let screenSub = NSTextField(labelWithString: "关掉这个开关 = 屏幕一直亮着，不会自动熄灭")

    let lidSwitch = NSSwitch()
    let lidLabel = NSTextField(labelWithString: "合盖继续运行")
    let lidSub = NSTextField(labelWithString: "盖上盖子也不休眠，需要一次性授权")
    let warnLabel = NSTextField(labelWithString: "⚠️ 合盖后仍在运行，注意散热，别直接塞进包里")

    let screenButton = NSButton(title: "立刻熄屏", target: nil, action: nil)
    let screenHint = NSTextField(labelWithString: "屏幕立刻黑掉；动一下键鼠就恢复常亮")
    let bottomHint = NSTextField(labelWithString: "关掉这个窗口 → 全部恢复系统原样")
    let quitButton = NSButton(title: "全部恢复并退出", target: nil, action: nil)

    var helperInstalled: Bool { FileManager.default.isExecutableFile(atPath: helperPath) }

    // MARK: - 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()

        if CommandLine.arguments.contains("--selftest") {
            selftest()
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            startSystemAssertion()
            screenSwitch.state = .off
            syncScreenUI()
            syncLidUI()
            tick()
            snapshot(to: CommandLine.arguments[i + 1])
            stopAll()
            exit(0)
        }

        startSystemAssertion()
        screenSwitch.state = .off       // 默认：不跟随系统，屏幕常亮
        syncScreenUI()
        syncLidUI()
        startedAt = Date()

        ticker = Timer.scheduledTimer(timeInterval: 1.0, target: self,
                                      selector: #selector(tick), userInfo: nil, repeats: true)
    }

    // MARK: - 界面

    func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 电脑不休眠", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出（恢复全部设置）", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = mainMenu
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 340),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "电脑不休眠"
        window.delegate = self
        window.isReleasedWhenClosed = false

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let wf = window.frame
            window.setFrameOrigin(NSPoint(x: (vf.midX - wf.width / 2).rounded(),
                                          y: (vf.midY - wf.height / 2 + 60).rounded()))
        }

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: 340))

        dot.frame = NSRect(x: 28, y: 302, width: 10, height: 10)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        content.addSubview(dot)

        titleLabel.frame = NSRect(x: 48, y: 290, width: 250, height: 30)
        titleLabel.font = NSFont.systemFont(ofSize: 21, weight: .semibold)
        content.addSubview(titleLabel)

        clockLabel.frame = NSRect(x: 296, y: 296, width: 150, height: 18)
        clockLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        clockLabel.textColor = .secondaryLabelColor
        clockLabel.alignment = .right
        content.addSubview(clockLabel)

        statusLabel.frame = NSRect(x: 26, y: 266, width: 420, height: 16)
        statusLabel.font = NSFont.systemFont(ofSize: 11.5)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)

        content.addSubview(separator(y: 254))

        screenSwitch.frame = NSRect(x: 22, y: 214, width: 40, height: 24)
        screenSwitch.target = self
        screenSwitch.action = #selector(toggleScreenSleepSetting(_:))
        content.addSubview(screenSwitch)

        screenLabel.frame = NSRect(x: 72, y: 217, width: 260, height: 20)
        screenLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        content.addSubview(screenLabel)

        screenSub.frame = NSRect(x: 72, y: 196, width: 385, height: 16)
        screenSub.font = NSFont.systemFont(ofSize: 11)
        screenSub.textColor = .tertiaryLabelColor
        content.addSubview(screenSub)

        lidSwitch.frame = NSRect(x: 22, y: 150, width: 40, height: 24)
        lidSwitch.target = self
        lidSwitch.action = #selector(toggleLid(_:))
        content.addSubview(lidSwitch)

        lidLabel.frame = NSRect(x: 72, y: 153, width: 200, height: 20)
        lidLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        content.addSubview(lidLabel)

        lidSub.frame = NSRect(x: 72, y: 132, width: 385, height: 16)
        lidSub.font = NSFont.systemFont(ofSize: 11)
        lidSub.textColor = .tertiaryLabelColor
        content.addSubview(lidSub)

        warnLabel.frame = NSRect(x: 26, y: 108, width: 420, height: 16)
        warnLabel.font = NSFont.systemFont(ofSize: 11)
        warnLabel.textColor = .systemOrange
        warnLabel.isHidden = true
        content.addSubview(warnLabel)

        screenButton.frame = NSRect(x: 22, y: 52, width: 110, height: 32)
        screenButton.bezelStyle = .rounded
        screenButton.target = self
        screenButton.action = #selector(sleepDisplayNow)
        content.addSubview(screenButton)

        screenHint.frame = NSRect(x: 144, y: 61, width: 310, height: 16)
        screenHint.font = NSFont.systemFont(ofSize: 11)
        screenHint.textColor = .tertiaryLabelColor
        content.addSubview(screenHint)

        content.addSubview(separator(y: 40))

        bottomHint.frame = NSRect(x: 24, y: 12, width: 270, height: 16)
        bottomHint.font = NSFont.systemFont(ofSize: 11)
        bottomHint.textColor = .tertiaryLabelColor
        content.addSubview(bottomHint)

        quitButton.frame = NSRect(x: 316, y: 8, width: 128, height: 26)
        quitButton.bezelStyle = .rounded
        quitButton.target = self
        quitButton.action = #selector(stopAndQuit)
        content.addSubview(quitButton)

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func separator(y: CGFloat) -> NSBox {
        let box = NSBox(frame: NSRect(x: 24, y: y, width: 422, height: 1))
        box.boxType = .separator
        return box
    }

    // MARK: - 系统睡眠（常驻断言）

    func startSystemAssertion() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-is", "-w", selfPID]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.refreshTitle() }
        }
        try? p.run()
        systemAssertion = p
        refreshTitle()
    }

    func refreshTitle() {
        let active = systemAssertion?.isRunning ?? false
        dot.layer?.backgroundColor = (active ? NSColor.systemGreen : NSColor.systemRed).cgColor
        titleLabel.stringValue = active ? "☕ 电脑不会睡眠" : "😴 睡眠规则已停止"
        statusLabel.stringValue = active ? "已阻止：空闲睡眠 · 系统睡眠" : "电脑已恢复默认的自动睡眠"
    }

    // MARK: - 屏幕常亮 / 跟随系统

    /// true = 屏幕常亮（装断言）；false = 交还系统，按空闲时间熄屏
    func applyScreenAwake(_ awake: Bool) {
        if awake {
            guard displayAssertion?.isRunning != true else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-d", "-w", selfPID]
            try? p.run()
            displayAssertion = p
        } else {
            if let p = displayAssertion, p.isRunning {
                p.terminate()
                p.waitUntilExit()
            }
            displayAssertion = nil
        }
    }

    func followSystemSleep() -> Bool { screenSwitch.state == .on }

    func displaySleepMinutes() -> String {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "custom"]
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return "" }
        p.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var batt = "-", ac = "-", section = ""
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Battery Power") { section = "b" }
            else if line.hasPrefix("AC Power") { section = "a" }
            else if line.hasPrefix("displaysleep") {
                let v = line.split(separator: " ").last.map(String.init) ?? "-"
                if section == "b" { batt = v } else if section == "a" { ac = v }
            }
        }
        return "电池 \(batt) 分钟 / 电源 \(ac) 分钟"
    }

    func syncScreenUI() {
        if followSystemSleep() {
            applyScreenAwake(false)
            screenSub.stringValue = "屏幕会按系统设置自动熄灭（\(displaySleepMinutes())）"
            screenHint.stringValue = "屏幕会自己按时熄灭，不用点这个按钮"
        } else {
            applyScreenAwake(true)
            screenSub.stringValue = "现在：屏幕一直亮着，不会自动熄灭（想省电就点「立刻熄屏」）"
            screenHint.stringValue = "屏幕立刻黑掉；动一下键鼠就恢复常亮"
        }
        screenSwitch.isEnabled = true
    }

    @objc func toggleScreenSleepSetting(_ sender: NSSwitch) {
        syncScreenUI()
    }

    // MARK: - 立刻熄屏（与常亮断言冲突，先撤断言再装回）

    @objc func sleepDisplayNow() {
        let hadAssertion = displayAssertion?.isRunning == true
        if hadAssertion { applyScreenAwake(false) }
        usleep(250_000)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
        p.waitUntilExit()

        pendingRearm = hadAssertion
        sleepRequestedAt = Date()
        screenHint.stringValue = "屏幕已熄灭 · 动一下键鼠就恢复常亮"
    }

    func anyDisplayAsleep() -> Bool {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success, count > 0 else { return false }
        for i in 0..<Int(count) where CGDisplayIsAsleep(ids[i]) != 0 { return true }
        return false
    }

    /// 除我们自己以外，还有谁在阻止显示器睡眠（微信等会）
    func foreignDisplayAssertions() -> [String] {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "assertions"]
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var names: [String] = []
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            guard line.contains("PreventUserIdleDisplaySleep") || line.contains("NoDisplaySleepAssertion") else { continue }
            if line.contains(" 0 ") || line.hasSuffix(" 0") { continue }
            if line.contains("caffeinate") { continue }        // 我们自己
            if let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"), open < close {
                let who = String(line[line.index(after: open)..<close])
                if !names.contains(who) { names.append(who) }
            }
        }
        return names
    }

    // MARK: - 合盖继续运行

    func readLidStatus() -> Bool {
        let p = Process()
        let pipe = Pipe()
        if helperInstalled {
            p.executableURL = URL(fileURLWithPath: helperPath)
            p.arguments = ["status"]
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["-g"]
        }
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.range(of: "SleepDisabled\\s+1", options: .regularExpression) != nil
    }

    func applyLid(_ on: Bool) -> (ok: Bool, message: String) {
        guard helperInstalled else {
            return (false, "还没有授权。请先双击桌面上的「\(setupName)」，输入一次开机密码。")
        }
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", helperPath, on ? "1" : "0"]
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, error.localizedDescription) }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus == 0 { return (true, "") }
        return (false, out.isEmpty ? "sudo 退出码 \(p.terminationStatus)" : out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func syncLidUI() {
        let on = readLidStatus()
        lidSwitch.state = on ? .on : .off
        lidSub.stringValue = helperInstalled
            ? (on ? "已生效：合盖后系统不会睡眠" : "盖上盖子也不休眠，需要一次性授权")
            : "未授权 · 点开关会提示安装（只需一次）"
        warnLabel.isHidden = !on
    }

    @objc func toggleLid(_ sender: NSSwitch) {
        let want = sender.state == .on
        if want && !helperInstalled {
            sender.state = .off
            promptInstall()
            return
        }
        let r = applyLid(want)
        if r.ok {
            syncLidUI()
        } else {
            sender.state = want ? .off : .on
            let a = NSAlert()
            a.messageText = "切换失败"
            a.informativeText = r.message
            a.alertStyle = .warning
            a.addButton(withTitle: "好")
            a.runModal()
        }
    }

    func promptInstall() {
        let a = NSAlert()
        a.messageText = "合盖继续运行需要一次性授权"
        a.informativeText = """
        这一步要用管理员权限改一条电源设置（关闭「合盖休眠」）。
        桌面上有「\(setupName)」，双击它、输入一次开机密码即可，以后就不用再输。
        """
        a.alertStyle = .informational
        a.addButton(withTitle: "去授权")
        a.addButton(withTitle: "取消")
        if a.runModal() == .alertFirstButtonReturn {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/\(setupName)")
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 计时

    @objc func tick() {
        if let p = systemAssertion, p.isRunning {
            let s = Int(Date().timeIntervalSince(startedAt))
            clockLabel.stringValue = String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        // 熄屏后用户一动键鼠屏幕就亮 —— 这时把「常亮」装回去
        if pendingRearm, Date().timeIntervalSince(sleepRequestedAt) > 2, !anyDisplayAsleep() {
            pendingRearm = false
            applyScreenAwake(true)
            let others = foreignDisplayAssertions()
            screenHint.stringValue = others.isEmpty
                ? "屏幕已亮 · 已恢复常亮"
                : "屏幕已亮 · 已恢复常亮（\(others.joined(separator: "、")) 也在阻止熄屏）"
        }
    }

    // MARK: - 退出

    @objc func stopAndQuit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }

    func stopAll() {
        ticker?.invalidate()
        if let p = displayAssertion, p.isRunning { p.terminate() }
        displayAssertion = nil
        if let p = systemAssertion, p.isRunning { p.terminate() }
        systemAssertion = nil
        if readLidStatus() { _ = applyLid(false) }
    }

    func applicationWillTerminate(_ notification: Notification) { stopAll() }

    // MARK: - 调试

    func snapshot(to path: String) {
        let v = window.contentView!
        let scale = max(window.backingScaleFactor, 1)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(v.bounds.width * scale),
                                   pixelsHigh: Int(v.bounds.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = v.bounds.size
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            let ctx = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.current = ctx
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: v.bounds).fill()
            v.displayIgnoringOpacity(v.bounds, in: ctx)
            NSGraphicsContext.restoreGraphicsState()
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// 验证「常亮 → 立刻熄屏 → 屏幕保持黑 → 唤醒后恢复常亮」整条链路
    func selftest() {
        startSystemAssertion()
        screenSwitch.state = .off
        syncScreenUI()
        print("① 常亮断言已装: \(displayAssertion?.isRunning == true)")

        sleep(1)
        sleepDisplayNow()
        sleep(2)
        print("② 熄屏 2 秒后屏幕是否仍黑: \(anyDisplayAsleep())")

        let wake = Process()
        wake.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        wake.arguments = ["-u", "-t", "2"]
        try? wake.run()
        wake.waitUntilExit()
        sleep(1)
        print("③ 唤醒后屏幕是否亮: \(!anyDisplayAsleep())")

        // 走真实的 tick 自动恢复路径，而不是手工装回去
        sleepRequestedAt = Date().addingTimeInterval(-3)
        pendingRearm = true
        print("   外部正在阻止熄屏的软件: \(foreignDisplayAssertions())")
        tick()
        print("④ tick 自动恢复常亮: \(displayAssertion?.isRunning == true)")

        stopAll()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
