import {getScoreFirestore} from "../src/firestore-connection.js";
import {firebaseRoomsRoute} from "../src/firebase-rooms.js";

export default async function handler(req, res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  res.setHeader("Cache-Control", "no-store");
  if (req.method === "OPTIONS") return res.status(204).end();
  if (!["GET", "POST", "DELETE"].includes(req.method)) return res.status(405).end();
  const url = new URL(req.url, "https://energygame-minigames-demo.vercel.app");
  const path = url.pathname === "/api/rooms" ? (url.searchParams.get("roomPath") || "") :
    url.pathname.replace(/^\/api\/webrtc\/rooms\/?/, "");
  const parts = ["webrtc", "rooms", ...path.split("/").filter(Boolean)];
  try {
    let body;
    if (req.method === "POST") {
      body = Buffer.isBuffer(req.body) || typeof req.body === "string" ? req.body : JSON.stringify(req.body ?? {});
      if (Buffer.byteLength(body) > 72 * 1024) return res.status(413).json({error: "요청 데이터가 너무 큽니다."});
    }
    const request = new Request(url, {method: req.method, body, headers: {Authorization: req.headers.authorization || ""}});
    const response = await firebaseRoomsRoute(request, getScoreFirestore(), parts, process.env);
    return res.status(response.status).json(await response.json());
  } catch (failure) {
    console.error("Room signaling storage error", failure.name, failure.code || "");
    return res.status(503).json({error: "방 코드 연결 서버에 잠시 연결할 수 없습니다. 다시 시도해 주세요."});
  }
}
