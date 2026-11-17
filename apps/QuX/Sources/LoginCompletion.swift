import Foundation

enum LoginCompletion {
    // The official login code publishes this event only after it processes its
    // success result and finishes the cross-site cookie handoff.
    static let script = #"""
    (() => {
        if (window !== window.top || location.protocol !== "https:" ||
            !["login.m.taobao.com", "login.taobao.com", "cnlogin.cainiao.com"].includes(location.hostname)) return;
        const install = () => {
            if (window.__quxLoginCompletionInstalled) return;
            const events = window.events;
            if (!events || typeof events.subscribe !== "function") return;
            window.__quxLoginCompletionInstalled = true;
            let completed = false;
            events.subscribe("afterHandleLoginResult", result => {
                if (completed || !result || result.action !== "loginResult" ||
                    typeof result.st !== "string" || result.st.length === 0 ||
                    (result.resultCode != null && Number(result.resultCode) !== 100)) return;
                completed = true;
                window.webkit.messageHandlers.quxLoginCompletion.postMessage("completed");
            });
        };
        install();
        window.addEventListener("load", install, { once: true });
    })();
    """#
}
