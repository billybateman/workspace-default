import fs from "node:fs";

const source = fs.readFileSync("setup.sh", "utf8");

for (const forbidden of [
  'WORKSPACE_ROOT/.git',
  "requires TenderHeart to clone the workspace repository first",
]) {
  if (source.includes(forbidden)) {
    throw new Error(`Detached setup blocker remains: ${forbidden}`);
  }
}

for (const required of [
  "install_postgresql",
  "ensure_role_and_database",
  "write_environment",
  "install_dependencies",
  "run_project_setup",
]) {
  if (!source.includes(required)) {
    throw new Error(`Required setup behavior missing: ${required}`);
  }
}

console.log("Detached workspace-default setup verified");
