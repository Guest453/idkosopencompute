const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const root = path.resolve(__dirname, "..");

function filesUnder(directory) {
  const output = [];
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) output.push(...filesUnder(full));
    else output.push(full);
  }
  return output;
}

const luaFiles = filesUnder(root).filter(file => file.endsWith(".lua"));
for (const file of luaFiles) {
  luaparse.parse(fs.readFileSync(file, "utf8"), {luaVersion: "5.3", encodingMode: "x-user-defined"});
}

const imagePath = path.join(root, "image.lua");
const imageAst = luaparse.parse(fs.readFileSync(imagePath, "utf8"), {luaVersion: "5.3", encodingMode: "x-user-defined"});
if (imageAst.body.length !== 1 || imageAst.body[0].type !== "ReturnStatement") {
  throw new Error("image.lua must contain one return statement");
}
const image = imageAst.body[0].arguments[0];
if (!image || image.type !== "TableConstructorExpression") throw new Error("image.lua must return a table");

function namedField(table, name) {
  return table.fields.find(field => field.type === "TableKeyString" && field.key.name === name);
}

function stringField(table, name) {
  const field = namedField(table, name);
  if (!field || field.value.type !== "StringLiteral") throw new Error(`missing string field ${name}`);
  return field.value.value;
}

const filesField = namedField(image, "files");
if (!filesField || filesField.value.type !== "TableConstructorExpression") {
  throw new Error("image.lua is missing its files table");
}

const sources = new Set();
const targets = new Set();
for (const field of filesField.value.fields) {
  if (field.type !== "TableValue" || field.value.type !== "TableConstructorExpression") {
    throw new Error("every image file must be a literal table entry");
  }
  const source = stringField(field.value, "source");
  const target = stringField(field.value, "target");
  if (sources.has(source) || targets.has(target)) throw new Error(`duplicate image mapping ${source} -> ${target}`);
  if (!source.startsWith("src/") || source.includes("..") || !target.startsWith("/") || target.includes("..")) {
    throw new Error(`unsafe image mapping ${source} -> ${target}`);
  }
  if (!fs.existsSync(path.join(root, ...source.split("/")))) throw new Error(`missing payload source ${source}`);
  sources.add(source);
  targets.add(target);
}

for (const required of ["/init.lua", "/idkos/boot.lua", "/idkos/system/runtime.lua", "/idkos/system/core.lua", "/idkos/system/ui.lua"]) {
  if (!targets.has(required)) throw new Error(`missing required image target ${required}`);
}
for (const sourceFile of filesUnder(path.join(root, "src")).filter(file => file.endsWith(".lua"))) {
  const source = path.relative(root, sourceFile).split(path.sep).join("/");
  if (!sources.has(source)) throw new Error(`src lua file is absent from image: ${source}`);
}

console.log(`validated ${luaFiles.length} lua files and ${sources.size} image mappings`);
