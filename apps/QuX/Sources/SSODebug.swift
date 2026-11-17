import Foundation

enum SSODebug {
    static let script = #"""
    (() => {
        if (location.protocol !== "https:" || window.__quxSSODebug) return;
        const trusted = host => ["cainiao.com", "taobao.com", "tmall.com"].some(d => host === d || host.endsWith("." + d));
        if (!trusted(location.hostname)) return;
        window.__quxSSODebug = true;
        const emit = data => {
            console.log("[SSO-Debug]", data);
            try { window.webkit.messageHandlers.ssoDebug.postMessage({...data, href: location.href}); } catch (_) {}
        };
        for (const name of ["replace", "assign"]) {
            const original = window.location[name];
            const wrapper = function(url) {
                emit({type: name, url: String(url), stack: new Error().stack || ""});
                return original.apply(this, arguments);
            };
            try { window.location[name] = wrapper; } catch (_) {}
            emit({type: "hook", method: name, installed: window.location[name] === wrapper});
        }
        const observe = (url, text, status) => {
            try {
                const endpoint = new URL(url, location.href);
                if (!trusted(endpoint.hostname) || !endpoint.pathname.includes("/h5/")) return;
                // JSONP / JSON: extract only canonical MTOP error codes. Never
                // forward response bodies, cookie values or account records.
                const codes = String(text).match(/FAIL_[A-Z0-9_]{1,100}/g) || [];
                for (const code of [...new Set(codes)].slice(0, 8)) {
                    emit({type: "mtop-error", url: endpoint.origin + endpoint.pathname, code, status});
                }
            } catch (_) {}
        };
        const urls = new WeakMap(), open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url, ...rest) {
            urls.set(this, String(url)); return open.call(this, method, url, ...rest);
        };
        XMLHttpRequest.prototype.send = function(...args) {
            this.addEventListener("loadend", () => {
                try {
                    const text = this.responseType === "json" ? JSON.stringify(this.response) :
                        (!this.responseType || this.responseType === "text") ? this.responseText : "";
                    observe(urls.get(this), text, this.status);
                } catch (_) {}
            }, {once: true});
            return send.apply(this, args);
        };
        if (typeof window.fetch === "function") {
            const original = window.fetch;
            window.fetch = function(...args) {
                return original.apply(this, args).then(response => {
                    try { response.clone().text().then(text => observe(response.url, text, response.status)).catch(() => {}); } catch (_) {}
                    return response;
                });
            };
        }
        emit({type: "ready"});
    })();
    """#
}
