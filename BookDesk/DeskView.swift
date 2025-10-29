//  DeskView.swift
//  BookDesk
//
//  A desk page that renders background, cards, and an add button.

import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers

struct DeskView: View {
    let deskIndex: Int
    let backgroundColor: Color
    @Binding var cards: [PDFCard]
    //var onOpen: (PDFCard) -> Void
    var onDragEnded: () -> Void
    @State private var showImporter = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                ZStack {
                    backgroundColor
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.8),
                            Color.black
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea(.container, edges: .all)

                // Cards layer
                ZStack {
                    ForEach(cards, id: \.id) { value in
                        DraggablePDFCard(card: value)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(14)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
                        )
                }
                .accessibilityLabel("Add PDF")
                .padding()
                .zIndex(10)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    let canvas = safeCanvasSize(geo.size)
                    var newCards: [PDFCard] = []
                    for (i, url) in urls.enumerated() {
                        let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }

                        let localURL = copyIntoAppSandbox(from: url) ?? url
                        if let card = makeCard(from: localURL, in: canvas, count: cards.count + i) {
                            newCards.append(card)
                        }
                    }
                    if !newCards.isEmpty {
                        cards.append(contentsOf: newCards)
                        onDragEnded()
                    }
                case .failure(let error):
                    print("Import failed: \(error.localizedDescription)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: DraggablePDFCard.didRequestDelete)) { note in
                guard let card = note.object as? PDFCard, let idx = cards.firstIndex(where: { $0.id == card.id }) else { return }
                cards.remove(at: idx)
                onDragEnded()
            }
            .onReceive(NotificationCenter.default.publisher(for: DraggablePDFCard.didDragEnded)) { note in
                guard let updated = note.object as? PDFCard,
                      let idx = cards.firstIndex(where: { $0.id == updated.id }) else { return }
                cards[idx] = updated
                onDragEnded()
            }
        }
    }

    // MARK: - Helpers
    // Copies an external PDF into the app's sandbox (Documents/ImportedPDFs) and returns the local URL.
    private func copyIntoAppSandbox(from sourceURL: URL) -> URL? {
        let fm = FileManager.default
        do {
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = docs.appendingPathComponent("ImportedPDFs", isDirectory: true)
            if !fm.fileExists(atPath: folder.path) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            }

            let originalName = sourceURL.lastPathComponent
            let base = (originalName as NSString).deletingPathExtension
            let ext = (originalName as NSString).pathExtension

            var dest = folder.appendingPathComponent(originalName)
            if fm.fileExists(atPath: dest.path) {
                let unique = base + "-" + UUID().uuidString.prefix(8)
                dest = folder.appendingPathComponent(unique).appendingPathExtension(ext)
            }

            // If the source is already inside our folder, just return it
            if sourceURL.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL {
                return sourceURL
            }

            // Remove any partial file before copying
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
            try fm.copyItem(at: sourceURL, to: dest)
            return dest
        } catch {
            print("Copy into sandbox failed: \(error)")
            return nil
        }
    }

    private func safeCanvasSize(_ size: CGSize) -> CGSize {
        if size.width > 0 && size.height > 0 { return size }
        let bounds = UIScreen.main.bounds
        return CGSize(width: max(320, bounds.width), height: max(480, bounds.height))
    }

    private func makeThumbnail(for url: URL, targetSize: CGSize) -> UIImage {
        if let doc = PDFDocument(url: url), let page = doc.page(at: 0) {
            var thumb = page.thumbnail(of: targetSize, for: .cropBox)
            if thumb.size == .zero {
                let rect = page.bounds(for: .cropBox)
                let scale = min(targetSize.width / rect.width, targetSize.height / rect.height)
                let out = CGSize(width: rect.width * scale, height: rect.height * scale)
                let renderer = UIGraphicsImageRenderer(size: out)
                thumb = renderer.image { ctx in
                    UIColor.clear.setFill()
                    ctx.fill(CGRect(origin: .zero, size: out))
                    if let cg = page.pageRef {
                        let context = ctx.cgContext
                        context.saveGState()
                        context.translateBy(x: 0, y: out.height)
                        context.scaleBy(x: scale, y: -scale)
                        context.drawPDFPage(cg)
                        context.restoreGState()
                    }
                }
            }
            return thumb
        }
        // Simple inline placeholder (no separate helper required)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: targetSize)
            UIColor.systemGray5.setFill()
            ctx.fill(rect)
            let pdfRect = rect.insetBy(dx: targetSize.width * 0.2, dy: targetSize.height * 0.25)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: pdfRect, cornerRadius: 6).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: min(18, targetSize.width * 0.15)),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: paragraph
            ]
            let text = NSAttributedString(string: "PDF", attributes: attrs)
            let textSize = text.size()
            let textOrigin = CGPoint(x: (targetSize.width - textSize.width)/2, y: (targetSize.height - textSize.height)/2)
            text.draw(at: textOrigin)
        }
    }

    
    private func makeCard(from url: URL, in canvasSize: CGSize, count: Int) -> PDFCard? {
        // We don't need to open the document here; thumbnail creation handles failures.

        // Target thumbnail size (kept modest; auto-fits in card frame)
        let target = CGSize(width: 180, height: 240)
        let thumb = makeThumbnail(for: url, targetSize: target)

        let offset: CGFloat = CGFloat(count % 5) * 24.0
        let startPos = CGPoint(
            x: max(100, min(canvasSize.width - 100, canvasSize.width / 2 + offset)),
            y: max(140, min(canvasSize.height - 140, canvasSize.height / 2 + offset))
        )
        return PDFCard(
            id: UUID(),
            url: url,
            thumbnail: thumb,
            position: startPos,
            size: target
        )
    }
}

