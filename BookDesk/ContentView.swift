//  ContentView.swift
//  BookDesk
//
//  Updated on 2025/10/25: Import PDF, show as draggable cards

import SwiftUI
import UIKit
import PDFKit
import CoreData

private extension CGFloat { var double: Double { Double(self) } }
private extension Double { var cgFloat: CGFloat { CGFloat(self) } }

// MARK: - Main Content
struct ContentView: View {
    @State private var desks: [[PDFCard]] = Array(repeating: [], count: 5)
    @State private var currentDesk: Int = 0

    @State private var viewerItem: URLItem? = nil
    @State private var shareItem: URLItem? = nil
    @State private var didLoadFromStore = false

    private let deskColors: [Color] = [
        Color(hue: 0.58, saturation: 0.50, brightness: 1.00), // vivid blue tint
        Color(hue: 0.78, saturation: 0.50, brightness: 1.00), // vivid purple tint
        Color(hue: 0.36, saturation: 0.50, brightness: 1.00), // vivid green tint
        Color(hue: 0.06, saturation: 0.55, brightness: 1.00), // vivid orange tint
        Color(hue: 0.53, saturation: 0.50, brightness: 1.00)  // vivid cyan tint
    ]

    @AppStorage("DebugOverlayEnabled") private var debugOverlayEnabled: Bool = true

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Debug Helpers
    private func debugTotalCardsInMemory() -> Int {
        desks.reduce(0) { $0 + $1.count }
    }

    private func coreDataCardCount() -> Int {
        let ctx = CoreDataStack.shared.context
        let request = NSFetchRequest<NSManagedObject>(entityName: "Card")
        do { return try ctx.count(for: request) } catch { return -1 }
    }

    var body: some View {
        TabView(selection: $currentDesk) {
            ForEach(0..<5, id: \.self) { desk in
                DeskView(
                    deskIndex: desk,
                    backgroundColor: deskColors[desk % deskColors.count],
                    cards: $desks[desk],
                    onDragEnded: {
                        CoreDataStack.shared.saveCards(desks: desks)
                    }
                )
                .tag(desk)
            }
        }
        .ignoresSafeArea(.container, edges: .all)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .task {
            guard !didLoadFromStore else { return }
            let loaded = CoreDataStack.shared.loadCards()
            desks = loaded
            didLoadFromStore = true
        }
        .onReceive(NotificationCenter.default.publisher(for: DraggablePDFCard.didRequestOpen)) { note in
            guard let card = note.object as? PDFCard else { return }
            viewerItem = URLItem(url: card.url)
        }
        .overlay(alignment: .bottomLeading) {
            if debugOverlayEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mem: \(debugTotalCardsInMemory())")
                    Text("CoreData: \(coreDataCardCount())")
                    Text("Desk: \(currentDesk + 1)/5")
                }
                .font(.caption2)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding()
            }
        }
        .fullScreenCover(item: $viewerItem) { item in
            PDFViewer(url: item.url)
        }
    }

    // Fallback in case geo.size is zero at the time of import
    private func safeCanvasSize(_ size: CGSize) -> CGSize {
        if size.width > 0 && size.height > 0 { return size }
        let bounds = UIScreen.main.bounds
        return CGSize(width: max(320, bounds.width), height: max(480, bounds.height))
    }
}

private struct URLItem: Identifiable {
    let id = UUID()
    let url: URL
}
