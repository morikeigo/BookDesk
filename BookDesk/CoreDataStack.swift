import Foundation
import CoreData
import UIKit

final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    var context: NSManagedObjectContext { container.viewContext }

    private init() {
        let model = CoreDataStack.makeModel()
        container = NSPersistentContainer(name: "BookDeskModel", managedObjectModel: model)
        container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unresolved Core Data error: \(error)")
            }
            self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }
    }

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Card entity
        let cardEntity = NSEntityDescription()
        cardEntity.name = "Card"
        cardEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        func attribute(_ name: String, _ type: NSAttributeType, _ isOptional: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = isOptional
            return a
        }

        cardEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("bookmark", .binaryDataAttributeType, true),
            attribute("path", .stringAttributeType, true),
            attribute("thumbnail", .binaryDataAttributeType, true),
            attribute("posX", .doubleAttributeType),
            attribute("posY", .doubleAttributeType),
            attribute("width", .doubleAttributeType),
            attribute("height", .doubleAttributeType),
            attribute("deskIndex", .integer16AttributeType),
            attribute("zIndex", .integer32AttributeType)
        ]

        model.entities = [cardEntity]
        return model
    }

    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do { try context.save() } catch {
                print("Core Data save error: \(error)")
            }
        }
    }

    // MARK: - Persistence API for PDFCard (consolidated)
    func saveCards(desks: [[PDFCard]]) {
        let ctx = container.viewContext
        // Clear existing records
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Card")
        let delete = NSBatchDeleteRequest(fetchRequest: fetch)
        do { try ctx.execute(delete) } catch { print("Core Data batch delete error: \(error)") }

        guard let entity = NSEntityDescription.entity(forEntityName: "Card", in: ctx) else {
            return
        }

        for (deskIdx, desk) in desks.enumerated() {
            for (z, card) in desk.enumerated() {
                let obj = NSManagedObject(entity: entity, insertInto: ctx)
                obj.setValue(card.id, forKey: "id")
                // Store bookmark if possible (preferred), and path as fallback
                if let bookmark = try? card.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    obj.setValue(bookmark, forKey: "bookmark")
                }
                obj.setValue(card.url.path, forKey: "path")
                // Geometry
                obj.setValue(Double(card.position.x), forKey: "posX")
                obj.setValue(Double(card.position.y), forKey: "posY")
                obj.setValue(Double(card.size.width), forKey: "width")
                obj.setValue(Double(card.size.height), forKey: "height")
                obj.setValue(Int16(deskIdx), forKey: "deskIndex")
                obj.setValue(Int32(z), forKey: "zIndex")
                // Thumbnail
                if let data = card.thumbnail.pngData() {
                    obj.setValue(data, forKey: "thumbnail")
                }
            }
        }

        saveContext()
    }

    func loadCards() -> [[PDFCard]] {
        var result: [[PDFCard]] = Array(repeating: [], count: 5)
        let ctx = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Card")
        var needsSave = false

        do {
            let objects = try ctx.fetch(request)
            for obj in objects {
                // Resolve URL from bookmark first, then path
                var resolvedURL: URL? = nil
                if let bookmark = obj.value(forKey: "bookmark") as? Data {
                    var stale = false
                    if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                        resolvedURL = url
                        if stale {
                            if let newBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                                obj.setValue(newBookmark, forKey: "bookmark")
                                needsSave = true
                            }
                        }
                    }
                }
                if resolvedURL == nil, let path = obj.value(forKey: "path") as? String {
                    resolvedURL = URL(fileURLWithPath: path)
                }
                guard let url = resolvedURL else { continue }

                // Geometry
                let posX = obj.value(forKey: "posX") as? Double ?? 0
                let posY = obj.value(forKey: "posY") as? Double ?? 0
                let width = obj.value(forKey: "width") as? Double ?? 180
                let height = obj.value(forKey: "height") as? Double ?? 240
                let deskIndex = Int(obj.value(forKey: "deskIndex") as? Int16 ?? 0)

                // Thumbnail
                let thumbnail: UIImage
                if let data = obj.value(forKey: "thumbnail") as? Data, let image = UIImage(data: data) {
                    thumbnail = image
                } else {
                    thumbnail = CoreDataStack.makePlaceholderThumbnail(size: CGSize(width: width, height: height))
                }

                // ID
                let id = (obj.value(forKey: "id") as? UUID) ?? UUID()

                let card = PDFCard(
                    id: id,
                    url: url,
                    thumbnail: thumbnail,
                    position: CGPoint(x: posX, y: posY),
                    size: CGSize(width: width, height: height)
                )

                let clampedDesk = max(0, min(4, deskIndex))
                result[clampedDesk].append(card)
            }
        } catch {
            print("Core Data fetch error: \(error)")
        }

        if needsSave { saveContext() }

        // Optional: maintain a stable order if needed (e.g., by y position)
        for i in 0..<result.count {
            result[i].sort { lhs, rhs in
                return lhs.position.y < rhs.position.y
            }
        }

        return result
    }

    private static func makePlaceholderThumbnail(size: CGSize) -> UIImage {
        let size = CGSize(width: max(8, size.width), height: max(8, size.height))
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.systemGray5.setFill()
            ctx.fill(rect)
            let pdfRect = rect.insetBy(dx: size.width * 0.2, dy: size.height * 0.25)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: pdfRect, cornerRadius: 6).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: min(18, size.width * 0.15)),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: paragraph
            ]
            let text = NSAttributedString(string: "PDF", attributes: attrs)
            let textSize = text.size()
            let origin = CGPoint(x: (size.width - textSize.width)/2, y: (size.height - textSize.height)/2)
            text.draw(at: origin)
        }
    }
}
