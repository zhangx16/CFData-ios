import UIKit
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let backendQueue = DispatchQueue(label: "cfdata.backend", qos: .userInitiated)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let controller = BrowserController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        controller.retry = { [weak self, weak controller] in
            self?.backendQueue.async {
                do {
                    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    let address = try Backend.start(withDataDirectory: base.appendingPathComponent("CFData", isDirectory: true).path)
                    guard let url = URL(string: address) else {
                        throw NSError(domain: "CFData", code: 1, userInfo: [NSLocalizedDescriptionKey: "本机服务没有返回有效地址"])
                    }
                    DispatchQueue.main.async { controller?.open(url) }
                } catch {
                    let message = error.localizedDescription
                    DispatchQueue.main.async { controller?.showError(message) }
                }
            }
        }
        controller.retry?()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Cancellation is performed in Go as well as the UI; WebKit may already be suspended.
        backendQueue.async { Backend.pause() }
        (window?.rootViewController as? BrowserController)?.didBackground()
        application.isIdleTimerDisabled = false
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        backendQueue.async { Backend.resume() }
        (window?.rootViewController as? BrowserController)?.didForeground()
    }
}

final class BrowserController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var retry: (() -> Void)?
    private var webView: WKWebView!
    private let message = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private var backendURL: URL?
    private var wasBackgrounded = false
    private var sharedFile: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(self, name: "cfdata")
        if let scriptURL = Bundle.main.url(forResource: "ios-bridge", withExtension: "js"), let script = try? String(contentsOf: scriptURL, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isHidden = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        message.text = "正在准备本机测速服务…\n首次启动需要下载数据中心信息"
        message.textAlignment = .center
        message.numberOfLines = 0
        message.font = .preferredFont(forTextStyle: .body)
        retryButton.setTitle("重试", for: .normal)
        retryButton.addTarget(self, action: #selector(retryStartup), for: .touchUpInside)
        retryButton.isHidden = true
        let stack = UIStackView(arrangedSubviews: [spinner, message, retryButton])
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48)
        ])
        spinner.startAnimating()
    }

    @objc private func retryStartup() {
        retryButton.isHidden = true
        message.text = "正在连接本机测速服务…"
        spinner.startAnimating()
        if let url = backendURL { open(url) } else { retry?() }
    }

    func open(_ url: URL) {
        backendURL = url
        webView.load(URLRequest(url: url))
    }

    func showError(_ text: String) {
        webView.isHidden = true
        spinner.stopAnimating()
        message.text = "启动失败\n" + text
        retryButton.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
        message.text = nil
        retryButton.isHidden = true
        webView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // A WebKit crash discards its in-memory table. Cancel any remaining native work.
        Backend.pause()
        Backend.resume()
        if let url = backendURL { open(url) }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage text: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard presentedViewController == nil else { completionHandler(false); return }
        let alert = UIAlertController(title: "CFData", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "http", url.host == "127.0.0.1", url.port == backendURL?.port {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url)
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive scriptMessage: WKScriptMessage) {
        let origin = scriptMessage.frameInfo.securityOrigin
        guard scriptMessage.frameInfo.isMainFrame, origin.protocol == "http", origin.host == "127.0.0.1", origin.port == backendURL?.port,
              let body = scriptMessage.body as? [String: Any], let kind = body["type"] as? String else { return }
        switch kind {
        case "copy":
            if let text = body["text"] as? String { UIPasteboard.general.string = text }
        case "activity":
            UIApplication.shared.isIdleTimerDisabled = (body["running"] as? Bool ?? false) && UIApplication.shared.applicationState == .active
        case "export":
            guard let content = body["content"] as? String, let fileName = body["name"] as? String else { return }
            share(content: content, name: fileName)
        default: break
        }
    }

    private func share(content: String, name: String) {
        guard presentedViewController == nil else { return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let cleanName = (name as NSString).lastPathComponent
            guard !cleanName.isEmpty, cleanName != ".", cleanName != ".." else { return }
            let file = directory.appendingPathComponent(cleanName)
            try content.write(to: file, atomically: true, encoding: .utf8)
            sharedFile = file
            let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in
                try? FileManager.default.removeItem(at: file)
                self?.sharedFile = nil
            }
            present(sheet, animated: true)
        } catch {
            let alert = UIAlertController(title: "导出失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
        }
    }

    func didBackground() { wasBackgrounded = true }

    func didForeground() {
        guard wasBackgrounded else { return }
        wasBackgrounded = false
        webView?.evaluateJavaScript("window.cfdataDidForeground && window.cfdataDidForeground()", completionHandler: nil)
    }
}
