import UIKit

extension UIApplication {
    static var keyWindow: UIWindow? {
        shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    static var topViewController: UIViewController? {
        func top(from controller: UIViewController?) -> UIViewController? {
            if let nav = controller as? UINavigationController {
                return top(from: nav.visibleViewController)
            }
            if let tab = controller as? UITabBarController {
                return top(from: tab.selectedViewController)
            }
            if let presented = controller?.presentedViewController {
                return top(from: presented)
            }
            return controller
        }

        return top(from: keyWindow?.rootViewController)
    }
}
