class BrowserAdBlockRules {
  static const String youtubeAdScript = """
(function() {
    'use strict';
    
    function skipAds() {
        const skipBtns = document.querySelectorAll(
            '.ytp-skip-ad-button, .ytp-ad-skip-button, ' +
            '.ytp-ad-skip-button-modern, [class*="skip-ad"], ' +
            '.ytp-ad-skip-button-slot button'
        );
        skipBtns.forEach(btn => {
            if (btn && btn.offsetParent !== null) {
                btn.click();
            }
        });
        
        const video = document.querySelector('.ad-showing video, .html5-video-container video');
        if (video && document.querySelector('.ad-showing')) {
            video.currentTime = video.duration || 9999;
            // Removed video.muted=true so actual videos won't stay muted
        }
        
        const overlays = document.querySelectorAll(
            '.ytp-ad-overlay-container, .ytp-ad-text-overlay, ' +
            '.ytp-ad-image-overlay, .ytp-ad-persistent-progress-bar-container, ' +
            '.ytp-suggested-action, .ytp-ad-module'
        );
        overlays.forEach(el => {
            if (el) el.remove();
        });
        
        const feedAds = document.querySelectorAll(
            'ytd-ad-slot-renderer, ytd-display-ad-renderer, ' +
            'ytd-promoted-sparkles-web-renderer, ytd-promoted-video-renderer, ' +
            'ytd-search-pyv-renderer, ytd-in-feed-ad-layout-renderer, ' +
            'ytd-banner-promo-renderer, ytd-statement-banner-renderer, ' +
            'ytd-rich-item-renderer:has(ytd-ad-slot-renderer), ' +
            '#masthead-ad, .ytd-banner-promo-renderer, ' +
            'tp-yt-paper-dialog:has([slot="trigger"])[data-promo-]'
        );
        feedAds.forEach(el => {
            if (el) el.remove();
        });
        
        const premiumOffers = document.querySelectorAll(
            '.ytd-mealbar-promo-renderer, #offer-module, ' +
            'ytd-mealbar-promo-renderer'
        );
        premiumOffers.forEach(el => {
            if (el) el.remove();
        });
    }
    
    const observer = new MutationObserver(function(mutations) {
        let shouldSkip = false;
        mutations.forEach(function(m) {
            if (m.addedNodes.length > 0) shouldSkip = true;
        });
        if (shouldSkip) skipAds();
    });
    
    observer.observe(document.documentElement, {
        childList: true,
        subtree: true
    });
    
    skipAds();
    setInterval(skipAds, 300);
})();
""";

  static const String generalAdScript = """
(function() {
    'use strict';
    
    const AD_SELECTORS = [
        '[id*="google_ads"]', '[class*="google-ad"]', '[class*="google_ad"]',
        '[id*="div-gpt-ad"]', '[class*="dfp-ad"]', '[class*="ad-container"]',
        '[class*="ad-wrapper"]', '[class*="ad-banner"]', '[class*="ad-slot"]',
        '[class*="ad-unit"]', '[class*="advertisement"]', '[class*="advertorial"]',
        '[class*="sponsor-"]', '[class*="sponsored"]', '[id*="sponsored"]',
        '[data-ad]', '[data-ads]', '[data-advertisement]',
        '[id*="taboola"]', '[class*="taboola"]',
        '[id*="outbrain"]', '[class*="outbrain"]',
        '[id*="criteo"]', '[class*="criteo"]',
        '.popup-overlay', '#popup-overlay', '.modal-backdrop.fade.in',
        '.push-notification-prompt', '#interstitial-wrapper', '.interstitial-ad',
        
        // Aggressive overlay/Age confirmations
        '[style*="z-index: 2147483647"]',
        '[style*="z-index: 999999"]',
        'div[id^="overlay"]',
        'div[class^="overlay"]',
        '#age-verification', '.age-verification',
        '#robot-check', '.robot-check'
    ];
    
    function removeAds() {
        if (window.location.hostname.includes('youtube.com')) return; // exempt Youtube
        
        AD_SELECTORS.forEach(selector => {
            try {
                document.querySelectorAll(selector).forEach(el => {
                    // Check if it's not the main content
                    if (el.querySelector('article, main, .content, p:nth-of-type(3), h1, h2')) return;
                    // Check if it contains suspicious text
                    const text = el.innerText ? el.innerText.toLowerCase() : "";
                    if (el.tagName === 'DIV' && (text.includes("over 18") || text.includes("not a robot") || text.includes("allow to view"))) {
                       el.style.display = 'none';
                       el.remove();
                       return;
                    }

                    el.style.display = 'none';
                    el.remove();
                });
            } catch(e) {}
        });
        
        // Find orphan full-screen popups
        document.querySelectorAll('div').forEach(div => {
            const styles = window.getComputedStyle(div);
            if (styles.position === 'fixed' && parseInt(styles.zIndex) > 9000) {
               const text = div.innerText ? div.innerText.toLowerCase() : "";
               if (text.includes("over 18") || text.includes("not a robot") || text.includes("allow")) {
                    div.remove();
               }
            }
        });

        document.querySelectorAll('iframe').forEach(iframe => {
            const src = iframe.src || '';
            if (/googlesyndication|doubleclick|adnxs|advertising|taboola|outbrain/.test(src)) {
                iframe.remove();
            }
        });
        
        if (document.body) {
            if (document.body.style.overflow === 'hidden' && document.querySelectorAll('.popup-overlay').length === 0) {
               document.body.style.overflow = 'auto';
            }
        }
    }
    
    const observer = new MutationObserver(function() {
        removeAds();
    });
    
    if (document.documentElement) {
        observer.observe(document.documentElement, {childList: true, subtree: true});
    }
    
    removeAds();
    setInterval(removeAds, 1000);
})();
""";

  static final List<String> adBlockDomains = [
    // Google Ads
    "googleadservices.com",
    "googlesyndication.com",
    "doubleclick.net",
    "googletagservices.com",
    "adservice.google.com",
    "pagead2.googlesyndication.com",
    "tpc.googlesyndication.com",
    "partner.googleadservices.com",
    "adwords.google.com",

    // YouTube Ads
    "youtube.com/api/stats/ads",
    "youtube.com/pagead",
    "youtube.com/ptracking",
    "youtube.com/youtubei/v1/log_event",
    "static.doubleclick.net",
    "s0.2mdn.net",
    "imasdk.googleapis.com",

    // Facebook / Twitter / Amazon
    "facebook.com/tr",
    "connect.facebook.net/en_US/fbevents.js",
    "an.facebook.com",
    "staticxx.facebook.com",
    "ads-twitter.com",
    "ads.twitter.com",
    "aax-us-east.amazon-adsystem.com",
    "aax.amazon-adsystem.com",
    "amazon-adsystem.com",
    "fls-na.amazon.com",

    // Microsoft / General
    "bat.bing.com",
    "ads.msn.com",
    "adnexus.net",
    "appnexus.com",
    "ib.adnxs.com",
    "adnxs.com",
    "adsrvr.org",
    "adtech.com",
    "advertising.com",
    "adcolony.com",
    "admob.com",
    "taboola.com",
    "trc.taboola.com",
    "cdn.taboola.com",
    "outbrain.com",
    "widgets.outbrain.com",
    "criteo.com",
    "dis.criteo.com",
    "rtax.criteo.com",

    // Tracking & Popups
    "scorecardresearch.com",
    "quantserve.com",
    "quantcast.com",
    "push.notifications.com",
    "pushwoosh.com",
    "onesignal.com"
  ];
}
