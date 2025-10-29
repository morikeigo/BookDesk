//  DraggablePDFCard.swift
//  BookDesk
//
//  A standalone draggable PDF card view used in the desk canvas.

import SwiftUI
import UIKit
import Foundation

// MARK: - Model
struct PDFCard: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var thumbnail: UIImage
    var position: CGPoint
    var size: CGSize
}

struct DraggablePDFCard: View {
    // MARK: - Notifications
    static let didChange = Notification.Name("DraggablePDFCard.didChange")
    static let didRequestOpen = Notification.Name("DraggablePDFCard.didRequestOpen")
    //static let didRequestShare = Notification.Name("DraggablePDFCard.didRequestShare")
    static let didRequestDelete = Notification.Name("DraggablePDFCard.didRequestDelete")
    static let didDragEnded = Notification.Name("DraggablePDFCard.didDragEnded")
    
    @State private var card: PDFCard
    @State private var dragStart: CGPoint? = nil
    // Tracks which PDF page was last viewed for this card.
    @State private var lastViewedPageIndex: Int = 0

    init(card: PDFCard,
         initialPageIndex: Int = 0) {
        self._card = State(initialValue: card)
        self._lastViewedPageIndex = State(initialValue: initialPageIndex)
    }

    var body: some View {
        Image(uiImage: card.thumbnail)
            .resizable()
            .scaledToFit()
            .frame(width: card.size.width, height: card.size.height)
            .shadow(radius: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.secondary.opacity(0.6))
            )
            .position(card.position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStart == nil { dragStart = card.position }
                        if let start = dragStart {
                            card.position = CGPoint(
                                x: start.x + value.translation.width,
                                y: start.y + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        dragStart = nil
                        NotificationCenter.default.post(name: DraggablePDFCard.didDragEnded, object: card)
                        NotificationCenter.default.post(name: DraggablePDFCard.didChange, object: card)
                    }
            )
            .accessibilityLabel(Text(card.url.lastPathComponent))
            .onTapGesture(count: 2) {
                NotificationCenter.default.post(name: DraggablePDFCard.didRequestOpen, object: card)
            }
            .contextMenu {
                ShareLink(item: card.url) {
                    Label("共有", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    NotificationCenter.default.post(name: DraggablePDFCard.didRequestDelete, object: card)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
    }
}
