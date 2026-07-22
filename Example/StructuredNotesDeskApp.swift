//  StructuredNotesDeskApp.swift
//  Structured Notes
//
//  Host app for the StructuredNotesDesk framework. Targets iOS 17+.
//  Display Name: "Structured Notes".

import SwiftUI
import StructuredNotesDesk

@main
struct StructuredNotesApp: App {
    var body: some Scene {
        WindowGroup {
            DeskView()
        }
    }
}
