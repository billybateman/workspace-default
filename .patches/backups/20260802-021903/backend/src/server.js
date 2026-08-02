import "dotenv/config";
import express from "express";
import { pool } from "./db.js";

const app = express();
app.use(express.json());

app.get("/api/health", async (_request, response) => {
  try {
    const result = await pool.query("select now() as now");
    response.json({
      ok: true,
      database: true,
      now: result.rows[0].now
    });
  } catch (error) {
    response.status(503).json({
      ok: false,
      database: false,
      error: error.message
    });
  }
});

app.get("/api/items", async (_request, response) => {
  const result = await pool.query(
    "select * from workspace_items order by created_at"
  );
  response.json(result.rows);
});

const port = Number(process.env.BACKEND_PORT || 4001);
app.listen(port, "0.0.0.0", () => {
  console.log(`backend listening on ${port}`);
});
