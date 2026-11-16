import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var updateTimer: Timer?

    var instances: [MonitoredInstance] = []
    var isChecking: Bool = false
    private var hasCompletedInitialScan = false
    private var pendingCacheReset = false
    private var instancesGeneration = 0

    private let liveMonitor = LiveMonitor()
    private let liveQueue = DispatchQueue(label: "com.sqoder.momi.live", qos: .utility)

    let mainMenu = NSMenu()
    let dashboardView = MomiDashboardView()
    let dashboardMenuItem = NSMenuItem()
    private var refreshRateSubmenu = NSMenu()
    private var launchAtLoginItem: NSMenuItem?
    var statsWindowController: UsageStatsWindowController?
    var latestUsageBundle: UsageSnapshotBundle?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "momi.speedo.v2"
        statusItem.button?.image = nil
        statusItem.button?.title = "--"

        instances = MonitoredInstance.defaultInstances()

        setupApplicationMainMenu()
        setupMenu()
        triggerBackgroundUpdate()

        UsageIndex.shared.onUpdate = { [weak self] bundle in
            self?.applyUsageBundle(bundle)
        }
        UsageIndex.shared.start()
        scheduleUpdateTimer()
    }

    private func setupApplicationMainMenu() {
        let appMenuBar = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuBar.addItem(appMenuItem)

        let appMenu = NSMenu()
        let statsItem = NSMenuItem(title: "用量统计…", action: #selector(showStatsAction), keyEquivalent: "t")
        statsItem.target = self
        appMenu.addItem(statsItem)

        let refreshItem = NSMenuItem(title: "刷新数据", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        appMenu.addItem(refreshItem)

        appMenu.addItem(NSMenuItem.separator())

        let closeItem = NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(closeItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 momi", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        NSApp.mainMenu = appMenuBar
    }

    private func setupMenu() {
        mainMenu.autoenablesItems = false
        mainMenu.delegate = self

        dashboardView.onOpenStats = { [weak self] in
            self?.showStatsAction()
        }
        dashboardView.onSelectInstance = { instance in
            guard let url = instance.latestURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        dashboardMenuItem.view = dashboardView
        mainMenu.addItem(dashboardMenuItem)
        updateDashboardState()

        mainMenu.addItem(NSMenuItem.separator())

        let statsItem = NSMenuItem(title: "用量统计…", action: #selector(showStatsAction), keyEquivalent: "t")
        statsItem.target = self
        mainMenu.addItem(statsItem)

        let refreshItem = NSMenuItem(title: "刷新数据", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        mainMenu.addItem(refreshItem)

        let refreshRateItem = NSMenuItem(title: "刷新频率", action: nil, keyEquivalent: "")
        refreshRateSubmenu = NSMenu()
        for interval in refreshIntervalOptions {
            let title = interval == floor(interval)
                ? String(format: "%.0f 秒", interval)
                : String(format: "%.1f 秒", interval)
            let option = NSMenuItem(title: title, action: #selector(selectRefreshIntervalAction(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = interval
            refreshRateSubmenu.addItem(option)
        }
        refreshRateItem.submenu = refreshRateSubmenu
        mainMenu.addItem(refreshRateItem)

        let loginItem = NSMenuItem(title: "开机自启", action: #selector(toggleLaunchAtLoginAction), keyEquivalent: "")
        loginItem.target = self
        launchAtLoginItem = loginItem
        mainMenu.addItem(loginItem)

        mainMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 momi", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        mainMenu.addItem(quitItem)

        syncMenuControlsState()
        statusItem.menu = mainMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        syncMenuControlsState()
        updateDashboardState()
        triggerBackgroundUpdate()
        UsageIndex.shared.scanNow()
    }

    private func syncMenuControlsState() {
        let current = currentStoredRefreshInterval()
        for item in refreshRateSubmenu.items {
            if let interval = item.representedObject as? Double {
                item.state = abs(current - interval) < 0.01 ? .on : .off
            }
        }
        if let loginItem = launchAtLoginItem {
            let status = SMAppService.mainApp.status
            loginItem.state = (status == .enabled) ? .on : .off
        }
    }

    func applyUsageBundle(_ bundle: UsageSnapshotBundle) {
        latestUsageBundle = bundle
        let total = bundle.periods[.all]?.total.total ?? 0
        dashboardView.updateTotal(total, indexing: bundle.isIndexing)
        statsWindowController?.apply(bundle)
    }

    func scheduleUpdateTimer() {
        updateTimer?.invalidate()
        let interval = currentStoredRefreshInterval()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.triggerBackgroundUpdate()
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    func triggerBackgroundUpdate() {
        if isChecking { return }
        isChecking = true

        let snapshot = instances
        let generation = instancesGeneration
        let shouldResetCaches = pendingCacheReset
        pendingCacheReset = false

        liveQueue.async { [weak self] in
            guard let self = self else { return }
            if shouldResetCaches {
                self.liveMonitor.resetCaches()
            }
            let result = self.liveMonitor.scan(instances: snapshot, now: Date())

            DispatchQueue.main.async {
                self.isChecking = false
                guard generation == self.instancesGeneration else {
                    self.triggerBackgroundUpdate()
                    return
                }
                let isFirstScan = !self.hasCompletedInitialScan
                self.hasCompletedInitialScan = true
                self.instances = result.instances
                if result.hasChanges || isFirstScan {
                    self.updateDashboardState()
                }
            }
        }
    }

    func updateDashboardState() {
        let visibleInstances = instances.filter { $0.latestURL != nil && $0.hasValidSession }
        let generating = visibleInstances.filter { $0.isGenerating }
        let isConcurrent = generating.count > 1

        if isConcurrent {
            let displaySpeed = generating.map { clampSpeed($0.currentSpeed) }.max() ?? 0.0
            statusItem.button?.title = displaySpeed > 0
                ? String(format: "%.1f t/s", displaySpeed)
                : "生成中"
        } else if let gen = generating.first {
            let speed = clampSpeed(gen.currentSpeed)
            statusItem.button?.title = speed > 0
                ? String(format: "%.1f t/s", speed)
                : "生成中"
        } else {
            statusItem.button?.title = "--"
        }

        let sortedInstances = visibleInstances
            .enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element, r = rhs.element
                if l.isGenerating != r.isGenerating { return l.isGenerating }
                let lSpeed = clampSpeed(l.currentSpeed)
                let rSpeed = clampSpeed(r.currentSpeed)
                if l.isGenerating && lSpeed != rSpeed {
                    return lSpeed > rSpeed
                }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }

        dashboardView.update(with: sortedInstances)
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func showStatsAction() {
        if statsWindowController == nil {
            let controller = UsageStatsWindowController()
            controller.onRefreshIntervalChange = { [weak self] _ in
                self?.scheduleUpdateTimer()
                self?.syncMenuControlsState()
            }
            statsWindowController = controller
        }
        if let bundle = latestUsageBundle {
            statsWindowController?.apply(bundle)
        }
        UsageIndex.shared.scanNow()
        activateApp()
        statsWindowController?.showWindow(nil)
        statsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func selectRefreshIntervalAction(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? Double else { return }
        UserDefaults.standard.set(interval, forKey: refreshIntervalDefaultsKey)
        scheduleUpdateTimer()
        syncMenuControlsState()
        statsWindowController?.syncRefreshIntervalDisplay()
    }

    @objc private func toggleLaunchAtLoginAction() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            SMAppService.openSystemSettingsLoginItems()
        }
        syncMenuControlsState()
    }

    @objc func refreshAction() {
        instancesGeneration += 1
        pendingCacheReset = true
        for i in 0..<instances.count {
            instances[i].latestURL = nil
            instances[i].lastParsedModDate = .distantPast
            instances[i].resetSessionState()
        }
        triggerBackgroundUpdate()
        UsageIndex.shared.scanNow()
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
