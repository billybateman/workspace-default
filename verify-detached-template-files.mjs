import fs from "node:fs";

const source = fs.readFileSync("setup.sh", "utf8");

if (source.includes('WORKSPACE_ROOT/.git')) {
  throw new Error("setup.sh still requires Git metadata");
}

for (const token of [
  "install_postgresql",
  "ensure_role_and_database",
  "write_environment",
  "run_project_setup",
]) {
  if (!source.includes(token)) {
    throw new Error(`Required setup behavior missing: ${token}`);
  }
}

console.log("Detached workspace setup verified");
