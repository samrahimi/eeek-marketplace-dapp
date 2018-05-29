function _defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } }

function _createClass(Constructor, protoProps, staticProps) { if (protoProps) _defineProperties(Constructor.prototype, protoProps); if (staticProps) _defineProperties(Constructor, staticProps); return Constructor; }

//
//
// background-images.js
//
// a javscript fallback for CSS 'object-fit' property for browsers that don't support it
if ('objectFit' in document.documentElement.style === false) {
  $('.bg-image').each(function attachBg() {
    var img = $(this);
    var src = img.attr('src');
    var classes = img.get(0).classList; // Replaces the default <img.bg-image> element with a <div.bg-image>
    // to attach background using legacy friendly CSS rules

    img.before($("<div class=\"" + classes + "\" style=\"background: url(" + src + "); background-size: cover; background-position: 50% 50%;\"></div>")); // Removes original <img.bg-image> as it is no longer required

    img.remove();
  });
} //
//
// prism.js
//
// Initialises the prism code highlighting plugin

/* global Prism */


Prism.highlightAll(); //
//
// smooth-scroll.js
//
// Initialises the prism code highlighting plugin

/* global SmoothScroll */

var mrSmoothScroll = new SmoothScroll('a[data-smooth-scroll]', {
  offset: $('body').attr('data-smooth-scroll-offset') || 0
}); //
//
// sticky.js
//
// Initialises the srollMonitor plugin and provides interface to watcher objects
// for sticking elements to the top of viewport while scrolling

/* global scrollMonitor */

var mrSticky = function ($) {
  /**
   * Check for scrollMonitor dependency
   * scrollMonitor - https://github.com/stutrek/scrollMonitor
   */
  if (typeof scrollMonitor === 'undefined') {
    throw new Error('mrSticky requires scrollMonitor.js (https://github.com/stutrek/scrollMonitor)');
  }
  /**
   * ------------------------------------------------------------------------
   * Constants
   * ------------------------------------------------------------------------
   */


  var NAME = 'mrSticky';
  var VERSION = '1.0.0';
  var DATA_KEY = 'mr.sticky';
  var EVENT_KEY = "." + DATA_KEY;
  var DATA_API_KEY = '.data-api';
  var JQUERY_NO_CONFLICT = $.fn[NAME];
  var NO_OFFSET = 0;
  var ClassName = {
    FIXED_TOP: 'position-fixed',
    FIXED_BOTTOM: 'sticky-bottom'
  };
  var Css = {
    HEIGHT: 'min-height',
    WIDTH: 'max-width',
    SPACE_TOP: 'top'
  };
  var Event = {
    LOAD_DATA_API: "load" + EVENT_KEY + DATA_API_KEY,
    RESIZE: "resize" + EVENT_KEY
  };
  var Options = {
    BELOW_NAV: 'below-nav',
    TOP: 'top'
  };
  var Selector = {
    DATA_ATTR: 'sticky',
    DATA_STICKY: '[data-sticky]',
    NAV_STICKY: 'body > div.nav-container > div[data-sticky="top"]'
  };
  /**
   * ------------------------------------------------------------------------
   * Class Definition
   * ------------------------------------------------------------------------
   */

  var Sticky =
  /*#__PURE__*/
  function () {
    function Sticky(element) {
      var $element = $(element);
      var stickyData = $element.data(Selector.DATA_ATTR);
      var stickyUntil = $element.closest('section') || null;
      this.element = element;
      this.stickBelowNav = stickyData === Options.BELOW_NAV;
      this.stickyUntil = stickyUntil;
      this.updateNavProperties();
      this.isNavElement = $element.is(this.navElement);
      this.initWatcher(element);
      this.updateCss();
      this.setResizeEvent();
    } // getters


    var _proto = Sticky.prototype;

    _proto.initWatcher = function initWatcher(element) {
      var _this = this;

      var $element = $(element);
      var notNavElement = !this.isNavElement;
      var offset = this.stickBelowNav && this.navIsSticky && notNavElement ? {
        top: this.navHeight
      } : NO_OFFSET;
      var watcher = scrollMonitor.create(element, offset); // ensure that we're always watching the place the element originally was

      watcher.lock();
      var untilWatcher = this.stickyUntil !== null ? scrollMonitor.create(this.stickyUntil, {
        bottom: -(watcher.height + offset.top)
      }) : null;
      this.watcher = watcher;
      this.untilWatcher = untilWatcher;
      this.navHeight = this.navHeight; // For navs that start at top, stick them immediately to avoid a jump

      if (this.isNavElement && watcher.top === 0 && !this.navIsAbsolute) {
        $element.addClass(ClassName.FIXED_TOP);
      }

      watcher.stateChange(function () {
        // Add fixed when element leaves via top of viewport or if nav is sitting at top
        $element.toggleClass(ClassName.FIXED_TOP, watcher.isAboveViewport || !_this.navIsAbsolute && _this.isNavElement && watcher.top === 0);
        $element.css(Css.SPACE_TOP, watcher.isAboveViewport && _this.navIsSticky && _this.stickBelowNav ? _this.navHeight : NO_OFFSET);
      });

      if (untilWatcher !== null) {
        untilWatcher.exitViewport(function () {
          // If the element is in a section, it will scroll up with the section
          $element.addClass(ClassName.FIXED_BOTTOM);
        });
        untilWatcher.enterViewport(function () {
          $element.removeClass(ClassName.FIXED_BOTTOM);
        });
      }
    };

    _proto.setResizeEvent = function setResizeEvent() {
      var _this2 = this;

      window.addEventListener('resize', function () {
        return _this2.updateCss();
      });
    };

    _proto.updateCss = function updateCss() {
      var $element = $(this.element); // Fix width by getting parent's width to avoid element spilling out when pos-fixed

      $element.css(Css.WIDTH, $element.parent().width());
      this.updateNavProperties();
      var elemHeight = $element.outerHeight();
      var notNavElement = !this.isNavElement; // Set a min-height to prevent "jumping" when sticking to top
      // but not applied to the nav element itself unless it is overlay (absolute) nav

      if (!this.navIsAbsolute && this.isNavElement || notNavElement) {
        $element.parent().css(Css.HEIGHT, elemHeight);
      }

      if (this.navIsSticky && notNavElement) {
        $element.css(Css.HEIGHT, elemHeight);
      }
    };

    _proto.updateNavProperties = function updateNavProperties() {
      var $navElement = this.navElement || $(Selector.NAV_STICKY).first();
      this.navElement = $navElement;
      this.navHeight = $navElement.outerHeight();
      this.navIsAbsolute = $navElement.css('position') === 'absolute';
      this.navIsSticky = $navElement.length;
    };

    Sticky.jQueryInterface = function jQueryInterface() {
      return this.each(function jqEachSticky() {
        var $element = $(this);
        var data = $element.data(DATA_KEY);

        if (!data) {
          data = new Sticky(this);
          $element.data(DATA_KEY, data);
        }
      });
    };

    _createClass(Sticky, null, [{
      key: "VERSION",
      get: function get() {
        return VERSION;
      }
    }]);

    return Sticky;
  }();
  /**
   * ------------------------------------------------------------------------
   * Initialise by data attribute
   * ------------------------------------------------------------------------
   */


  $(window).on(Event.LOAD_DATA_API, function () {
    var stickyElements = $.makeArray($(Selector.DATA_STICKY));
    /* eslint-disable no-plusplus */

    for (var i = stickyElements.length; i--;) {
      var $sticky = $(stickyElements[i]);
      Sticky.jQueryInterface.call($sticky, $sticky.data());
    }
  });
  /**
   * ------------------------------------------------------------------------
   * jQuery
   * ------------------------------------------------------------------------
   */

  /* eslint-disable no-param-reassign */

  $.fn[NAME] = Sticky.jQueryInterface;
  $.fn[NAME].Constructor = Sticky;

  $.fn[NAME].noConflict = function StickyNoConflict() {
    $.fn[NAME] = JQUERY_NO_CONFLICT;
    return Sticky.jQueryInterface;
  };
  /* eslint-enable no-param-reassign */


  return Sticky;
}(jQuery); //
//
// Util
//
// Medium Rare utility functions


