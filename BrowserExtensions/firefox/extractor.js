function ezclipExtractDesignContext() {
  const visible = (el) => {
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);
    return rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none" && Number(style.opacity || "1") > 0.02;
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

  const resolveFontURLs = (cssText, baseHref) => cssText.replace(/url\(([^)]+)\)/gi, (_, rawURL) => {
    const trimmed = rawURL.trim();
    const quote = trimmed.startsWith("\"") || trimmed.startsWith("'") ? trimmed[0] : "";
    const unquoted = quote ? trimmed.slice(1, -1) : trimmed;
    if (/^(data:|blob:|https?:|file:|chrome-extension:|moz-extension:)/i.test(unquoted)) {
      return `url(${quote}${unquoted}${quote})`;
    }
    try {
      return `url(${quote}${new URL(unquoted, baseHref || document.baseURI).href}${quote})`;
    } catch (_) {
      return `url(${trimmed})`;
    }
  });

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
        fontFaceRules.push(resolveFontURLs(rule.cssText, sheet.href));
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
      "border-color", "border-style", "border-width", "background", "background-color", "background-image",
      "color", "box-shadow", "font-family", "font-size",
      "font-weight", "line-height", "letter-spacing", "text-transform", "text-decoration",
      "white-space", "min-width", "height", "text-align", "outline"
    ];
    for (const prop of keep) clone.style.setProperty(prop, style.getPropertyValue(prop));
    const transparent = style.backgroundColor === "rgba(0, 0, 0, 0)" || style.backgroundColor === "transparent";
    if (transparent && !style.backgroundImage.includes("gradient")) {
      clone.style.backgroundColor = "rgba(255,255,255,.92)";
    }
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

  const buttonText = (el) => {
    const tag = el.tagName.toLowerCase();
    const label = el.getAttribute("aria-label") || el.getAttribute("title") || "";
    if (tag === "input") return (el.value || label).trim().replace(/\s+/g, " ");
    return (el.innerText || el.textContent || label).trim().replace(/\s+/g, " ");
  };

  const buttonCandidates = [
    ...document.querySelectorAll("button,[role='button'],a[href],input[type='button'],input[type='submit'],[onclick],[tabindex]")
  ].filter((el) => {
    if (!visible(el)) return false;
    const rect = el.getBoundingClientRect();
    const text = buttonText(el);
    if (text.length < 1 || text.length > 72) return false;
    if (rect.width < 12 || rect.height < 12 || rect.width > 820 || rect.height > 260) return false;
    if (rect.height / Math.max(rect.width, 1) > 3.2 || rect.width / Math.max(rect.height, 1) > 18) return false;
    const style = window.getComputedStyle(el);
    const tag = el.tagName.toLowerCase();
    const hasButtonSignal = tag === "button" || tag === "input" || el.getAttribute("role") === "button" ||
      el.hasAttribute("onclick") || el.getAttribute("tabindex") === "0" ||
      style.backgroundColor !== "rgba(0, 0, 0, 0)" || style.backgroundImage !== "none" ||
      parseFloat(style.borderTopWidth) > 0 || parseFloat(style.paddingLeft) + parseFloat(style.paddingRight) > 16;
    return hasButtonSignal;
  }).sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    const aScore = (ar.width * ar.height) + (ar.top >= 0 && ar.top < window.innerHeight ? 2000 : 0);
    const bScore = (br.width * br.height) + (br.top >= 0 && br.top < window.innerHeight ? 2000 : 0);
    return bScore - aScore;
  });

  const buttons = [];
  const seenButtons = new Set();
  for (const el of buttonCandidates) {
    const text = buttonText(el);
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
