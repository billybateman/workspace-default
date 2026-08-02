import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { installTenderHeartTheme } from "./tenderheart/installTenderHeartTheme.js";
import "./styles.css";

installTenderHeartTheme();

function App() {
  const [health, setHealth] = useState(null);

  useEffect(() => {
    fetch("/api/health")
      .then((response) => response.json())
      .then(setHealth)
      .catch(() => setHealth({ ok: false }));
  }, []);

  return (
    <main>
      <p className="eyebrow">PROJECT TENDERHEART</p>
      <h1>Your workspace is ready.</h1>
      <p>React, Node, Git, and PostgreSQL are connected.</p>
      <pre>{JSON.stringify(health, null, 2)}</pre>
    </main>
  );
}

createRoot(document.getElementById("root")).render(<App />);
