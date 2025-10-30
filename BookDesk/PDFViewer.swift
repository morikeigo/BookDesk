//  PDFViewer.swift
//  BookDesk
//
//  A standalone SwiftUI wrapper around PDFKit to display PDFs in a sheet.

import SwiftUI
import PDFKit

public struct PDFViewer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var horizontal = false

    public init(url: URL) { self.url = url }

    public var body: some View {
        ZStack(alignment: .top) {
            PDFKitView(url: url, horizontal: horizontal)
                .ignoresSafeArea()

            // Top overlay toolbar
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("閉じる", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                }
                Spacer()
                Picker("方向", selection: $horizontal) {
                    Text("縦").tag(false)
                    Text("横").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding()
        }
    }
}

public struct PDFKitView: UIViewRepresentable {
    let url: URL
    let horizontal: Bool

    public init(url: URL, horizontal: Bool) {
        self.url = url
        self.horizontal = horizontal
    }

    public class Coordinator {
        let url: URL
        var granted = false
        var pageChangeObserver: NSObjectProtocol?
        let defaults = UserDefaults.standard

        init(url: URL) { self.url = url }

        var storageKey: String {
            // URL ごとに一意なキー
            "PDFLastPage::" + url.absoluteString
        }

        func saveCurrentPageIndex(from view: PDFView) {
            guard let doc = view.document,
                  let page = view.currentPage else { return }
            let index = doc.index(for: page)
            defaults.set(index, forKey: storageKey)
        }

        func restorePageIfAvailable(on view: PDFView) {
            guard let doc = view.document else { return }
            let saved = defaults.object(forKey: storageKey) as? Int ?? 0
            guard saved >= 0, saved < doc.pageCount,
                  let page = doc.page(at: saved) else { return }
            // go(to:) は該当ページの先頭に移動します
            view.go(to: page)
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    public func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = horizontal ? .horizontal : .vertical
        view.usePageViewController(horizontal)

        context.coordinator.granted = url.startAccessingSecurityScopedResource()
        if context.coordinator.granted == false {
            // Attempt to start access anyway for non-security-scoped URLs (no-op if not applicable)
            _ = url.startAccessingSecurityScopedResource()
        }

        if let doc = PDFDocument(url: url) {
            view.document = doc

            // 1) 前回ページを復元
            context.coordinator.restorePageIfAvailable(on: view)

            // 2) ページ変更を監視して保存
            context.coordinator.pageChangeObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak view] _ in
                guard let view = view else { return }
                context.coordinator.saveCurrentPageIndex(from: view)
            }
        } else {
            // If it fails, try resolving bookmark data if the URL carries it via resource values (defensive)
            view.document = nil
        }

        return view
    }

    public func updateUIView(_ uiView: PDFView, context: Context) {
        let newDirection: PDFDisplayDirection = horizontal ? .horizontal : .vertical
        if uiView.displayDirection != newDirection {
            uiView.displayDirection = newDirection
            uiView.usePageViewController(horizontal)
        }
    }

    public static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        if let token = coordinator.pageChangeObserver {
            NotificationCenter.default.removeObserver(token)
            coordinator.pageChangeObserver = nil
        }
        if coordinator.granted { coordinator.url.stopAccessingSecurityScopedResource() }
    }
}
