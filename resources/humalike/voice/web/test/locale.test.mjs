import assert from "node:assert/strict";
import test from "node:test";
import { LANGUAGES, language, setLanguage, t, texts } from "../src/locale.mjs";

test("english is the default and the fallback", () => {
  assert.equal(language(), "en");
  assert.equal(setLanguage("xx"), "en");
  assert.equal(setLanguage(undefined), "en");
  assert.equal(t("title"), "Voice settings");
});

test("a region suffix selects the base language", () => {
  assert.equal(setLanguage("pl-PL"), "pl");
  assert.equal(t("title"), "Ustawienia głosu");
  assert.equal(setLanguage("PL"), "pl");
  setLanguage("en");
});

test("placeholders are filled and unknown keys render as themselves", () => {
  assert.equal(t("diag.sources", { count: 3 }), "3 sources");
  assert.equal(t("error.micPrefix", {}), "WebRTC microphone: {message}");
  assert.equal(t("no.such.key"), "no.such.key");
});

test("every language carries every key", () => {
  const english = Object.keys(texts("en"));
  for (const code of LANGUAGES) {
    const keys = Object.keys(texts(code));
    assert.deepEqual(keys.sort(), [...english].sort(), `${code} keys differ from en`);
  }
});
