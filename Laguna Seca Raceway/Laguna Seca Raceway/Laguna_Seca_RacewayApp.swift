//
//  Laguna_Seca_RacewayApp.swift
//  Laguna Seca Raceway
//
//  Created by David Nishimoto on 11/24/26.
//

import SwiftUI
import CoreData

@main
struct Laguna_Seca_RacewayApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
