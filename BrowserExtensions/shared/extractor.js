function ezclipExtractDesignContext() {
  const visible = (el) => {
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);
    return rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none" && style.opacity !== "0";
  };

  const selectorFor = (el) => {
    const tag = el.tagName.toLowerCase();
    if (el.id) return `${tag}#${CSS.escape(el.id)}`;
    const cls = [...el.classList].slice(0, 2).map((c) => `.${CSS.escape(c)}`).join("");
    return `${tag}${cls}`;
  };

  const textElements = [...document.querySelectorAll("h1,h2,h3,h4,h5,h6,p,span,a,li,td,th,button,label")].filter(visible);
  const fontMap = new Map();
  for (const el of textElements.slice(0, 600)) {
    const text = (el.innerText || el.textContent || "").trim().replace(/\s+/g, " ");
    if (text.length < 8) continue;
    const style = window.getComputedStyle(el);
    const key = `${style.fontFamily}|${style.fontSize}|${style.fontWeight}`;
    const existing = fontMap.get(key);
    if (existing) {
      existing.count += 1;
    } else {
      fontMap.set(key, {
        fontFamily: style.fontFamily.split(",")[0].replace(/['"]/g, "").trim(),
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        sampleText: text.slice(0, 80),
        selector: selectorFor(el),
        count: 1
      });
    }
  }

  const colorMap = new Map();
  const addColor = (role, value) => {
    if (!value || value === "rgba(0, 0, 0, 0)" || value === "transparent") return;
    const key = `${role}|${value}`;
    colorMap.set(key, { role, value, count: (colorMap.get(key)?.count || 0) + 1 });
  };
  for (const el of textElements.slice(0, 600)) {
    const style = window.getComputedStyle(el);
    addColor("text", style.color);
    addColor("background", style.backgroundColor);
    addColor("border", style.borderTopColor);
  }

  const root = window.getComputedStyle(document.documentElement);
  const cssTokens = [];
  for (let i = 0; i < root.length && cssTokens.length < 120; i++) {
    const name = root[i];
    if (name.startsWith("--")) {
      const value = root.getPropertyValue(name).trim();
      if (value) cssTokens.push({ name, value });
    }
  }

  const fontFaceRules = [];
  for (const sheet of [...document.styleSheets]) {
    let rules;
    try {
      rules = sheet.cssRules;
    } catch (_) {
      continue;
    }
    for (const rule of [...rules]) {
      if (rule.type === CSSRule.FONT_FACE_RULE && fontFaceRules.length < 48) {
        fontFaceRules.push(rule.cssText);
      }
    }
  }

  const rgbToHex = (value) => {
    const match = value.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/i);
    if (!match) return value;
    return "#" + [match[1], match[2], match[3]]
      .map((part) => Number(part).toString(16).padStart(2, "0"))
      .join("");
  };

  const previewHTML = (source, text) => {
    const tag = source.tagName.toLowerCase() === "a" ? "a" : "button";
    const clone = document.createElement(tag);
    const style = window.getComputedStyle(source);
    const keep = [
      "display", "align-items", "justify-content", "gap", "padding", "border", "border-radius",
      "background", "background-color", "color", "box-shadow", "font-family", "font-size",
      "font-weight", "line-height", "letter-spacing", "text-transform", "text-decoration",
      "white-space", "min-width", "height", "text-align"
    ];
    for (const prop of keep) clone.style.setProperty(prop, style.getPropertyValue(prop));
    clone.style.margin = "0";
    clone.style.position = "relative";
    clone.style.boxSizing = "border-box";
    clone.style.maxWidth = "100%";
    clone.style.cursor = "default";
    clone.style.transform = "none";
    clone.style.animation = "none";
    clone.textContent = text;
    if (tag === "a") clone.setAttribute("role", "button");
    return clone.outerHTML;
  };

  const buttonCandidates = [
    ...document.querySelectorAll("button,[role='button'],a[href]")
  ].filter((el) => {
    if (!visible(el)) return false;
    const rect = el.getBoundingClientRect();
    const text = (el.innerText || el.textContent || "").trim().replace(/\s+/g, " ");
    if (text.length < 2 || text.length > 48) return false;
    if (rect.width < 16 || rect.height < 24 || rect.width > 640 || rect.height > 220) return false;
    if (rect.height / rect.width > 1.4 || rect.width / rect.height > 10) return false;
    const style = window.getComputedStyle(el);
    const hasButtonSignal = el.tagName.toLowerCase() === "button" || el.getAttribute("role") === "button" ||
      style.backgroundColor !== "rgba(0, 0, 0, 0)" || parseFloat(style.borderTopWidth) > 0;
    return hasButtonSignal;
  });

  const buttons = [];
  const seenButtons = new Set();
  for (const el of buttonCandidates) {
    const text = (el.innerText || el.textContent || "").trim().replace(/\s+/g, " ");
    if (seenButtons.has(text.toLowerCase())) continue;
    seenButtons.add(text.toLowerCase());
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);
    buttons.push({
      text,
      html: previewHTML(el, text)
        .replaceAll("rgb(255, 255, 255)", "#fff")
        .replaceAll("rgb(0, 0, 0)", "#000")
        .slice(0, 12000),
      width: Math.round(rect.width),
      height: Math.round(rect.height),
      backgroundColor: rgbToHex(style.backgroundColor),
      color: rgbToHex(style.color)
    });
    if (buttons.length >= 12) break;
  }

  return {
    url: location.href,
    title: document.title,
    scroll: {
      x: window.scrollX,
      y: window.scrollY,
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      documentHeight: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)
    },
    fonts: [...fontMap.values()].sort((a, b) => b.count - a.count).slice(0, 16),
    colors: [...colorMap.values()].sort((a, b) => b.count - a.count).slice(0, 24),
    cssTokens,
    buttons,
    fontFaceCSS: fontFaceRules.join("\n").slice(0, 120000)
  };
}

if (typeof module !== "undefined") {
  module.exports = { ezclipExtractDesignContext };
}
