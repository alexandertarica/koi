const PREFIX = "koi-demo:";

async function deleteKoiDemoKeys(redis) {
  let cursor = "0";
  let removed = 0;

  do {
    const [nextCursor, scannedKeys] = await redis.scan(cursor, { match: `${PREFIX}*`, count: 500 });
    const safeKeys = scannedKeys.filter((key) => typeof key === "string" && key.startsWith(PREFIX));
    for (let start = 0; start < safeKeys.length; start += 500) {
      removed += await redis.del(...safeKeys.slice(start, start + 500));
    }
    cursor = String(nextCursor);
  } while (cursor !== "0");

  return removed;
}

module.exports = { deleteKoiDemoKeys, PREFIX };
