import AppKit
import SwiftUI

@MainActor
final class ViewState: ObservableObject {
    @Published var title = "Готово к диктовке"
    @Published var detail = "⌘ + ` — начать и закончить"
    @Published var recording = false
    @Published var busy = false
    @Published var cancellable = false
    @Published var level: CGFloat = 0
    @Published var seconds = 0
    @Published var modelStatus = "Подготовка модели…"
    @Published var progress: Double?
    @Published var modelReady = false
    @Published var modelFailed = false
    @Published var microphoneGranted = false
    @Published var accessibilityGranted = false
    @Published var hotkeyError: String?
}

struct OverlayView: View {
    @ObservedObject var state: ViewState
    var cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 14) {
            if state.recording {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<7) { index in
                        Capsule().fill(Color.accentColor)
                            .frame(width: 4, height: reduceMotion ? 10 : 4 + state.level * CGFloat([15, 24, 32, 21, 29, 18, 12][index]))
                            .opacity(reduceMotion ? 0.35 + state.level * 0.65 : 1)
                    }
                }.frame(width: 46, height: 36)
                    .animation(.easeOut(duration: 0.09), value: state.level)
                    .accessibilityLabel("Уровень звука микрофона")
            } else if state.busy {
                ProgressView().controlSize(.small).frame(width: 30)
            } else {
                Image(systemName: "clipboard").font(.system(size: 22)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(state.title).font(.system(size: 14, weight: .semibold))
                    if state.recording {
                        Text(String(format: "%02d:%02d", state.seconds / 60, state.seconds % 60))
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                if !state.detail.isEmpty {
                    Text(state.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if state.cancellable {
                Button(action: cancel) { Image(systemName: "xmark.circle.fill").font(.system(size: 19)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Отменить диктовку").accessibilityLabel("Отменить диктовку")
            }
        }
        .padding(16).frame(width: 380, height: 78)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.1), lineWidth: 1))
    }
}

struct SetupView: View {
    @ObservedObject var state: ViewState
    var microphone: () -> Void
    var accessibility: () -> Void
    var retry: () -> Void
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice Input").font(.title2.bold())
                    Text("Говорите. Текст появится в вашем приложении.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(state.modelReady ? "Whisper Turbo готова" : state.modelStatus, systemImage: state.modelReady ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                if !state.modelReady && !state.modelFailed {
                    if let progress = state.progress { ProgressView(value: progress) }
                    else { ProgressView().controlSize(.small) }
                }
                Text("Распознавание на Mac. Интернет нужен только для первоначального скачивания модели (~626 МБ и файлы словаря).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if state.modelFailed { Button("Повторить загрузку", action: retry) }
            }
            Divider()
            permissionRow("Микрофон", detail: "Нужен для записи вашего голоса.", granted: state.microphoneGranted, action: microphone)
            permissionRow("Универсальный доступ", detail: "Для вставки в исходное поле. Без доступа текст остаётся в буфере.", granted: state.accessibilityGranted, action: accessibility)
            if let error = state.hotkeyError { Text(error).foregroundStyle(.red).font(.callout) }
            VStack(alignment: .leading, spacing: 7) {
                Text("⌘ + ` / ё").font(.system(size: 22, weight: .medium, design: .rounded))
                Text("Первое нажатие — запись, второе — распознавание. Сочетание действует, пока приложение запущено, и заменяет переключение окон.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text("Русский язык · Без истории записей").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Свернуть в меню", action: close).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 490)
    }
    private func permissionRow(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Разрешить", action: action) }
        }
    }
}

@MainActor
final class OverlayPanel: NSPanel {
    init(state: ViewState, cancel: @escaping () -> Void) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 78), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        level = .floating; hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: OverlayView(state: state, cancel: cancel))
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func show(on screen: NSScreen) {
        let bounds = screen.visibleFrame
        setFrameOrigin(NSPoint(x: bounds.midX - frame.width / 2, y: bounds.minY + 24))
        orderFrontRegardless()
    }
}
