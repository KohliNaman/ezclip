const test = require("node:test");
const assert = require("node:assert/strict");

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
