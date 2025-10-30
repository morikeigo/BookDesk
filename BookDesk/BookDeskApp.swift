//
//  BookDeskApp.swift
//  BookDesk
//
//  Created by user on 2025/10/25.
//

import SwiftUI
import CoreData

@main
struct BookDeskApp: App {
    //let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
               // .environment(\.managedObjectContext)
            //, persistenceController.container.viewContext)
        }
    }
}
