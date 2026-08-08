const crypto = require("crypto");
const jwt = require("jsonwebtoken");

const SECRET = process.env.JWT_SECRET || "confidentiald_dev_secret_2026";

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto.pbkdf2Sync(password, salt, 100000, 32, "sha512").toString("hex");
  return { salt, hash };
}

function verifyPassword(password, salt, hash) {
  const computed = crypto.pbkdf2Sync(password, salt, 100000, 32, "sha512").toString("hex");
  const a = Buffer.from(computed);
  const b = Buffer.from(hash);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

function sign(user) {
  return jwt.sign({ id: user.id, username: user.username }, SECRET, {
    expiresIn: "30d",
  });
}

function verify(token) {
  return jwt.verify(token, SECRET);
}

function middleware(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: "Non authentifié" });
  try {
    req.user = verify(token);
    next();
  } catch (e) {
    res.status(401).json({ error: "Token invalide ou expiré" });
  }
}

module.exports = { hashPassword, verifyPassword, sign, verify, middleware };