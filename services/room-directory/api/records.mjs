import {getScoreFirestore} from "../src/firestore-connection.js";
import {firebaseScoresRoute} from "../src/firebase-scores.js";

export default async function handler(req, res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Cache-Control", "no-store");
  if (req.method === "OPTIONS") return res.status(204).end();
  if (!["GET", "POST"].includes(req.method)) return res.status(405).end();
  const url = new URL(req.url, "https://energygame-minigames-demo.vercel.app");
  const path = url.searchParams.get("gamePath") ?? url.pathname.replace(/^\/api\/scores\//, "");
  const parts = ["scores", ...path.split("/").filter(Boolean)];
  try {
    const hasBody = req.method === "POST";
    const body = hasBody && (typeof req.body === "string" || Buffer.isBuffer(req.body) ? req.body : JSON.stringify(req.body ?? {}));
    if (hasBody && Buffer.byteLength(body) > 1024) return res.status(413).json({error: "too_large"});
    const request = new Request(url, {
      method: req.method,
      headers: {"Authorization": req.headers.authorization || "", "CF-Connecting-IP": (req.headers["x-vercel-forwarded-for"] || req.socket.remoteAddress || "local").split(",")[0].trim()},
      ...(hasBody ? {body} : {})
    });
    const response = await firebaseScoresRoute(request, getScoreFirestore(), parts);
    return res.status(response.status).json(await response.json());
  } catch (error) {
    console.error("Arcade record storage error", error.name, error.code || "");
    return res.status(503).json({error: "score_service_unavailable"});
  }
}
