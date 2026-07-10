const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const { ezclipExtractDesignContext } = require("../shared/extractor.js");

function installDOMMock(fontRuleCSS, sheetHref = "https://example.com/assets/site.css") {
  global.CSS = { escape: (value) => value };
  global.CSSRule = { FONT_FACE_RULE: 5 };
  global.window = {
    scrollX: 0,
    scrollY: 0,
    innerWidth: 1200,
    innerHeight: 800
  };
  global.document = {
    title: "Example",
    baseURI: "https://example.com/pages/pricing",
    body: { scrollHeight: 1600 },
    documentElement: { scrollHeight: 1700 },
    styleSheets: [
      {
        href: sheetHref,
        cssRules: [{ type: CSSRule.FONT_FACE_RULE, cssText: fontRuleCSS }]
      }
    ],
    querySelectorAll() {
      return [];
    }
  };
  global.location = { href: "https://example.com/pages/pricing" };
  global.getComputedStyle = () => ({ length: 0 });
  window.getComputedStyle = global.getComputedStyle;
}

test("extractor resolves relative font URLs against stylesheet URL", () => {
  installDOMMock("@font-face { font-family: Example; src: url('../fonts/example.woff2'); }");

  const context = ezclipExtractDesignContext();

  assert.match(context.fontFaceCSS, /https:\/\/example\.com\/fonts\/example\.woff2/);
});

test("extractor preserves absolute font URLs", () => {
  installDOMMock("@font-face { font-family: Example; src: url('https://cdn.example.com/example.woff2'); }");

  const context = ezclipExtractDesignContext();

  assert.match(context.fontFaceCSS, /https:\/\/cdn\.example\.com\/example\.woff2/);
});

function makeStyle(overrides = {}) {
  const values = {
    visibility: "visible",
    display: "inline-flex",
    opacity: "1",
    backgroundColor: "rgb(20, 90, 220)",
    backgroundImage: "none",
    color: "rgb(255, 255, 255)",
    borderTopWidth: "1px",
    paddingLeft: "14px",
    paddingRight: "14px",
    fontFamily: "Example Sans",
    fontSize: "16px",
    fontWeight: "700",
    lineHeight: "20px",
    ...overrides
  };
  return {
    ...values,
    length: 0,
    getPropertyValue(prop) {
      return values[prop] || values[prop.replace(/-([a-z])/g, (_, c) => c.toUpperCase())] || "";
    }
  };
}

function makeElement(tagName, rect, attrs = {}, style = makeStyle()) {
  return {
    tagName: tagName.toUpperCase(),
    id: "",
    classList: [],
    value: attrs.value || "",
    innerText: attrs.text || "",
    textContent: attrs.text || "",
    style: { setProperty(prop, value) { this[prop] = value; } },
    getBoundingClientRect() {
      return { top: rect.top || 0, width: rect.width, height: rect.height };
    },
    getAttribute(name) {
      return attrs[name] || null;
    },
    hasAttribute(name) {
      return Object.prototype.hasOwnProperty.call(attrs, name);
    },
    setAttribute(name, value) {
      attrs[name] = value;
    },
    get outerHTML() {
      const tag = this.tagName.toLowerCase();
      return `<${tag}>${this.textContent}</${tag}>`;
    },
    __style: style
  };
}

function installButtonDOMMock(elements) {
  global.CSS = { escape: (value) => value };
  global.CSSRule = { FONT_FACE_RULE: 5 };
  global.window = {
    scrollX: 0,
    scrollY: 0,
    innerWidth: 1200,
    innerHeight: 800
  };
  global.document = {
    title: "Buttons",
    baseURI: "https://example.com/",
    body: { scrollHeight: 900 },
    documentElement: { scrollHeight: 900 },
    styleSheets: [],
    createElement(tag) {
      const attrs = {};
      const styleValues = {};
      return {
        tagName: tag.toUpperCase(),
        style: {
          setProperty(prop, value) {
            styleValues[prop] = value;
          }
        },
        textContent: "",
        setAttribute(name, value) {
          attrs[name] = value;
        },
        get outerHTML() {
          const attrText = Object.entries(attrs).map(([key, value]) => ` ${key}="${value}"`).join("");
          const styleText = Object.entries(styleValues).map(([key, value]) => `${key}: ${value};`).join(" ");
          const styleAttr = styleText ? ` style="${styleText}"` : "";
          return `<${tag}${attrText}${styleAttr}>${this.textContent}</${tag}>`;
        }
      };
    },
    querySelectorAll(selector) {
      if (selector.includes("button") || selector.includes("[onclick]")) return elements;
      return [];
    }
  };
  global.location = { href: "https://example.com/buttons" };
  global.getComputedStyle = (el) => el?.__style || makeStyle({ length: 0 });
  window.getComputedStyle = global.getComputedStyle;
}

test("extractor captures aria-label icon buttons", () => {
  installButtonDOMMock([
    makeElement("button", { width: 32, height: 32 }, { "aria-label": "Search" })
  ]);

  const context = ezclipExtractDesignContext();

  assert.equal(context.buttons[0].text, "Search");
});

test("extractor captures custom clickable controls", () => {
  installButtonDOMMock([
    makeElement("div", { width: 180, height: 44 }, { onclick: "checkout()", text: "Checkout" })
  ]);

  const context = ezclipExtractDesignContext();

  assert.equal(context.buttons[0].text, "Checkout");
});

test("packaged extractor copies stay in sync", () => {
  const root = path.resolve(__dirname, "..");
  const shared = fs.readFileSync(path.join(root, "shared/extractor.js"), "utf8");
  assert.equal(fs.readFileSync(path.join(root, "chromium/extractor.js"), "utf8"), shared);
  assert.equal(fs.readFileSync(path.join(root, "firefox/extractor.js"), "utf8"), shared);
});
