//
//  SharingService.swift
//  InkSlate
//
//  Created by Lucas Waldron on 10/18/25.
//  Based on FSNotes sharing implementation
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Sharing Service (FSNotes-inspired)
class SharingService: ObservableObject {
    static let shared = SharingService()
    
    private init() {}
    
    
    deinit {
        
    }
    
    // MARK: - Share Note
    
    func shareNote(_ note: Notes, from view: UIViewController) {
        let activityViewController = UIActivityViewController(
            activityItems: [note.content ?? ""],
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = view.view
            popover.sourceRect = CGRect(x: view.view.bounds.midX, y: view.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        view.present(activityViewController, animated: true)
    }
    
    // MARK: - Export as HTML
    
    func exportAsHTML(_ note: Notes) -> String {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(note.title ?? "Untitled Note")</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; }
                h1, h2, h3 { color: #333; }
                code { background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }
                pre { background: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; }
                blockquote { border-left: 4px solid #ddd; margin: 0; padding-left: 20px; color: #666; }
                blockquote p { margin: 0; }
            </style>
        </head>
        <body>
            <h1>\(note.title ?? "Untitled Note")</h1>
            \(markdownToHTML(note.content ?? ""))
        </body>
        </html>
        """
        
        return html
    }
    
    // MARK: - Export as Markdown
    
    func exportAsMarkdown(_ note: Notes) -> String {
        return "# \(note.title ?? "")\n\n\(note.content ?? "")"
    }
    
    // MARK: - Export as PDF
    
    func exportAsPDF(_ note: Notes) -> Data? {
        let html = exportAsHTML(note)
        
        let printFormatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)
        
        let pageSize = CGSize(width: 595, height: 842) // A4 size
        let printableRect = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")
        
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, printableRect, nil)
        UIGraphicsBeginPDFPage()
        
        renderer.drawPage(at: 0, in: UIGraphicsGetPDFContextBounds())
        
        UIGraphicsEndPDFContext()
        
        return pdfData as Data
    }
    
    // MARK: - Private Methods
    
    private func markdownToHTML(_ markdown: String) -> String {
        // Simple markdown to HTML conversion
        var html = markdown
        
        // Headers
        html = html.replacingOccurrences(of: "^# (.+)$", with: "<h1>$1</h1>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^## (.+)$", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^### (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        
        // Bold
        html = html.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        
        // Italic
        html = html.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)
        
        // Code blocks
        html = html.replacingOccurrences(of: "```([\\s\\S]*?)```", with: "<pre><code>$1</code></pre>", options: .regularExpression)
        
        // Inline code
        html = html.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        
        // Links
        html = html.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        
        // Line breaks
        html = html.replacingOccurrences(of: "\n", with: "<br>")
        
        return html
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Export Options View
struct ExportOptionsView: View {
    let note: Notes
    @Environment(\.dismiss) var dismiss
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Export Note")
                    .font(.headline)
                
                Text("Choose how you want to export this note.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 16) {
                    Button("Share as Text") {
                        shareItems = [note.content ?? ""]
                        showingShareSheet = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                    Button("Export as HTML") {
                        let html = SharingService.shared.exportAsHTML(note)
                        shareItems = [html]
                        showingShareSheet = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                    Button("Export as Markdown") {
                        let markdown = SharingService.shared.exportAsMarkdown(note)
                        shareItems = [markdown]
                        showingShareSheet = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                    Button("Export as PDF") {
                        if let pdfData = SharingService.shared.exportAsPDF(note) {
                            shareItems = [pdfData]
                            showingShareSheet = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
        }
    }
}
