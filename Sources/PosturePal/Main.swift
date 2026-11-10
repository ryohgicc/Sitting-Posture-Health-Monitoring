import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var model: AppModel?
    static var showMain: (() -> Void)?
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApp.setActivationPolicy(.accessory)
        Self.showMain = { [weak self] in self?.openMain() }
        openMain()
    }
    func openMain() {
        guard let model = Self.model else { return }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 780,height: 820), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            w.title = "坐姿搭子"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainView(model: model))
            w.minSize = NSSize(width: 740,height: 740); w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) { Self.model?.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner,.list])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in Self.showMain?() }
        completionHandler()
    }
}

@main
struct PosturePalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model: AppModel
    init() {
        let value = AppModel()
        _model = StateObject(wrappedValue: value)
        AppDelegate.model = value
    }
    var body: some Scene {
        MenuBarExtra {
            Text("坐姿搭子 · \(model.captureState)")
            if model.validationMode { Text("验证模式，姿态通知未开启") }
            Button("打开状态与校准") { AppDelegate.showMain?() }
            Divider()
            if model.requested {
                if model.pauseUntil != nil { Button("恢复检测") { model.resume() } }
                else { Button("暂停检测30分钟") { model.pause() } }
                Button("停止检测（释放摄像头）") { model.stop() }
            } else { Button("开启监测…") { AppDelegate.showMain?() } }
            if model.muted { Button("恢复提醒") { model.unsnooze() } }
            else { Button("稍后提醒10分钟（摄像头仍工作）") { model.snooze() } }
            Toggle("活动提醒", isOn: $model.activityEnabled).onChange(of: model.activityEnabled) { model.save() }
            Button("我已活动，重置计时") { model.activityDone() }
            Divider()
            Button("退出") { model.shutdown(); NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: model.capturing ? "figure.seated.side" : "figure.seated.side.airbag.on")
        }
    }
}
