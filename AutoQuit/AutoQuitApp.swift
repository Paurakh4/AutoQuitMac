//
//  AutoQuitApp.swift
//  AutoQuit
//
//  Created by Paurakh Pyakurel on 06/01/2026.
//

import SwiftUI
import ApplicationServices
import Combine

@MainActor
class AppWatcher: ObservableObject {
    static let shared = AppWatcher()
    @Published var isTrusted: Bool = AXIsProcessTrusted()
    
    private var observers: [pid_t: AXObserver] = [:]
    private var contexts: [pid_t: WatcherContext] = [:]
    private var permissionTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    
    class WatcherContext {
        unowned let watcher: AppWatcher
        let pid: pid_t
        init(watcher: AppWatcher, pid: pid_t) {
            self.watcher = watcher
            self.pid = pid
        }
    }
    
    init() {
        // Check for permissions periodically
        permissionTask = Task {
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                self.checkPermissions()
            }
        }
        
        // Polling Fallback: Check all watched apps every 5 seconds
        pollingTask = Task {
            while true {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                self.pollWatchedApps()
            }
        }
        
        if isTrusted {
            startMonitoring()
        }
    }
    
    deinit {
        permissionTask?.cancel()
        pollingTask?.cancel()
    }
    
    func pollWatchedApps() {
        guard isTrusted else { return }
        
        // Iterate over all currently watched PIDs
        for pid in observers.keys {
            if let app = getApp(pid: pid) {
                checkApp(app)
            }
        }
    }
    
    func checkPermissions() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
            if trusted {
                startMonitoring()
            }
        }
    }
    
    func startMonitoring() {
        print("Starting AppWatcher monitoring...")
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        
        for app in NSWorkspace.shared.runningApplications {
            watchApp(app)
        }
    }
    
    @objc func appLaunched(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            watchApp(app)
        }
    }
    
    @objc func appTerminated(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            unwatchApp(app)
        }
    }
    
    func unwatchApp(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        if let observer = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers.removeValue(forKey: pid)
            contexts.removeValue(forKey: pid)
        }
    }
    
    func watchApp(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        
        let pid = app.processIdentifier
        var observer: AXObserver?
        
        let context = WatcherContext(watcher: self, pid: pid)
        contexts[pid] = context // Keep it alive
        let refcon = Unmanaged.passUnretained(context).toOpaque()
        
        let error = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let context = Unmanaged<WatcherContext>.fromOpaque(refcon).takeUnretainedValue()
            context.watcher.handleNotification(observer: observer, element: element, notification: notification, pid: context.pid)
        }, &observer)
        
        guard error == .success, let axObserver = observer else {
            contexts.removeValue(forKey: pid)
            return
        }
        
        // Add source to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
        // AXObserverSetCallback(axObserver, refcon) // Redundant and potentially causing issues
        
        observers[pid] = axObserver
        print("Watching \(app.localizedName ?? "unknown")")
        
        // Initial setup
        let selfPtr = refcon // Use the same context pointer
        let appElement = AXUIElementCreateApplication(pid)
        
        // Watch for new windows created
        AXObserverAddNotification(axObserver, appElement, kAXWindowCreatedNotification as CFString, selfPtr)
        
        // Watch existing windows
        var windows: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        if result == .success, let windowsList = windows as? [AXUIElement] {
            for window in windowsList {
                AXObserverAddNotification(axObserver, window, kAXUIElementDestroyedNotification as CFString, selfPtr)
            }
        }
    }
    
    func handleNotification(observer: AXObserver, element: AXUIElement, notification: CFString, pid: pid_t) {
        let notifName = notification as String
        
        if notifName == kAXWindowCreatedNotification as String {
            // New window created, watch it for destruction
            // We need the refcon (context) to pass to AddNotification
            if let context = contexts[pid] {
                let refcon = Unmanaged.passUnretained(context).toOpaque()
                AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
            }
        } else if notifName == kAXUIElementDestroyedNotification as String {
            handleWindowClosed(pid: pid)
        }
    }
    
    func getApp(pid: pid_t) -> NSRunningApplication? {
        return NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
    }
    
    func handleWindowClosed(pid: pid_t) {
        // Retry logic to handle AX tree update lag
        checkAppWithRetry(pid: pid, attempt: 1)
    }
    
    func checkAppWithRetry(pid: pid_t, attempt: Int) {
        guard let app = self.getApp(pid: pid) else { return }
        
        // Delays: 0.1s, 0.5s, 1.0s
        let delays = [0.1, 0.4, 0.5] // Cumulative: 0.1, 0.5, 1.0
        guard attempt <= delays.count else { return }
        
        let delay = delays[attempt - 1]
        
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let shouldQuit = self.checkApp(app)
            if !shouldQuit {
                // If we found windows, maybe they are ghost windows? Check again.
                // Only retry if we suspect lag (optional, but safer)
                if attempt < delays.count {
                    // print("Windows found for \(app.localizedName ?? "app"). Retrying check (\(attempt + 1)/\(delays.count))...")
                    self.checkAppWithRetry(pid: pid, attempt: attempt + 1)
                }
            }
        }
    }
    
    @discardableResult
    func checkApp(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var windows: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        
        if result == .success, let windowsList = windows as? [AXUIElement] {
            // Check for standard windows (not invisible ones)
            let visibleWindows = windowsList.filter { window in
                var values: CFArray?
                let attributes = [
                    kAXRoleAttribute,
                    kAXSubroleAttribute,
                    kAXTitleAttribute,
                    kAXMinimizedAttribute,
                    kAXHiddenAttribute,
                    kAXSizeAttribute
                ] as CFArray
                
                let result = AXUIElementCopyMultipleAttributeValues(window, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
                
                guard result == .success, let valuesList = values as? [AnyObject], valuesList.count == 6 else {
                    return false
                }
                
                // AXUIElementCopyMultipleAttributeValues returns values in the same order. 
                // Missing values might be NSNull or just missing? 
                // Documentation says it returns an array of values. If an error occurs for a specific attribute, 
                // it might return a specific error wrapper or just fail. 
                // Usually it fills with AXValue or appropriate type.
                
                // Safely unwrap
                func getVal<T>(_ index: Int, type: T.Type) -> T? {
                    if index < valuesList.count {
                        let val = valuesList[index]
                        // Check for AXValue specifically if needed, but usually casting works if bridged
                        if val is NSNull { return nil }
                        return val as? T
                    }
                    return nil
                }

                let _ = getVal(0, type: String.self) // roleString
                let subroleString = getVal(1, type: String.self)
                let _ = getVal(2, type: String.self) ?? "" // titleString
                let isMinimized = getVal(3, type: Bool.self) ?? false
                let isHidden = getVal(4, type: Bool.self) ?? false
                
                var width: CGFloat = 0
                var height: CGFloat = 0
                
                if let sizeVal = getVal(5, type: AXValue.self) {
                     var size = CGSize.zero
                     AXValueGetValue(sizeVal, .cgSize, &size)
                     width = size.width
                     height = size.height
                }

                let isTiny = width < 50 && height < 50
                
                // Debug log (can be commented out for production)
                // print(" - Window: '\(titleString)' | Role: \(roleString ?? "nil") | Subrole: \(subroleString ?? "nil") | Minimized: \(isMinimized) | Hidden: \(isHidden) | Size: \(width)x\(height)")
                
                let isStandardWindow = subroleString == (kAXStandardWindowSubrole as String)
                
                return isStandardWindow && !isMinimized && !isHidden && !isTiny
            }
            
            if visibleWindows.isEmpty {
                print("AutoQuit: Closing \(app.localizedName ?? "app") (PID: \(pid))")
                app.terminate()
                return true
            }
        }
        return false
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "AutoQuit")
        }
        
        // Initial Menu Setup
        updateMenu()
        
        // Observe changes to update menu dynamically
        AppWatcher.shared.$isTrusted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
            .store(in: &cancellables)
        
        // Check permissions on launch
        if !AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openSettings()
            }
        }
    }
    
    func updateMenu() {
        let menu = NSMenu()
        
        let isTrusted = AppWatcher.shared.isTrusted
        
        if !isTrusted {
            let permItem = NSMenuItem(title: "⚠️ Permission Needed", action: #selector(openSettings), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        let statusTitle = "Status: \(isTrusted ? "Running" : "Setup Required")"
        let statusItem = NSMenuItem(title: statusTitle, action: #selector(openSettings), keyEquivalent: "")
        statusItem.target = self
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit AutoQuit", action: #selector(terminateApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = menu
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 380),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.center()
            window.title = "AutoQuit Settings"
            window.contentView = NSHostingView(rootView: ContentView(watcher: AppWatcher.shared))
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func terminateApp() {
        NSApplication.shared.terminate(nil)
    }
}

@main
struct AutoQuitEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
