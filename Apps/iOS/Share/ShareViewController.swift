import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Saves what you share as a task. Perch picks it up the next time it opens.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareForm(
            load: { [weak self] in await self?.sharedText() ?? "" },
            finish: { [weak self] text in
                if let text { self?.save(text) }
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        ))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func sharedText() async -> String {
        var parts: [String] = []
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                parts.append(url.absoluteString)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                parts.append(text)
            }
        }
        return parts.joined(separator: "\n")
    }

    private func save(_ text: String) {
        guard let inbox = SharedStore.inboxURL else { return }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try? text.write(to: inbox.appendingPathComponent(UUID().uuidString + ".txt"), atomically: true, encoding: .utf8)
    }
}

private struct ShareForm: View {
    let load: () async -> String
    let finish: (String?) -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $text, axis: .vertical).lineLimit(3...8)
                Text("The first line becomes the task. Use tomorrow, #Personal, or !p1 as usual.").font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Add to Perch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { finish(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { finish(text) }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task { text = await load() }
    }
}
