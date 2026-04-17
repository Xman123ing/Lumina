import AppKit
import os
import SwiftUI

struct MacInputField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 16
    var autoFocus: Bool = false
    var onSubmit: (() -> Void)? = nil
    var onUp: (() -> Void)? = nil
    var onDown: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil

    private let logger = Logger(subsystem: "Lumina", category: "Input")

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: fontSize, weight: .medium)
        field.textColor = .white
        logger.info("[LuminaInput] makeNSView placeholder=\(self.placeholder, privacy: .public)")
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.font = .systemFont(ofSize: fontSize, weight: .medium)

        if autoFocus {
            if !context.coordinator.didAutoFocus {
                context.coordinator.didAutoFocus = true
                DispatchQueue.main.async {
                    self.logger.info("[LuminaInput] requesting focus placeholder=\(self.placeholder, privacy: .public)")
                    nsView.window?.makeFirstResponder(nsView)
                    if let editor = nsView.currentEditor() {
                        editor.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
                    }
                    if let responder = nsView.window?.firstResponder {
                        self.logger.info("[LuminaInput] firstResponder after focus=\(String(describing: type(of: responder)), privacy: .public)")
                    } else {
                        self.logger.info("[LuminaInput] firstResponder after focus=nil")
                    }
                }
            }
        } else {
            context.coordinator.didAutoFocus = false
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacInputField
        private let logger = Logger(subsystem: "Lumina", category: "Input")
        var didAutoFocus = false

        init(_ parent: MacInputField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            logger.info("[LuminaInput] beginEditing placeholder=\(self.parent.placeholder, privacy: .public)")
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            logger.info("[LuminaInput] endEditing placeholder=\(self.parent.placeholder, privacy: .public)")
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            logger.debug("[LuminaInput] textDidChange placeholder=\(self.parent.placeholder, privacy: .public) valueLength=\(field.stringValue.count)")
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                logger.debug("[LuminaInput] command submit placeholder=\(self.parent.placeholder, privacy: .public)")
                parent.onSubmit?()
                return true
            case #selector(NSResponder.moveUp(_:)):
                logger.debug("[LuminaInput] command up placeholder=\(self.parent.placeholder, privacy: .public)")
                parent.onUp?()
                return true
            case #selector(NSResponder.moveDown(_:)):
                logger.debug("[LuminaInput] command down placeholder=\(self.parent.placeholder, privacy: .public)")
                parent.onDown?()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                logger.debug("[LuminaInput] command escape placeholder=\(self.parent.placeholder, privacy: .public)")
                parent.onEscape?()
                return true
            default:
                return false
            }
        }
    }
}
