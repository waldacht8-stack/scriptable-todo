import SwiftUI
import WidgetKit
import AppIntents

// ウィジェットの見た目。アプリ本体の「ウィジェットの見本」画面でも同じものを表示して、
// シミュレーターのスクリーンショットで見た目を確かめられるようにする。

struct TodoWidgetView: View {
    let items: [TodoItem]
    let groupOK: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODO").font(.headline)
                Spacer()
                Text("\(items.filter { !$0.done }.count)件").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(items.prefix(3)) { item in
                Button(intent: ToggleTodoIntent(id: item.id)) {
                    HStack(spacing: 6) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        Text(item.title).lineLimit(1).strikethrough(item.done)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if !groupOK {
                Text("⚠︎ App Group なし").font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}

struct WakeWidgetView: View {
    let state: WakeState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("起床").font(.headline)
            if let at = state.checkedInAt, Calendar.current.isDateInToday(at) {
                Label("チェックイン済み \(at.formatted(date: .omitted, time: .shortened))", systemImage: "sun.max.fill")
                    .font(.subheadline)
            } else {
                Button(intent: CheckInIntent()) {
                    Label("起きた！", systemImage: "alarm")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.tint, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
