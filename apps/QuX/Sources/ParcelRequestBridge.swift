import Foundation

enum ParcelRequestBridge {
    static let script = #"""
    (() => {
        if (location.protocol !== "https:" || location.hostname !== "page.cainiao.com" ||
            !/^\/guoguo\/app-myexpress-taobao\/?$/.test(location.pathname)) return;
        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.quxParcels;
        if (!handler || window.__quxParcelBridge) return;
        window.__quxParcelBridge = true;
        const api = "mtop.cainiao.lpc.packageservice.querytaobaopackagelist";
        const wrapped = new WeakMap();
        const wrap = original => {
            if (typeof original !== "function") return original;
            if (wrapped.has(original)) return wrapped.get(original);
            const replacement = function(params, ...rest) {
                if (!params || String(params.api).toLowerCase() !== api) return original.call(this, params, ...rest);
                const page = Number(params.data && params.data.currentPage || 1);
                if (!Number.isInteger(page) || page < 1 || page > 200) return Promise.reject({ret: ["FAIL_INVALID_PAGE"]});
                const config = window.lib.mtop.config || {};
                const gateway = [config.prefix || "acs", config.subDomain || "m", config.mainDomain || "taobao.com"].join(".");
                // Bypass only this API's browser login middleware. Native code
                // returns a real service response; it never fabricates a session.
                return handler.postMessage({page, gateway}).then(result => {
                    const success = result && Array.isArray(result.ret) && result.ret.some(code => /^SUCCESS(?:::|$)/.test(code));
                    const callback = success ? params.successCallback : params.failureCallback;
                    if (typeof callback === "function") { try { callback(result); } catch (_) {} }
                    if (success) return result;
                    return Promise.reject(result || {ret: ["FAIL_NATIVE_BRIDGE"]});
                });
            };
            wrapped.set(original, replacement);
            wrapped.set(replacement, replacement);
            return replacement;
        };
        const watched = new WeakMap();
        const watch = (object, key, transform) => {
            if (!object || (typeof object !== "object" && typeof object !== "function")) return;
            let keys = watched.get(object);
            if (!keys) { keys = new Set(); watched.set(object, keys); }
            if (keys.has(key)) return;
            keys.add(key);
            const descriptor = Object.getOwnPropertyDescriptor(object, key);
            if (descriptor && (!descriptor.configurable || descriptor.get || descriptor.set)) {
                try { object[key] = transform(object[key]); } catch (_) {}
                return;
            }
            let value = transform(object[key]);
            Object.defineProperty(object, key, {configurable: true, enumerable: descriptor ? descriptor.enumerable : true,
                get() { return value; }, set(next) { value = transform(next); }});
        };
        const patchMtop = mtop => { watch(mtop, "request", wrap); return mtop; };
        const patchLib = lib => { watch(lib, "mtop", patchMtop); return lib; };
        try { watch(window, "lib", patchLib); } catch (_) { console.log("[SSO-Debug] parcel bridge install failed"); }
    })();
    """#
}
