import CoreGraphics

/// Scripts injected into every page. Platform-free so they can be run against real WebKit on a
/// Mac, which is how `hudtests` checks them.
public enum PageScripts {
    /// Keeps every page's own fixed bars below ours — the bridge the content flows under.
    ///
    /// The page is inset below the glass bar, but `position: fixed; top: 0` means the top of
    /// the web view, which is behind the glass: a site's header (YouTube's, a news site's, a
    /// cookie banner) would sit under the bar with the page scrolling beneath both. So anything fixed or sticky near the top edge is moved
    /// down by the bar's height. It stays fixed, the content still runs under it and on up under
    /// the glass, and it stays clickable because it is no longer covered.
    ///
    /// It looks only along the top band of the page (`elementsFromPoint` on a row of points),
    /// not at every element, so it is cheap enough to rerun whenever the page changes.
    public static func bridge(inset: CGFloat) -> String {
        """
        (function () {
          if (window.__hudBridge) return;
          window.__hudBridge = true;
          var inset = \(Double(inset));
          var reach = 140;

          function adjust(el) {
            if (!(el instanceof Element) || el === document.documentElement || el === document.body) return;
            if (el.hasAttribute('data-hud-top')) return;
            var style = getComputedStyle(el);
            if (style.position !== 'fixed' && style.position !== 'sticky') return;
            // A sticky header inside its own scrolling box sticks to that box, not to the page,
            // and the bar does not cover it. Only the ones that stick to the page move.
            if (style.position === 'sticky') {
              for (var a = el.parentElement; a && a !== document.body; a = a.parentElement) {
                if (/(auto|scroll|overlay)/.test(getComputedStyle(a).overflowY)) return;
              }
            }
            var top = parseFloat(style.top);
            if (isNaN(top)) {
              if (style.position === 'sticky') return;
              var rect = el.getBoundingClientRect();
              if (rect.top > reach || rect.height === 0) return;
              top = rect.top;
            }
            if (top < 0 || top > reach) return;
            el.setAttribute('data-hud-top', String(top));
            el.style.setProperty('top', (top + inset) + 'px', 'important');
          }

          function scan() {
            if (!document.body) return;
            var w = window.innerWidth, seen = new Set();
            for (var i = 0; i <= 12; i++) {
              var x = Math.min(w - 1, Math.max(1, i * w / 12));
              [2, 24, 60, 100].forEach(function (y) {
                document.elementsFromPoint(x, y).forEach(function (el) {
                  if (seen.has(el)) return;
                  seen.add(el);
                  adjust(el);
                });
              });
            }
          }

          window.__hudSetTopInset = function (value) {
            inset = value;
            document.querySelectorAll('[data-hud-top]').forEach(function (el) {
              var top = parseFloat(el.getAttribute('data-hud-top')) || 0;
              el.style.setProperty('top', (top + inset) + 'px', 'important');
            });
            if (inset > 0) scan();
          };

          var pending = null;
          function soon(delay) {
            if (pending) return;
            pending = setTimeout(function () { pending = null; if (inset > 0) scan(); }, delay);
          }

          document.addEventListener('DOMContentLoaded', function () {
            scan();
            new MutationObserver(function () { soon(400); })
              .observe(document.body, {childList: true, subtree: true});
          });
          window.addEventListener('load', function () { scan(); });
          window.addEventListener('scroll', function () { soon(250); }, {passive: true});
          window.addEventListener('resize', function () { soon(250); });
          // Single-page sites build their header late; look a few more times as they settle.
          [500, 1500, 3000, 6000].forEach(function (t) { setTimeout(scan, t); });
        })();
        """
    }
}
