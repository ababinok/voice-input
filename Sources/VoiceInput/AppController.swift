import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI
import VoiceInputCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    let state = ViewState()
    let speech = SpeechEngine()
    let recorder = Recorder()
    let insertion = TextInsertion()
    let hotkey = HotKey()
    var session = DictationSession()
    var target: TextInsertion.Target?
    var statusItem: NSStatusItem!
    var panel: OverlayPanel!
    var setupWindow: NSWindow?
    var ticker: Timer?
    var startedAt = Date()
    var recognition: Task<Void, Never>?
    var preparation: Task<Void, Never>?
    var dismissal: Task<Void, Never>?
    var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Do not run two copies with competing hotkeys and microphones.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1 { NSApp.terminate(nil); return }
        panel = OverlayPanel(state: state) { [weak self] in self?.cancel() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Input")
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Voice Input — настройки", action: #selector(showSetup), keyEquivalent: "")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Завершить Voice Input", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        hotkey.onPress = { [weak self] in self?.toggle() }
        do { try hotkey.register() } catch { state.hotkeyError = error.localizedDescription }
        recorder.onDeviceChange = { [weak self] in
            guard let self, self.session.phase == .recording else { return }
            _ = self.recorder.stop(); self.ticker?.invalidate(); self.session.fail()
            self.notify("Микрофон отключён", detail: "Проверьте устройство и начните запись заново.")
        }
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        if !UserDefaults.standard.bool(forKey: "setupSeen") || !state.microphoneGranted || state.hotkeyError != nil { showSetup() }
        prepare()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return true
    }
    func refreshPermissions() {
        state.microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        state.accessibilityGranted = AXIsProcessTrusted()
    }
    @objc func showSetup() {
        if setupWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Voice Input"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SetupView(state: state,
                microphone: { [weak self] in self?.requestMicrophone() },
                accessibility: { [weak self] in self?.requestAccessibility() },
                retry: { [weak self] in self?.prepare() },
                close: { [weak self] in self?.setupWindow?.orderOut(nil) }))
            window.center(); setupWindow = window
        }
        UserDefaults.standard.set(true, forKey: "setupSeen")
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }
    func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in Task { @MainActor in self?.refreshPermissions() } }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func prepare() {
        guard preparation == nil, !state.modelReady else { return }
        state.modelFailed = false
        preparation = Task { [weak self] in
            guard let self else { return }
            do {
                try await speech.prepare { [weak self] message, progress in
                    Task { @MainActor in self?.state.modelStatus = message; self?.state.progress = progress }
                }
                state.modelReady = true; state.modelStatus = "Модель готова"; state.progress = nil
            } catch {
                state.modelFailed = true; state.modelStatus = "Не удалось подготовить модель: \(error.localizedDescription)"; state.progress = nil
                showSetup()
            }
            preparation = nil
        }
    }
    func toggle() {
        switch session.phase {
        case .recording: stopAndRecognize()
        case .transcribing, .cancelling: break
        case .idle:
            guard recognition == nil else { return }
            refreshPermissions()
            guard state.modelReady, state.microphoneGranted, state.hotkeyError == nil else { showSetup(); return }
            dismissal?.cancel()
            target = insertion.capture()
            guard session.start() != nil else { return }
            do { try recorder.start() }
            catch { session.fail(); notify("Запись не началась", detail: error.localizedDescription); return }
            startedAt = Date(); state.seconds = 0; state.level = 0
            state.title = "Слушаю…"; state.detail = "⌘ + ` — закончить"; state.recording = true; state.busy = false; state.cancellable = true
            panel.show(on: target?.screen ?? NSScreen.main!)
            statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Идёт запись")
            ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.session.phase == .recording else { return }
                    self.state.seconds = Int(Date().timeIntervalSince(self.startedAt))
                    let db = 20 * log10(max(self.recorder.level, 0.00001))
                    self.state.level = CGFloat(max(0, min(1, (db + 55) / 40)))
                    if self.state.seconds >= 30 * 60 { self.stopAndRecognize() }
                }
            }
        }
    }
    func stopAndRecognize() {
        guard session.stop() else { return }
        ticker?.invalidate(); ticker = nil
        let audio = recorder.stop()
        state.recording = false; state.busy = true; state.title = "Распознаю…"; state.detail = ""; state.level = 0
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Input")
        guard audio.samples.count >= 4800, audio.peak > 0.001 else {
            session.fail(); notify("Речь не обнаружена", detail: "Попробуйте говорить ближе к микрофону."); return
        }
        let token = session.id
        let destination = target
        recognition = Task { [weak self] in
            guard let self else { return }
            defer { recognition = nil }
            do {
                let text = try await speech.transcribe(audio.samples)
                guard session.finish(token), !Task.isCancelled else { finishCancellation(); return }
                if text.isEmpty { notify("Речь не обнаружена", detail: "Текст не скопирован.") }
                else {
                    state.cancellable = false
                    let pasted = await insertion.copyAndPaste(text, into: destination)
                    if pasted {
                        state.busy = false
                        panel.orderOut(nil)
                        target = nil
                    } else {
                        notify("Текст в буфере — нажмите ⌘V", detail: "", duration: .seconds(2))
                    }
                }
            } catch {
                let wasCancelled = session.phase == .cancelling || Task.isCancelled
                _ = session.finish(token)
                if wasCancelled { finishCancellation() }
                else { notify("Не удалось распознать", detail: error.localizedDescription) }
            }
        }
    }
    func cancel() {
        dismissal?.cancel()
        if session.phase == .recording {
            _ = recorder.stop(); ticker?.invalidate(); ticker = nil
            session.cancel(); finishCancellation()
        } else if session.phase == .transcribing {
            session.cancel(); recognition?.cancel()
            state.title = "Отменяю…"; state.detail = "Текст не будет вставлен"; state.cancellable = false
        }
    }
    func finishCancellation() {
        state.recording = false; state.busy = false; state.cancellable = false
        panel.orderOut(nil); target = nil
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Input")
    }
    func notify(_ title: String, detail: String, duration: Duration = .seconds(4)) {
        dismissal?.cancel()
        state.title = title; state.detail = detail; state.recording = false; state.busy = false; state.cancellable = false
        panel.show(on: target?.screen ?? NSScreen.main!)
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        hotkey.unregister(); _ = recorder.stop(); recognition?.cancel(); preparation?.cancel()
        ticker?.invalidate(); permissionTimer?.invalidate(); dismissal?.cancel()
    }
}
