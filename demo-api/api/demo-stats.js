const { timingSafeEqual } = require("node:crypto");
const { createRedis } = require("../lib/store");

const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
const csvCell = (value) => `"${String(value ?? "").replace(/"/g, '""')}"`;

function requestKey(req) {
  const direct = req.query?.key;
  if (typeof direct === "string") return direct;
  try { return new URL(req.url, "https://koi-demo-api.vercel.app").searchParams.get("key") || ""; }
  catch { return ""; }
}

function keyMatches(provided, expected) {
  const left = Buffer.from(provided);
  const right = Buffer.from(expected);
  return left.length === right.length && timingSafeEqual(left, right);
}

function sendHtml(res, status, content) {
  res.statusCode = status;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  return res.end(content);
}

function sendCsv(res, records) {
  const rows = [["firstName", "startedAt", "finishedAt", "wouldUse", "wouldPay", "dailyUse", "email", "respondentId"]];
  for (const item of records) rows.push([item.firstName, item.startedAt, item.finishedAt, item.answers?.wouldUse, item.answers?.wouldPay, item.answers?.dailyUse, item.email, item.respondentId]);
  res.statusCode = 200;
  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", 'attachment; filename="koi-demo-feedback.csv"');
  res.setHeader("Cache-Control", "no-store");
  return res.end(rows.map((row) => row.map(csvCell).join(",")).join("\r\n"));
}

module.exports = async function handler(req, res) {
  if (req.method !== "GET") return sendHtml(res, 405, "<!doctype html><title>Method not allowed</title><p>Use GET.</p>");
  const expected = process.env.STATS_KEY;
  const provided = requestKey(req);
  if (!expected || !provided || !keyMatches(provided, expected)) return sendHtml(res, 404, "<!doctype html><title>Not found</title><p>This page is not available.</p>");

  try {
    const redis = createRedis();
    if (!redis) return sendHtml(res, 503, "<!doctype html><title>Storage not connected</title><p>Connect the demo data store to view stats.</p>");
    const respondentIds = (await redis.smembers("koi-demo:feedback-index")).slice(-10000);
    const [rawRecords, rawEvents] = await Promise.all([
      respondentIds.length ? redis.mget(...respondentIds.map((id) => `koi-demo:feedback:${id}`)) : [],
      redis.lrange("koi-demo:events", -50000, -1),
    ]);
    const records = rawRecords.map((value) => typeof value === "string" ? JSON.parse(value) : value).filter((value) => value && typeof value === "object").sort((left, right) => Date.parse(right.finishedAt) - Date.parse(left.finishedAt));
    if (req.query?.format === "csv" || new URL(req.url, "https://koi-demo-api.vercel.app").searchParams.get("format") === "csv") return sendCsv(res, records);
    const events = rawEvents.map((value) => { try { return typeof value === "string" ? JSON.parse(value) : value; } catch { return null; } }).filter(Boolean);
    const counts = (field) => Object.fromEntries(["Yes", "Maybe", "No"].map((answer) => [answer, records.filter((item) => item.answers?.[field] === answer).length]));
    const useCounts = counts("wouldUse");
    const payCounts = counts("wouldPay");
    const eventCounts = Object.fromEntries([...new Set(events.map((item) => item.event))].sort().map((event) => [event, events.filter((item) => item.event === event).length]));
    const formatTime = (value) => {
      const date = new Date(value);
      return Number.isNaN(date.getTime()) ? "" : date.toLocaleString("en-US", { dateStyle: "medium", timeStyle: "short", timeZone: "UTC" }) + " UTC";
    };
    const query = encodeURIComponent(provided);
    const rows = records.map((item) => `<tr><td>${escapeHtml(item.firstName)}</td><td>${escapeHtml(formatTime(item.finishedAt || item.submittedAt))}</td><td>Use: ${escapeHtml(item.answers?.wouldUse)}<br>Pay: ${escapeHtml(item.answers?.wouldPay)}</td><td>${escapeHtml(item.answers?.dailyUse)}</td></tr>`).join("");
    const emails = records.filter((item) => typeof item.email === "string" && item.email).map((item) => `<li>${escapeHtml(item.firstName)} · <a href="mailto:${escapeHtml(item.email)}">${escapeHtml(item.email)}</a></li>`).join("") || "<li>No email addresses shared.</li>";
    const eventRows = Object.entries(eventCounts).map(([event, count]) => `<tr><td>${escapeHtml(event)}</td><td>${count}</td></tr>`).join("") || '<tr><td colspan="2">No events recorded.</td></tr>';
    const html = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Koi demo feedback</title><style>body{margin:0;background:#e6e8e8;color:#213352;font:14px/1.55 system-ui,sans-serif}.wrap{max-width:1100px;margin:auto;padding:32px 22px}h1,h2{font-weight:500}h1{font-size:28px}h2{margin-top:36px;font-size:19px}.cards{display:flex;gap:12px;flex-wrap:wrap}.card{min-width:180px;padding:16px;border:1px solid #c4cbd3;border-radius:15px;background:#fff8}.card strong{display:block;font-size:22px}table{width:100%;border-collapse:collapse;background:#fff9}th,td{text-align:left;vertical-align:top;padding:10px;border-bottom:1px solid #cbd2d9}th{font-size:11px;text-transform:uppercase;letter-spacing:.1em}a{color:#213352}.top{display:flex;justify-content:space-between;align-items:center}.download{padding:10px 14px;border:1px solid #8994a3;border-radius:999px;text-decoration:none}</style><main class="wrap"><div class="top"><div><p>KOI · JUDGE KIOSK</p><h1>Demo feedback</h1></div><a class="download" href="?key=${query}&amp;format=csv">Download CSV</a></div><section class="cards"><div class="card"><span>Total respondents</span><strong>${records.length}</strong></div><div class="card"><span>Would use · Yes / Maybe / No</span><strong>${useCounts.Yes} / ${useCounts.Maybe} / ${useCounts.No}</strong></div><div class="card"><span>Would pay · Yes / Maybe / No</span><strong>${payCounts.Yes} / ${payCounts.Maybe} / ${payCounts.No}</strong></div></section><h2>Responses</h2><table><thead><tr><th>First name</th><th>Time</th><th>Answers</th><th>What would make Koi a daily habit?</th></tr></thead><tbody>${rows || "<tr><td colspan=\"4\">No responses yet.</td></tr>"}</tbody></table><h2>Emails shared separately</h2><ul>${emails}</ul><h2>Events by type</h2><table><thead><tr><th>Event</th><th>Count</th></tr></thead><tbody>${eventRows}</tbody></table></main></html>`;
    return sendHtml(res, 200, html);
  } catch {
    return sendHtml(res, 503, "<!doctype html><title>Stats unavailable</title><p>Could not read the demo data store.</p>");
  }
};
