import SwiftUI

/// A preview-only page picker: dragging never changes reading progress.
struct ReaderPageJumpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    let current: Int
    let total: Int
    let onJump: (Int) -> Void
    @State private var target: Int
    @State private var input: String
    @FocusState private var numberFocused: Bool

    init(current: Int, total: Int, onJump: @escaping (Int) -> Void) {
        let maximum = max(1, total)
        let start = min(max(1, current), maximum)
        self.current = start
        self.total = maximum
        self.onJump = onJump
        _target = State(initialValue: start)
        _input = State(initialValue: String(start))
    }

    private var validInput: Int? {
        guard let value = Int(input), (1...total).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Страница \(target) из \(total)")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(palette.text)
                        Text("Текущая позиция: \(current) · \(target == current ? "без изменений" : target > current ? "+\(target-current) стр." : "−\(current-target) стр.")")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                    }

                    if total > 1 {
                        Slider(value: Binding(
                            get: { Double(target) },
                            set: { setTarget(Int($0.rounded())) }
                        ), in: 1...Double(total), step: 1)
                        .tint(palette.accent)
                        .accessibilityLabel("Выбор страницы")

                        HStack {
                            Text("1")
                            Spacer()
                            Text("\(total)")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.secondary)
                    }

                    HStack(spacing: 8) {
                        jumpButton("−50", delta: -50)
                        jumpButton("−10", delta: -10)
                        jumpButton("+10", delta: 10)
                        jumpButton("+50", delta: 50)
                    }

                    HStack {
                        Button("В начало") { setTarget(1) }
                        Spacer()
                        Button("В конец") { setTarget(total) }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .tint(palette.accent)

                    HStack {
                        Text("Номер страницы")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.text)
                        Spacer()
                        TextField("1–\(total)", text: $input)
                            .keyboardType(.numberPad)
                            .focused($numberFocused)
                            .multilineTextAlignment(.center)
                            .monospacedDigit()
                            .frame(width: 105)
                            .padding(10)
                            .background(palette.surfaceHigh, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(palette.text)
                            .onChange(of: input) { _, value in
                                if let number = Int(value), (1...total).contains(number) {
                                    target = number
                                }
                            }
                    }
                    if validInput == nil {
                        Text("Введи число от 1 до \(total).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        guard let page = validInput else { return }
                        numberFocused = false
                        onJump(page)
                        dismiss()
                    } label: {
                        Label("Перейти", systemImage: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(validInput == nil)

                    Text("Промежуточные страницы не отмечаются как прочитанные.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Перейти к странице")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .preferredColorScheme(palette.colorScheme)
    }

    private func setTarget(_ value: Int) {
        target = min(max(1, value), total)
        input = String(target)
    }

    private func jumpButton(_ title: String, delta: Int) -> some View {
        Button {
            numberFocused = false
            setTarget(target + delta)
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(palette.surfaceHigh, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.accent)
        .disabled(delta < 0 ? target <= 1 : target >= total)
    }
}
