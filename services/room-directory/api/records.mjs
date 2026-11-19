import {BlobPreconditionFailedError, get, head, put} from "@vercel/blob";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {routeSnapshot} from "../src/score-snapshot.js";

const schema = readFileSync(join(process.cwd(), "schema.sql"), "utf8");
const pathname = "arcade/records-v1.sqlite";
const store = {
  async read() {
    const blob = await get(pathname, {access: "private", useCache: false});
    if (!blob) return null;
    return {bytes: Buffer.from(await new Response(blob.stream).arrayBuffer()), etag: blob.blob.etag};
  },
  async save(bytes, etag) {
    try {
      await put(pathname, bytes, {
        access: "private", addRandomSuffix: false, allowOverwrite: Boolean(etag),
        ...(etag ? {ifMatch: etag} : {}), contentType: "application/octet-stream"
      });
      return true;
    } catch (error) {
      if (error instanceof BlobPreconditionFailedError) return false;
      // Two first-time players may both have seen an empty store.
      if (!etag && await head(pathname).catch(() => null)) return false;
      throw error;
    }
  }
};

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
    const makeRequest = () => new Request(url, {
      method: req.method,
      headers: {"Authorization": req.headers.authorization || "", "CF-Connecting-IP": (req.headers["x-vercel-forwarded-for"] || req.socket.remoteAddress || "local").split(",")[0].trim()},
      ...(hasBody ? {body} : {})
    });
    const response = await routeSnapshot(makeRequest, parts, schema, store);
    return res.status(response.status).json(await response.json());
  } catch (error) {
    console.error("Arcade record storage error", error.name, error.code || "");
    return res.status(503).json({error: "score_service_unavailable"});
  }
}