var mrUtil = function ($) {
  // Activate tooltips
  $('[data-toggle="tooltip"]').tooltip();
  var Util = {
    activateIframeSrc: function activateIframeSrc(iframe) {
      var $iframe = $(iframe);

      if ($iframe.attr('data-src')) {
        $iframe.attr('src', $iframe.attr('data-src'));
      }
    },
    idleIframeSrc: function idleIframeSrc(iframe) {
      var $iframe = $(iframe);
      $iframe.attr('data-src', $iframe.attr('src')).attr('src', '');
    }
  };
  return Util;
}(jQuery);

$(document).ready(function () {
  $('.video-cover .video-play-icon').on('click touchstart', function clickedPlay() {
    var $iframe = $(this).closest('.video-cover').find('iframe');
    mrUtil.activateIframeSrc($iframe);
    $(this).parent('.video-cover').addClass('video-cover-playing');
  }); // Disable video cover behaviour on mobile devices to avoid user having to press twice

  var isTouchDevice = 'ontouchstart' in document.documentElement;

  if (isTouchDevice === true) {
    $('.video-cover').each(function activeateMobileIframes() {
      $(this).addClass('video-cover-touch');
      var $iframe = $(this).closest('.video-cover').find('iframe');
      mrUtil.activateIframeSrc($iframe);
    });
  } // <iframe> in modals


  $('.modal').on('shown.bs.modal', function modalShown() {
    var $modal = $(this);

    if ($modal.find('iframe[data-src]').length) {
      var $iframe = $modal.find('iframe[data-src]');
      mrUtil.activateIframeSrc($iframe);
    }
  });
  $('.modal').on('hidden.bs.modal', function modalHidden() {
    var $modal = $(this);

    if ($modal.find('iframe[src]').length) {
      var $iframe = $modal.find('iframe[data-src]');
      mrUtil.idleIframeSrc($iframe);
    }
  });
  $('[data-toggle="tooltip"]').tooltip();
}); //
//
// wizard.js
//
// initialises the jQuery Smart Wizard plugin

$(document).ready(function () {
  $('.wizard').smartWizard({
    transitionEffect: 'fade',
    showStepURLhash: false,
    toolbarSettings: {
      toolbarPosition: 'none'
    }
  });
});