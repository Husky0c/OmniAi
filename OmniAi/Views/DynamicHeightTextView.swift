import SwiftUI

#if canImport(UIKit)
import UIKit

class IntrinsicTextView: UITextView {
    var maxHeight: CGFloat = 150
    private var lastWidth: CGFloat = 0
    private var lastText: String = ""
    private var cachedSize: CGSize = .zero

    override var intrinsicContentSize: CGSize {
        let width = max(frame.width, 100)
        let currentText = text ?? ""

        if width == lastWidth && currentText == lastText {
            return cachedSize
        }

        let fittingSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let size = sizeThatFits(fittingSize)
        let shouldScroll = size.height >= maxHeight
        if isScrollEnabled != shouldScroll {
            isScrollEnabled = shouldScroll
        }

        lastWidth = width
        lastText = currentText
        cachedSize = CGSize(width: UIView.noIntrinsicMetric, height: min(size.height, maxHeight))
        return cachedSize
    }
}

struct DynamicHeightTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    let font: UIFont
    let textInsets: UIEdgeInsets
    let maxHeight: CGFloat

    init(
        text: Binding<String>,
        placeholder: String,
        isFocused: Binding<Bool>,
        font: UIFont = UIFont.preferredFont(forTextStyle: .body),
        textInsets: UIEdgeInsets = UIEdgeInsets(top: 16, left: 14, bottom: 8, right: 14),
        maxHeight: CGFloat = 150
    ) {
        self._text = text
        self.placeholder = placeholder
        self._isFocused = isFocused
        self.font = font
        self.textInsets = textInsets
        self.maxHeight = maxHeight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        weak var placeholderLabel: UILabel?

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self._text = text
            self._isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if text != newText {
                text = newText
            }
            placeholderLabel?.isHidden = !newText.isEmpty
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.isFocused = false
            }
        }
    }

    func makeUIView(context: Context) -> IntrinsicTextView {
        let tv = IntrinsicTextView()
        tv.maxHeight = maxHeight
        tv.delegate = context.coordinator
        tv.font = font
        tv.backgroundColor = .clear
        tv.textContainerInset = textInsets
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.text = text
        tv.isScrollEnabled = false
        tv.textColor = UIColor.label

        let label = UILabel()
        label.text = placeholder
        label.font = font
        label.textColor = UIColor.placeholderText
        label.sizeToFit()
        label.frame.origin = CGPoint(
            x: textInsets.left,
            y: textInsets.top
        )
        tv.addSubview(label)
        context.coordinator.placeholderLabel = label

        return tv
    }

    func updateUIView(_ uiView: IntrinsicTextView, context: Context) {
        let isEnabled = context.environment.isEnabled
        if uiView.isEditable != isEnabled {
            uiView.isEditable = isEnabled
        }

        if uiView.text != text {
            uiView.text = text
            uiView.invalidateIntrinsicContentSize()
        }
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty || !isEnabled
    }
}
#endif
