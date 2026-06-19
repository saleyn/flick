// run.js
// ======
// Minimal QUnit-compatible runner for flick-test.js, executed by `node`.
// Loads flick.js and flick-test.js as global scripts (like <script> tags in
// a browser), provides `equal`/`deepEqual` as plain assertions, and exits
// non-zero on any failure so this can be invoked from `mix test`.

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

let failures = 0;

global.equal = (actual, expected, message) => {
  try {
    assert.strictEqual(actual, expected, message);
    console.log(`ok - ${message}`);
  } catch (e) {
    failures++;
    console.error(`not ok - ${message}\n  ${e.message}`);
  }
};

global.deepEqual = (actual, expected, message) => {
  try {
    assert.deepStrictEqual(actual, expected, message);
    console.log(`ok - ${message}`);
  } catch (e) {
    failures++;
    console.error(`not ok - ${message}\n  ${e.message}`);
  }
};

global.throws = (fn, message) => {
  try {
    assert.throws(fn);
    console.log(`ok - ${message}`);
  } catch (e) {
    failures++;
    console.error(`not ok - ${message}\n  ${e.message}`);
  }
};

function runScript(file) {
  const code = fs.readFileSync(file, "utf8");
  vm.runInThisContext(code, { filename: file });
}

runScript(path.join(__dirname, "..", "..", "priv", "flick.js"));
runScript(path.join(__dirname, "flick-test.js"));

vm.runInThisContext("flick_test()", { filename: "run.js" });

if (failures > 0) {
  console.error(`\n${failures} failure(s)`);
  process.exit(1);
} else {
  console.log("\nAll flick.js tests passed");
}
