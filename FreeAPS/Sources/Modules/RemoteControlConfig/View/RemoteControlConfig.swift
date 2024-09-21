import Combine
import Foundation
import SwiftUI
import Swinject
import UIKit

extension RemoteControlConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State private var selectedVerboseHint: String?
        @State private var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var isCopied: Bool = false

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Remote Control")) {
                    Toggle(isOn: $state.isTRCEnabled) {
                        Text("Enable Remote Control")
                    }
                    Text(
                        "Remote commands allow Trio to receive instructions, such as boluses and temp targets, from LoopFollow."
                    )
                    .font(.footnote)
                    .foregroundColor(.gray)
                }

                Section(header: Text("Shared Secret")) {
                    TextField("Enter Shared Secret", text: $state.sharedSecret)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .padding(8)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)

                    Button(action: {
                        UIPasteboard.general.string = state.sharedSecret
                        isCopied = true
                    }) {
                        Label("Copy Secret", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .alert(isPresented: $isCopied) {
                        Alert(
                            title: Text("Copied"),
                            message: Text("Shared Secret copied to clipboard"),
                            dismissButton: .default(Text("OK"))
                        )
                    }

                    Button(action: {
                        state.generateNewSharedSecret()
                    }) {
                        Label("Generate Secret", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Remote Control")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
