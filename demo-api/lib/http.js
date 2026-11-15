const ALLOWED_ORIGIN = "https://alexandertarica.github.io";

function applyCors(req, res, methods = "POST, OPTIONS") {
  const origin = req.headers.origin;
  if (origin && origin !== ALLOWED_ORIGIN) return false;
  if (origin === ALLOWED_ORIGIN) {
    res.setHeader("Access-Control-Allow-Origin", ALLOWED_ORIGIN);
    res.setHeader("Vary", "Origin");
    res.setHeader("Access-Control-Allow-Methods", methods);
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    res.setHeader("Access-Control-Max-Age", "86400");
  }
  return true;
}

function respond(res, status, body) {
  return res.status(status).json(body);
}

function validRespondentId(value) {
  return typeof value === "string" && /^[a-f0-9-]{36}$/i.test(value);
}

module.exports = { ALLOWED_ORIGIN, applyCors, respond, validRespondentId };
