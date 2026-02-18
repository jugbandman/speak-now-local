import SwiftUI

struct StatusIcon: View {
    let state: RecordingState
    @AppStorage(Constants.keyMenuBarIcon) private var iconChoice = Constants.defaultMenuBarIcon

    var body: some View {
        switch state {
        case .idle:
            idleIcon
        case .recording:
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
        case .transcribing:
            if #available(macOS 14.0, *) {
                Image(systemName: "ellipsis.circle")
                    .symbolEffect(.variableColor.iterative)
                    .font(.system(size: 14))
            } else {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
        }
    }

    @ViewBuilder
    private var idleIcon: some View {
        let choice = MenuBarIconChoice(rawValue: iconChoice) ?? .sparkles
        if choice.isEmoji {
            Text(choice.emojiText)
                .font(.system(size: 14))
        } else {
            Image(systemName: choice.sfSymbolName)
                .font(.system(size: 14))
        }
    }
}
