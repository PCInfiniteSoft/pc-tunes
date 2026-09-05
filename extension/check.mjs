// Catches a call to a function that does not exist anywhere in the file.
//
// `node --check` only parses; it is perfectly happy with `runCommand(...)` after
// `runCommand` has been deleted, and the extension then fails at runtime, in a page,
// with nothing to show for it but an entry on Chrome's error list. That is exactly
// what happened when the search feature was cut out of `inject.js` and took the
// command dispatcher next to it. This is the check that would have caught it.
//
// Deliberately crude: a regex pass, not a parser. It looks only at bare calls —
// `name(...)` with no `.` in front — so it says nothing about `foo.bar()`, and it is
// happy to be wrong about a name that is genuinely a global by listing it below.

import { readFileSync } from "node:fs";

const KEYWORDS = new Set([
  "if", "for", "while", "switch", "catch", "return", "typeof", "function", "new",
  "delete", "void", "in", "of", "do", "else", "await", "yield", "throw", "case",
  "async",
]);

/// Blanks out comments and string bodies, keeping every newline so reported line
/// numbers still point at the right place. Without this, prose in a doc comment reads
/// as a call — "the (correctly-chosen) player bar" looks exactly like `the(...)`.
function stripCommentsAndStrings(source) {
  let out = "";
  let i = 0;
  const blank = (text) => text.replace(/[^\n]/g, " ");

  while (i < source.length) {
    const two = source.slice(i, i + 2);
    if (two === "//") {
      const end = source.indexOf("\n", i);
      const stop = end === -1 ? source.length : end;
      out += blank(source.slice(i, stop));
      i = stop;
      continue;
    }
    if (two === "/*") {
      const end = source.indexOf("*/", i + 2);
      const stop = end === -1 ? source.length : end + 2;
      out += blank(source.slice(i, stop));
      i = stop;
      continue;
    }
    const quote = source[i];
    if (quote === '"' || quote === "'" || quote === "`") {
      let j = i + 1;
      while (j < source.length) {
        if (source[j] === "\\") {
          j += 2;
          continue;
        }
        if (source[j] === quote) break;
        j += 1;
      }
      // The quotes themselves are kept so the surrounding syntax still parses by eye.
      out += quote + blank(source.slice(i + 1, j)) + (source[j] === quote ? quote : "");
      i = j + 1;
      continue;
    }
    out += source[i];
    i += 1;
  }
  return out;
}

// Globals these files legitimately call by bare name.
const GLOBALS = new Set([
  "setTimeout", "clearTimeout", "setInterval", "clearInterval", "queueMicrotask",
  "parseInt", "parseFloat", "isNaN", "isFinite", "encodeURIComponent",
  "decodeURIComponent", "structuredClone", "fetch", "Array", "Object", "String",
  "Number", "Boolean", "Symbol", "Promise", "Error", "TypeError", "Set", "Map",
  "WeakMap", "WeakSet", "Date", "RegExp", "JSON", "Math", "MutationObserver",
  "WebSocket", "URL", "URLSearchParams", "Uint8Array", "TextEncoder", "TextDecoder",
]);

const DECLARATION_PATTERNS = [
  /\bfunction\s+([A-Za-z_$][\w$]*)/g,
  /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g,
  /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*;/g,
];

// A bare call: an identifier followed by "(" that is not preceded by "." or a word
// character, and is not a declaration of its own.
const CALL_PATTERN = /(^|[^.\w$])([A-Za-z_$][\w$]*)\s*\(/g;

let failed = false;

for (const path of process.argv.slice(2)) {
  const source = stripCommentsAndStrings(readFileSync(path, "utf8"));

  const declared = new Set();
  for (const pattern of DECLARATION_PATTERNS) {
    for (const match of source.matchAll(pattern)) declared.add(match[1]);
  }
  // Parameters count as declared: a callback may well call one.
  for (const match of source.matchAll(/\(([^()]*)\)\s*=>/g)) {
    for (const part of match[1].split(",")) {
      const name = part.trim().split(/[\s=:]/)[0];
      if (/^[A-Za-z_$][\w$]*$/.test(name)) declared.add(name);
    }
  }
  for (const match of source.matchAll(/\bfunction\s*[A-Za-z_$\w]*\s*\(([^()]*)\)/g)) {
    for (const part of match[1].split(",")) {
      const name = part.trim().split(/[\s=:]/)[0];
      if (/^[A-Za-z_$][\w$]*$/.test(name)) declared.add(name);
    }
  }

  const missing = new Map();
  for (const match of source.matchAll(CALL_PATTERN)) {
    const name = match[2];
    if (KEYWORDS.has(name) || GLOBALS.has(name) || declared.has(name)) continue;
    if (!missing.has(name)) {
      missing.set(name, source.slice(0, match.index).split("\n").length);
    }
  }

  for (const [name, line] of missing) {
    console.error(`${path}:${line}: calls '${name}', which is not defined in this file`);
    failed = true;
  }
}

if (failed) {
  console.error("\nIf one of these really is a global, add it to GLOBALS in check.mjs.");
  process.exit(1);
}
console.log("extension: every bare call resolves");
