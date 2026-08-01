import fs from "node:fs/promises";
import path from "node:path";
import { pool } from "../src/db.js";

const directory = path.resolve("seeders");
const files = (await fs.readdir(directory))
  .filter((name) => name.endsWith(".sql"))
  .sort();

for (const file of files) {
  await pool.query(await fs.readFile(path.join(directory, file), "utf8"));
  console.log("seeded", file);
}

await pool.end();
