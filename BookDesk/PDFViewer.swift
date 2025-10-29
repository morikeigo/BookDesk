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
    @State private var drawEnabled = false

    public init(url: URL) { self.url = url }

    public var body: some View {
        ZStack(alignment: .top) {
            PDFKitView(url: url, horizontal: horizontal, drawEnabled: drawEnabled)
                .ignoresSafeArea()

            // Top overlay toolbar
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("閉じる", systemImage: "xmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                Toggle(isOn: $drawEnabled) {
                    Image(systemName: drawEnabled ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                        .imageScale(.large)
                        .accessibilityLabel("ペン")
                }
                .toggleStyle(.button)
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
    let drawEnabled: Bool

    public init(url: URL, horizontal: Bool, drawEnabled: Bool) {
        self.url = url
        self.horizontal = horizontal
        self.drawEnabled = drawEnabled
    }

    final class DrawingCanvas: UIView {
        weak var pdfView: PDFView?
        var isDrawing = false
        var lineWidth: CGFloat = 3
        var strokeColor: UIColor = .systemBlue

        private var points: [CGPoint] = []
        private let preview = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            isUserInteractionEnabled = true
            preview.fillColor = UIColor.clear.cgColor
            preview.strokeColor = strokeColor.cgColor
            preview.lineWidth = lineWidth
            preview.lineJoin = .round
            preview.lineCap = .round
            layer.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard isDrawing, let t = touches.first else { return }
            points = [t.location(in: self)]
            updatePreview()
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard isDrawing, let t = touches.first else { return }
            points.append(t.location(in: self))
            updatePreview()
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard isDrawing else { return }
            commitStroke()
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard isDrawing else { return }
            points.removeAll(); updatePreview()
        }

        private func updatePreview() {
            let path = UIBezierPath()
            guard let first = points.first else { preview.path = nil; return }
            path.move(to: first)
            for p in points.dropFirst() { path.addLine(to: p) }
            preview.strokeColor = strokeColor.cgColor
            preview.lineWidth = lineWidth
            preview.path = path.cgPath
        }

        private func commitStroke() {
            defer { points.removeAll(); updatePreview() }
            guard let pdfView = pdfView, let first = points.first,
                  let page = pdfView.page(for: first, nearest: true) else { return }

            let pagePath = UIBezierPath()
            pagePath.move(to: pdfView.convert(first, to: page))
            for p in points.dropFirst() {
                pagePath.addLine(to: pdfView.convert(p, to: page))
            }
            pagePath.lineWidth = max(0.5, lineWidth / max(1, pdfView.scaleFactor))

            let bounds = pagePath.bounds.insetBy(dx: -lineWidth, dy: -lineWidth)
            let ink = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            ink.color = strokeColor
            ink.add(pagePath)
            page.addAnnotation(ink)
        }
    }

    public class Coordinator {
        let url: URL
        var granted = false
        init(url: URL) { self.url = url }
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
        } else {
            // If it fails, try resolving bookmark data if the URL carries it via resource values (defensive)
            view.document = nil
        }

        // Add drawing overlay
        let canvasTag = 4242
        if view.viewWithTag(canvasTag) == nil {
            let canvas = DrawingCanvas(frame: view.bounds)
            canvas.tag = canvasTag
            canvas.pdfView = view
            canvas.isUserInteractionEnabled = true
            canvas.isDrawing = drawEnabled
            canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(canvas)
        }

        return view
    }

    public func updateUIView(_ uiView: PDFView, context: Context) {
        let newDirection: PDFDisplayDirection = horizontal ? .horizontal : .vertical
        if uiView.displayDirection != newDirection {
            uiView.displayDirection = newDirection
            uiView.usePageViewController(horizontal)
        }
        if let canvas = uiView.viewWithTag(4242) as? DrawingCanvas {
            canvas.isDrawing = drawEnabled
        }
    }

    public static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        if coordinator.granted { coordinator.url.stopAccessingSecurityScopedResource() }
    }
}

