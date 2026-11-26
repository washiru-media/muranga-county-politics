import { createClient } from "@supabase/supabase-js";
import { createHmac } from "node:crypto";

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false, autoRefreshToken: false } }
);

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY || !process.env.IP_HASH_SECRET) {
    return res.status(500).json({ error: "Server is not fully configured." });
  }

  const { categoryId, aspirantId } = req.body || {};
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuid.test(categoryId || "") || !uuid.test(aspirantId || "")) {
    return res.status(400).json({ error: "Invalid category or aspirant." });
  }

  // Vercel supplies x-forwarded-for. Use the first address and store only its HMAC.
  const forwarded = req.headers["x-forwarded-for"];
  const ip = (Array.isArray(forwarded) ? forwarded[0] : (forwarded || "")).split(",")[0].trim();
  if (!ip) return res.status(400).json({ error: "Could not identify the network address." });
  const ipHash = createHmac("sha256", process.env.IP_HASH_SECRET).update(ip).digest("hex");

  const { error } = await supabase.rpc("cast_poll_vote", {
    p_category_id: categoryId,
    p_aspirant_id: aspirantId,
    p_ip_hash: ipHash
  });

  if (error) {
    const duplicate = /already been submitted|duplicate key/i.test(error.message || "");
    return res.status(duplicate ? 409 : 400).json({
      error: duplicate ? "A vote has already been submitted from this IP address for this category." : (error.message || "Vote rejected.")
    });
  }
  return res.status(200).json({ ok: true });
}
