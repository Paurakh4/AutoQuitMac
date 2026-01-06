//
//  ContentView.swift
//  AutoQuit
//
//  Created by Paurakh Pyakurel on 06/01/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var watcher: AppWatcher
    
    var body: some View {
        VStack(spacing: 20) {
            if watcher.isTrusted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                
                Text("AutoQuit is Running")
                    .font(.title)
                
                Text("This app runs in the background. You can close this window.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                
                Text("Permission Needed")
                    .font(.title)
                
                Text("AutoQuit needs Accessibility permissions to detect when you close other apps.")
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    // Step 1: Reveal in Finder
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    
                    // Step 2: Open Settings
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("1. Open Settings & Finder")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                VStack(alignment: .leading, spacing: 10) {
                    Label("Drag 'AutoQuit' from the Finder window into the list.", systemImage: "arrow.right.doc.on.clipboard")
                    Label("Toggle the switch to ON.", systemImage: "switch.2")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical)
                
                Button("Show App in Finder again") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .buttonStyle(.link)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    ContentView(watcher: AppWatcher())
}
