import fs from "node:fs";
import path from "node:path";

const target = path.resolve(process.cwd(), "setup.sh");
let source = fs.readFileSync(target, "utf8");

const exact = `  [ -d "$WORKSPACE_ROOT/.git" ] ||
    die "setup.sh requires TenderHeart to clone the workspace repository first"

`;

if (source.includes(exact)) {
  source = source.replace(exact, "");
} else {
  source = source.replace(
    /\s*\[\s+-d\s+"\$WORKSPACE_ROOT\/\.git"\s+\]\s*\|\|\s*\n\s*die\s+"setup\.sh requires TenderHeart to clone the workspace repository first"\s*\n?/,
    "\n",
  );
}

if (source.includes("requires TenderHeart to clone the workspace repository first")) {
  throw new Error("The legacy .git requirement could not be removed");
}

fs.writeFileSync(target, source);
console.log("workspace-default/setup.sh now supports detached template files");
