//
//  Sales_ProjectApp.swift
//  Sales_Project
//
//  Created by Vritik Valabdas on 2/24/26.
//

import SwiftUI

//@main
struct Sales_ProjectApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    // S6: nunca criar um Admin com password fixa em código.
    // Sem utilizadores na base de dados, a `LoginView` mostra o ecrã de
    // criação do primeiro Admin.

    var body: some Scene {
        WindowGroup {
            if authViewModel.isLoggedIn {
                MainView()
                    .environmentObject(authViewModel)
            } else {
                LoginView()
                    .environmentObject(authViewModel)
            }
        }
    }
}
