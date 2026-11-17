import Foundation

enum AuthDiagnostics {
    static func line(host: String, mainFrame: Bool, body: Any) -> String? {
        guard let data = body as? [String: Any], let event = data["event"] as? String,
              ["ready", "storage-yes", "storage-no", "storage-unknown", "request-start", "request-end", "script-error", "promise-error", "login-result"].contains(event),
              ["login.m.taobao.com", "login.taobao.com", "cnlogin.cainiao.com"].contains(host) else { return nil }
        var line = "\(mainFrame ? "主页面" : "内嵌页面") \(host) · \(event)"
        if let kind = data["kind"] as? String, ["sms", "login", "other"].contains(kind) { line += " · " + kind }
        if let status = data["status"] as? Int, (0...599).contains(status) { line += " · HTTP \(status)" }
        return line
    }

    // Observe only endpoint categories/status. Never read input values, request
    // bodies, response bodies, headers, cookies or login-result contents.
    static let script = #"""
    (() => {
        if (location.protocol !== "https:" ||
            !["login.m.taobao.com", "login.taobao.com", "cnlogin.cainiao.com"].includes(location.hostname)) return;
        if (window.__quxDiagnostics) return;
        window.__quxDiagnostics = true;
        const emit = (event, extra = {}) => {
            try { window.webkit.messageHandlers.quxDiagnostics.postMessage({event, ...extra}); } catch (_) {}
        };
        const kind = value => {
            try {
                const path = new URL(String(value), location.href).pathname;
                return /sms|send.*code/i.test(path) ? "sms" : /login|havana|sso/i.test(path) ? "login" : "other";
            } catch (_) { return "other"; }
        };
        emit("ready");
        if (typeof document.hasStorageAccess === "function") {
            document.hasStorageAccess().then(yes => emit(yes ? "storage-yes" : "storage-no"), () => emit("storage-unknown"));
        } else { emit("storage-unknown"); }
        window.addEventListener("error", () => emit("script-error"));
        window.addEventListener("unhandledrejection", () => emit("promise-error"));
        const categories = new WeakMap();
        const open = XMLHttpRequest.prototype.open;
        const send = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url, ...rest) {
            categories.set(this, kind(url));
            return open.call(this, method, url, ...rest);
        };
        XMLHttpRequest.prototype.send = function(...args) {
            const category = categories.get(this) || "other";
            emit("request-start", {kind: category});
            this.addEventListener("loadend", () => emit("request-end", {kind: category, status: this.status}), {once: true});
            return send.apply(this, args);
        };
        const install = () => {
            if (window.__quxDiagnosticsEvents || !window.events || typeof window.events.subscribe !== "function") return;
            window.__quxDiagnosticsEvents = true;
            window.events.subscribe("afterHandleLoginResult", () => emit("login-result"));
        };
        install();
        document.addEventListener("DOMContentLoaded", install, {once: true});
        window.addEventListener("load", install, {once: true});
    })();
    """#
}
