import SwiftUI

struct CostEstimateView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel

    var body: some View {
        let estimate = viewModel.costEstimate

        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "dollarsign.circle")
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(estimate.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let detail = estimate.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(settings.isMinimalistMode ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(viewModel.inputText.isEmpty ? 0.6 : 1.0))
        )
        .animation(.easeInOut(duration: 0.2), value: estimate.summary)
    }
}

struct CostEstimateView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = TTSViewModel()
        CostEstimateView()
            .environmentObject(viewModel)
            .environmentObject(viewModel.settings)
            .padding()
            .frame(width: 600)
    }
}
