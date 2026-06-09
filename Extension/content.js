// ezclip content script
// Stays dormant until the background script sends { action: "capture" }.
// Extracts design tokens (buttons, colors, fonts, scroll, metadata) and
// returns them to the background script. Never mutates the page DOM.

(function () {
  "use strict";

  // Guard: if the browser API isn't available (e.g., direct page load), no-op
  if (typeof browser === "undefined" || !browser.runtime || !browser.runtime.onMessage) {
    return;
  }

  browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message && message.action === "capture") {
      captureDesignTokens().then(sendResponse).catch(() => sendResponse(null));
      return true; // async response
    }
  });

  async function captureDesignTokens() {
    // Wait for fonts to be loaded before extraction
    try {
      if (document.fonts && document.fonts.ready) {
        await document.fonts.ready;
      }
    } catch (e) {
      // ignore
    }

    const url = window.location.href;
    const title = document.title;
    const viewport = {
      width: window.innerWidth,
      height: window.innerHeight,
    };
    const scroll = {
      y: Math.round(window.scrollY || window.pageYOffset || 0),
      totalHeight: Math.round(document.documentElement.scrollHeight || document.body.scrollHeight || 0),
      percent: 0,
    };
    if (scroll.totalHeight > 0) {
      scroll.percent = Math.round((scroll.y / scroll.totalHeight) * 100);
    }

    const buttons = extractButtons();
    const colors = extractColors();
    const fonts = extractFonts();

    return {
      url,
      title,
      viewport,
      scroll,
      buttons,
      colors,
      fonts,
    };
  }

  // ---------- Buttons ----------

  function extractButtons() {
    const candidates = document.querySelectorAll("button, a");
    const results = [];
    const viewportW = window.innerWidth;
    const viewportH = window.innerHeight;
    const scrollX = window.scrollX || window.pageXOffset || 0;
    const scrollY = window.scrollY || window.pageYOffset || 0;

    for (const el of candidates) {
      if (results.length >= 30) break;

      const tag = el.tagName.toLowerCase();
      const text = (el.innerText || "").trim();

      // Heuristic filters (based on Button Stealer research)
      if (text.length < 2 || text.length > 40) continue;
      if (text.includes("\n")) continue;

      const rect = el.getBoundingClientRect();
      const width = rect.width;
      const height = rect.height;
      if (width < 20 || height < 20) continue;
      if (width > 600 || height > 200) continue;
      const ratio = width / height;
      if (ratio < 0.5 || ratio > 8) continue;

      // Visibility check
      const style = window.getComputedStyle(el);
      if (style.display === "none") continue;
      if (style.visibility === "hidden") continue;
      if (style.opacity === "0") continue;

      // Viewport check (element must be visible on screen)
      const visible =
        rect.bottom > 0 &&
        rect.right > 0 &&
        rect.top < viewportH &&
        rect.left < viewportW;
      if (!visible) continue;

      // Non-transparent background or meaningful color
      const bg = style.backgroundColor;
      const isTransparent = bg === "rgba(0, 0, 0, 0)" || bg === "transparent" || bg === "";
      if (isTransparent && !hasNonTransparentChildBg(el)) continue;

      // Parent context: closest semantic container
      const parent = getParentContext(el);

      const rectData = {
        x: Math.round(rect.left + scrollX),
        y: Math.round(rect.top + scrollY),
        width: Math.round(width),
        height: Math.round(height),
      };

      const stylesData = {
        backgroundColor: rgbToHex(style.backgroundColor) || style.backgroundColor,
        color: rgbToHex(style.color) || style.color,
        fontSize: style.fontSize,
        fontFamily: cleanFontFamily(style.fontFamily),
        fontWeight: style.fontWeight,
        borderRadius: shorthandBorderRadius(style),
        padding: shorthandPadding(style),
        boxShadow: style.boxShadow === "none" ? undefined : style.boxShadow,
        border: shorthandBorder(style),
        width: style.width,
        height: style.height,
      };

      // Remove undefined / default-ish values to keep payload light
      for (const key of Object.keys(stylesData)) {
        if (stylesData[key] === undefined || stylesData[key] === "none" || stylesData[key] === "0px" || stylesData[key] === "rgba(0, 0, 0, 0)" || stylesData[key] === "auto") {
          delete stylesData[key];
        }
      }

      results.push({
        text,
        tag,
        styles: stylesData,
        rect: rectData,
        parent,
      });
    }

    return results;
  }

  function hasNonTransparentChildBg(el) {
    for (const child of el.children) {
      const childStyle = window.getComputedStyle(child);
      const bg = childStyle.backgroundColor;
      if (bg && bg !== "rgba(0, 0, 0, 0)" && bg !== "transparent" && bg !== "") {
        return true;
      }
    }
    return false;
  }

  function getParentContext(el) {
    const stopTags = new Set(["body", "html", "main", "section", "article", "nav", "header", "footer", "aside"]);
    const parts = [];
    let current = el.parentElement;
    let depth = 0;
    while (current && depth < 6) {
      const tag = current.tagName.toLowerCase();
      let part = tag;
      if (current.id) {
        part += "#" + current.id;
      } else if (current.className && typeof current.className === "string") {
        const firstClass = current.className.trim().split(/\s+/)[0];
        if (firstClass) {
          part += "." + firstClass;
        }
      }
      parts.unshift(part);
      if (stopTags.has(tag)) break;
      current = current.parentElement;
      depth++;
    }
    return parts.join(" > ");
  }

  // ---------- Colors ----------

  function extractColors() {
    const colorMap = new Map(); // hex -> count
    const elements = document.querySelectorAll("*");
    for (const el of elements) {
      const style = window.getComputedStyle(el);
      const bg = style.backgroundColor;
      const fg = style.color;
      const bgHex = rgbToHex(bg);
      const fgHex = rgbToHex(fg);
      if (bgHex) {
        colorMap.set(bgHex, (colorMap.get(bgHex) || 0) + 1);
      }
      if (fgHex) {
        colorMap.set(fgHex, (colorMap.get(fgHex) || 0) + 1);
      }
    }

    const sorted = Array.from(colorMap.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 20);

    // Heuristic role assignment for the top colors
    const roles = assignColorRoles(sorted);

    return sorted.map(([hex, count], index) => ({
      hex,
      count,
      role: roles[index] || undefined,
    }));
  }

  function assignColorRoles(sortedColors) {
    const roles = new Array(sortedColors.length);
    // Try to guess a primary accent (first non-black/white/non-gray)
    for (let i = 0; i < sortedColors.length; i++) {
      const hex = sortedColors[i][0];
      if (isNeutral(hex)) continue;
      roles[i] = "primary";
      break;
    }
    // Most frequent white-ish is likely background
    for (let i = 0; i < sortedColors.length; i++) {
      const hex = sortedColors[i][0];
      if (isLight(hex)) {
        roles[i] = "background";
        break;
      }
    }
    // Most frequent dark is likely text
    for (let i = 0; i < sortedColors.length; i++) {
      const hex = sortedColors[i][0];
      if (isDark(hex)) {
        roles[i] = "text";
        break;
      }
    }
    return roles;
  }

  function isNeutral(hex) {
    const rgb = hexToRgb(hex);
    if (!rgb) return false;
    const max = Math.max(rgb.r, rgb.g, rgb.b);
    const min = Math.min(rgb.r, rgb.g, rgb.b);
    return max - min < 20;
  }

  function isLight(hex) {
    const rgb = hexToRgb(hex);
    if (!rgb) return false;
    const luminance = (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b) / 255;
    return luminance > 0.85;
  }

  function isDark(hex) {
    const rgb = hexToRgb(hex);
    if (!rgb) return false;
    const luminance = (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b) / 255;
    return luminance < 0.25;
  }

  // ---------- Fonts ----------

  function extractFonts() {
    const results = [];
    const seen = new Set();

    // Primary heading font
    const h1 = document.querySelector("h1");
    if (h1) {
      const style = window.getComputedStyle(h1);
      const family = cleanFontFamily(style.fontFamily);
      const weight = style.fontWeight;
      const styleVal = style.fontStyle;
      const key = family + "|" + weight + "|" + styleVal;
      if (!seen.has(key)) {
        seen.add(key);
        results.push({ family, weight, style: styleVal, role: "heading" });
      }
    }

    // Body font
    const body = document.body;
    if (body) {
      const style = window.getComputedStyle(body);
      const family = cleanFontFamily(style.fontFamily);
      const weight = style.fontWeight;
      const styleVal = style.fontStyle;
      const key = family + "|" + weight + "|" + styleVal;
      if (!seen.has(key)) {
        seen.add(key);
        results.push({ family, weight, style: styleVal, role: "body" });
      }
    }

    // All loaded @font-face fonts that are actually rendered
    try {
      if (document.fonts) {
        for (const fontFace of document.fonts) {
          const family = fontFace.family;
          const weight = String(fontFace.weight);
          const style = fontFace.style;
          const key = family + "|" + weight + "|" + style;
          if (seen.has(key)) continue;
          // Check if this font is actually used on the page
          const sampleText = "abcdefghijklmnopqrstuvwxyz0123456789";
          if (document.fonts.check(`${style} ${weight} 16px "${family}"`, sampleText)) {
            seen.add(key);
            results.push({ family, weight, style, role: "loaded" });
          }
        }
      }
    } catch (e) {
      // ignore font API errors
    }

    return results;
  }

  // ---------- Helpers ----------

  function rgbToHex(rgbStr) {
    if (!rgbStr) return null;
    rgbStr = rgbStr.trim();
    const m = rgbStr.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/);
    if (!m) return null;
    const r = parseInt(m[1], 10);
    const g = parseInt(m[2], 10);
    const b = parseInt(m[3], 10);
    const a = m[4] !== undefined ? parseFloat(m[4]) : 1;
    if (a < 0.05) return null; // effectively transparent
    return "#" + [r, g, b].map((x) => x.toString(16).padStart(2, "0")).join("");
  }

  function hexToRgb(hex) {
    const m = hex.match(/^#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2})$/i);
    if (!m) return null;
    return {
      r: parseInt(m[1], 16),
      g: parseInt(m[2], 16),
      b: parseInt(m[3], 16),
    };
  }

  function cleanFontFamily(ff) {
    if (!ff) return "";
    // Remove quotes, extract the first font name
    return ff
      .split(",")[0]
      .replace(/["']/g, "")
      .trim();
  }

  function shorthandBorderRadius(style) {
    const tl = style.borderTopLeftRadius;
    const tr = style.borderTopRightRadius;
    const br = style.borderBottomRightRadius;
    const bl = style.borderBottomLeftRadius;
    if (!tl || tl === "0px") return undefined;
    if (tl === tr && tr === br && br === bl) return tl;
    return `${tl} ${tr} ${br} ${bl}`;
  }

  function shorthandPadding(style) {
    const t = style.paddingTop;
    const r = style.paddingRight;
    const b = style.paddingBottom;
    const l = style.paddingLeft;
    if (t === "0px" && r === "0px" && b === "0px" && l === "0px") return undefined;
    if (t === b && r === l) {
      if (t === r) return t;
      return `${t} ${r}`;
    }
    return `${t} ${r} ${b} ${l}`;
  }

  function shorthandBorder(style) {
    const w = style.borderWidth;
    const s = style.borderStyle;
    const c = style.borderColor;
    if (s === "none" || w === "0px") return undefined;
    // If all sides are uniform
    const wT = style.borderTopWidth;
    const wR = style.borderRightWidth;
    const wB = style.borderBottomWidth;
    const wL = style.borderLeftWidth;
    const sT = style.borderTopStyle;
    const sR = style.borderRightStyle;
    const sB = style.borderBottomStyle;
    const sL = style.borderLeftStyle;
    const cT = style.borderTopColor;
    const cR = style.borderRightColor;
    const cB = style.borderBottomColor;
    const cL = style.borderLeftColor;
    if (wT === wR && wR === wB && wB === wL && sT === sR && sR === sB && sB === sL && cT === cR && cR === cB && cB === cL) {
      return `${wT} ${sT} ${cT}`;
    }
    return undefined;
  }
})();
