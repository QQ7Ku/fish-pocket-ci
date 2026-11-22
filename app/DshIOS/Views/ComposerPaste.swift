import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ObjectiveC

/// An image on the clipboard (拷贝 in Photos, a screenshot's 拷贝) pastes into the draft as an
/// attachment: from the edit menu's 粘贴, the iPad keyboard's paste key, and the keyboard's
/// paste suggestion, which iOS offers only to an input that takes images. SwiftUI's text input
/// takes text alone, and its own paste API starts at iOS 27, so the UIKit text view under the
/// input learns it here. A file (拷贝 in Files) joins as a file, as the web takes a pasted file,
/// and text over `ComposerModel.longTextLimit` as a text file: in the input it would hold the
/// app on its layout.
extension View {
    func pastesAttachments(focused: Bool, into composer: ComposerModel) -> some View {
        modifier(ImagePasteModifier(focused: focused, composer: composer))
    }
}

private struct ImagePasteModifier: ViewModifier {
    let focused: Bool
    let composer: ComposerModel
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.onChange(of: focused, initial: true) { _, now in
            guard now else { return }
            // The text view becomes first responder as focus lands: one turn later it is there to find.
            DispatchQueue.main.async {
                guard let view = UIResponder.focusedTextView else { return }
                // A queued message being edited is text only.
                ImagePaste.attach(to: view, accepts: { [composer] in composer.editingQueue == nil }) { pasted in
                    switch pasted {
                    case .image(let data):
                        if let refusal = composer.addImage(data: data) { app.showToast(refusal) }
                    case .file(let copy): composer.addStagedFile(copy)
                    case .longText(let text): composer.addLongText(text)
                    case .failed: app.showToast(String(localized: "粘贴的文件读取失败"))
                    }
                }
            }
        }
    }
}

/// UIKit runs the paste as it does for any text view: the system hands over the clipboard only
/// in the course of a paste the user asked for (a read of our own after the keyboard's paste
/// key comes back empty). The view's paste delegate takes each image, file and long text out of
/// the paste and lets the rest, text, through untouched. Everything here runs on the main thread.
enum ImagePaste {
    enum Pasted {
        /// An image's own bytes: a PNG stays a PNG.
        case image(Data)
        /// A file's copy, in a folder of its own under `tmp/uploads` (`PickedMovie.stage`).
        case file(URL)
        case longText(String)
        /// A file that could not be read.
        case failed
    }
    typealias Handler = (Pasted) -> Void

    private final class Target: NSObject, UITextPasteDelegate {
        let accepts: () -> Bool
        let add: Handler
        init(accepts: @escaping () -> Bool, add: @escaping Handler) { self.accepts = accepts; self.add = add }

        func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting, transform item: any UITextPasteItem) {
            let provider = item.itemProvider
            guard accepts() else { return item.setDefaultResult() }
            let types = provider.registeredContentTypes
            weak let view = textPasteConfigurationSupporting as? UITextView
            let add: @Sendable (Pasted) -> Void = { [add = self.add] pasted in
                DispatchQueue.main.async {
                    add(pasted)
                    // The text did not change, so the keyboard would keep offering the paste
                    // it just made (iOS 27's 粘贴自… suggestion): told the document changed, it
                    // refreshes its suggestions.
                    guard let view, view.isFirstResponder else { return }
                    view.inputDelegate?.textWillChange(view)
                    view.inputDelegate?.textDidChange(view)
                }
            }
            if let type = types.first(where: { $0.conforms(to: .image) }) {
                item.setNoResult()
                // An image that cannot be read pastes nothing: another 拷贝 is the only remedy anyway.
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    if let data { add(.image(data)) }
                }
            } else if provider.suggestedName != nil, let type = types.first(where: { $0.conforms(to: .data) }) {
                // A file brings its name; text copied in an app comes without one. Files offers
                // a text file's contents as text too, which would land in the input.
                item.setNoResult()
                _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                    // The system's copy is gone once this returns.
                    guard let url, let copy = try? PickedMovie.stage(url) else { return add(.failed) }
                    add(.file(copy))
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                // The paste waits for its items: a long text leaves it, the rest go in as they came.
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    let text = (object as? NSString) as String?
                    DispatchQueue.main.async {
                        guard let text, text.utf16.count > ComposerModel.longTextLimit else {
                            return text.map { item.setResult(string: $0) } ?? item.setDefaultResult()
                        }
                        item.setNoResult()
                        add(.longText(text))
                    }
                }
            } else {
                item.setDefaultResult()
            }
        }
    }

    nonisolated(unsafe) private static var targetKey: UInt8 = 0
    nonisolated(unsafe) private static var patched: Set<ObjectIdentifier> = []

    /// Let this text view paste images into its composer. The view keeps the delegate for its
    /// lifetime (a text view holds its paste delegate weakly).
    @MainActor
    static func attach(to view: UITextView, accepts: @escaping () -> Bool, add: @escaping Handler) {
        let first = objc_getAssociatedObject(view, &targetKey) == nil
        let target = Target(accepts: accepts, add: add)
        objc_setAssociatedObject(view, &targetKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        view.pasteDelegate = target
        let types = view.pasteConfiguration?.acceptableTypeIdentifiers ?? (UIPasteboard.typeListString as? [String] ?? [])
        if !types.contains(UTType.image.identifier) {
            view.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: types + [UTType.image.identifier])
        }
        patch(object_getClass(view))
        // The keyboard asked what it can paste as the view took focus, before the view took
        // images: asked again, its paste key (iPad) and paste suggestion count the image.
        if first, view.isFirstResponder { view.reloadInputViews() }
    }

    /// A plain-text view offers 粘贴 for text only: with an image on the clipboard, this one
    /// offers it too while it takes images. The class is SwiftUI's private subclass; any other
    /// view of it falls through to what the class did before.
    private static func patch(_ cls: AnyClass?) {
        guard let cls, patched.insert(ObjectIdentifier(cls)).inserted else { return }
        typealias CanPerform = @convention(c) (AnyObject, Selector, Selector, Any?) -> Bool
        let selector = #selector(UIResponder.canPerformAction(_:withSender:))
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: CanPerform.self)
        let block: @convention(block) (AnyObject, Selector, Any?) -> Bool = { this, action, sender in
            if action == #selector(UIResponderStandardEditActions.paste(_:)),
               let target = objc_getAssociatedObject(this, &targetKey) as? Target, target.accepts(),
               UIPasteboard.general.hasImages {
                return true
            }
            return original(this, selector, action, sender)
        }
        class_replaceMethod(cls, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }
}
