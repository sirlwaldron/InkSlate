//
//  SharingService.swift
//  InkSlate
//
//  Created by Lucas Waldron on 10/18/25.
//  Based on FSNotes sharing implementation
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Sharing Service (FSNotes-inspired)
class SharingService: ObservableObject {
    static let shared = SharingService()
    
    private init() {}
    
    // MARK: - Share Note (iOS: from view controller; macOS: items only, use ShareSheet)
    
    #if canImport(UIKit)
    func shareNote(_ note: Notes, from view: UIViewController) {
        guard !note.isEncrypted else {
            let alert = UIAlertController(
                title: "Decrypt to Share",
                message: "This note is locked. Decrypt it before sharing or exporting.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            view.present(alert, animated: true)
            return
        }
        let activityViewController = UIActivityViewController(
            activityItems: [note.content ?? ""],
            applicationActivities: nil
        )
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = view.view
            popover.sourceRect = CGRect(x: view.view.bounds.midX, y: view.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        view.present(activityViewController, animated: true)
    }
    #endif
    
    // MARK: - Export as HTML
    
    func exportAsHTML(_ note: Notes) -> String {
        if note.isEncrypted {
            return """
            <!DOCTYPE html>
            <html>
            <head><meta charset="UTF-8"></head>
            <body><p>This note is locked. Decrypt it in InkSlate to export.</p></body>
            </html>
            """
        }
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
        if note.isEncrypted {
            return "# \(note.title ?? "")\n\n( Locked note — decrypt in InkSlate to export. )"
        }
        return "# \(note.title ?? "")\n\n\(note.content ?? "")"
    }
    
    // MARK: - Export as PDF (iOS only; macOS returns nil)
    
    func exportAsPDF(_ note: Notes) -> Data? {
        #if canImport(UIKit)
        let html = exportAsHTML(note)
        let printFormatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)
        let pageSize = CGSize(width: 595, height: 842)
        let printableRect = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, printableRect, nil)
        UIGraphicsBeginPDFPage()
        renderer.drawPage(at: 0, in: UIGraphicsGetPDFContextBounds())
        UIGraphicsEndPDFContext()
        return pdfData as Data
        #else
        return nil
        #endif
    }
    
    #if canImport(UIKit)
    /// Exports a PDF to a temporary file so the share sheet has a filename + UTType.
    func exportPDFToTemporaryFile(_ note: Notes) -> URL? {
        guard let data = exportAsPDF(note) else { return nil }
        
        let safeTitle = (note.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (note.title ?? "Note")
            : "Note"
        
        let fileName = safeTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(80)
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(fileName))
            .appendingPathExtension("pdf")
        
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
    #endif
    
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

// MARK: - Share Sheet (UIKit)
#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Export Options View
struct ExportOptionsView: View {
    let note: Notes
    @Environment(\.dismiss) var dismiss
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showingLockedAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Export Note")
                    .font(.headline)
                
                Text("Choose how you want to export this note.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if note.isEncrypted {
                    Text("This note is locked. Decrypt it before exporting.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 16) {
                    Button("Share as Text") {
                        guard !note.isEncrypted else { showingLockedAlert = true; return }
                        shareItems = [note.content ?? ""]
                        showingShareSheet = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                    Button("Export as HTML") {
                        guard !note.isEncrypted else { showingLockedAlert = true; return }
                        let html = SharingService.shared.exportAsHTML(note)
                        shareItems = [html]
                        showingShareSheet = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                    Button("Export as Markdown") {
                        guard !note.isEncrypted else { showingLockedAlert = true; return }
                        let markdown = SharingService.shared.exportAsMarkdown(note)
                        shareItems = [markdown]
                        showingShareSheet = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                    #if canImport(UIKit)
                    Button("Export as PDF") {
                        guard !note.isEncrypted else { showingLockedAlert = true; return }
                        if let pdfURL = SharingService.shared.exportPDFToTemporaryFile(note) {
                            shareItems = [pdfURL]
                            showingShareSheet = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    #endif
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            #if canImport(UIKit)
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
            #endif
            .alert("Locked Note", isPresented: $showingLockedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Decrypt this note before exporting.")
            }
        }
    }
}
