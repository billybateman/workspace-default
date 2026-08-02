import fs from "node:fs";
import path from "node:path";

const target = path.resolve(process.cwd(), "setup.sh");
let source = fs.readFileSync(target, "utf8");

const oldCheck = `  [ -d "$WORKSPACE_ROOT/.git" ] ||
    die "setup.sh requires TenderHeart to clone the workspace repository first"

`;

if (source.includes(oldCheck)) {
  source = source.replace(oldCheck, "");
} else if (source.includes("requires TenderHeart to clone the workspace repository first")) {
  throw new Error("Could not safely remove setup.sh Git repository requirement");
}

fs.writeFileSync(target, source);
console.log("setup.sh no longer requires /home/user/.git");
