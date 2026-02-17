import SwiftUI

struct StatusIcon: View {
    let state: RecordingState

    var body: some View {
        switch state {
        case .idle:
            Image(systemName: "waveform")
        case .recording:
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.multicolor)
        case .transcribing:
            Image(systemName: "ellipsis.circle")
                .symbolEffect(.variableColor.iterative)
        }
    }
}
