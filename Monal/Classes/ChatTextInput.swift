//
//  ChatTextInput.swift
//  Monal
//
//  isaCloud: the text field of the chat input bar, a UITextView. Unlike TextField(axis: .vertical), it grows up to maxLines
//  lines and then scrolls, and it keeps the cursor visible while typing (with a TextField the cursor could be out of view).
//

import SwiftUI
import UIKit

struct ChatTextInput: UIViewRepresentable {
    @Binding var text: String
    /// shown while the input is empty (UITextView has no placeholder of its own)
    var placeholder: String
    /// the height limit, in lines of the body font: above it the text scrolls
    var maxLines: Int = 6

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ChatPlaceholderTextView {
        let textView = ChatPlaceholderTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.text = text
        textView.updatePlaceholder()
        return textView
    }

    func updateUIView(_ uiView: ChatPlaceholderTextView, context: Context) {
        context.coordinator.parent = self
        uiView.placeholder = placeholder
        // only a change that came from outside is written: the text typed by the person is already in the view, and
        // writing it again would move the cursor. An open composition (dictation, accents) is left alone too.
        if uiView.text != text && uiView.markedTextRange == nil {
            context.coordinator.isApplyingExternalText = true
            uiView.text = text
            // an outside change (cleared, sent, edit loaded, mention inserted) leaves the cursor at the end
            uiView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            context.coordinator.isApplyingExternalText = false
            uiView.updatePlaceholder()
            context.coordinator.scrollToCursor(uiView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ChatPlaceholderTextView, context: Context) -> CGSize? {
        let lineHeight = ceil(uiView.font?.lineHeight ?? 20)
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else {
            return CGSize(width: 0, height: lineHeight)
        }
        // one line at least, and maxLines lines at most; above that the text scrolls inside the view
        let contentHeight = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let height = min(max(contentHeight, lineHeight), lineHeight * CGFloat(maxLines))
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatTextInput
        /// true while SwiftUI's text is written into the view, so that the change is not sent back
        var isApplyingExternalText = false

        init(parent: ChatTextInput) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingExternalText, let view = textView as? ChatPlaceholderTextView else {
                return
            }
            parent.text = textView.text
            view.updatePlaceholder()
            scrollToCursor(view)
        }

        /// the height is worked out after the layout pass, so the cursor is brought into view on the next turn of the main queue
        func scrollToCursor(_ textView: UITextView) {
            DispatchQueue.main.async { [weak textView] in
                guard let textView = textView else {
                    return
                }
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }
    }
}

/// isaCloud: a UITextView with a placeholder: a label drawn over the text while the text is empty. Its accessibility value
/// is the placeholder while the input is empty, and the text otherwise.
final class ChatPlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()

    var placeholder: String = "" {
        didSet {
            placeholderLabel.text = placeholder
            updatePlaceholder()
        }
    }

    init() {
        super.init(frame: .zero, textContainer: nil)
        font = UIFont.preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        textColor = .label
        backgroundColor = .clear
        textContainerInset = .zero
        isScrollEnabled = true
        alwaysBounceVertical = false
        // the default behavior of the system input stays: autocorrection, spelling, smart quotes, keyboard type, Enter as a line break

        placeholderLabel.font = font
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("ChatPlaceholderTextView is only created in code")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // the same left and right position as the text (the line fragment padding of the text container)
        let x = textContainerInset.left + textContainer.lineFragmentPadding
        let width = max(0, bounds.width - x - textContainerInset.right - textContainer.lineFragmentPadding)
        let height = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        placeholderLabel.frame = CGRect(x: x, y: textContainerInset.top, width: width, height: height)
    }

    /// shows the placeholder only while the text is empty, and keeps the accessibility value in step with it
    func updatePlaceholder() {
        let isEmpty = text.isEmpty
        placeholderLabel.isHidden = !isEmpty
        accessibilityLabel = placeholder
        accessibilityValue = isEmpty ? placeholder : text
    }
}
