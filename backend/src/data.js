const { Pool } = require("pg");
const auth = require("./auth");

const connectionString =
  process.env.DATABASE_URL ||
  process.env.PG_CONNECTION_STRING ||
  "postgresql://postgres:password@localhost:5432/confidenceld";

const pool = new Pool({
  connectionString,
  ssl:
    process.env.DATABASE_SSL === "false"
      ? false
      : { rejectUnauthorized: false },
});

async function query(text, params = []) {
  const res = await pool.query(text, params);
  return res;
}

async function init() {
  await query(`CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    salt TEXT NOT NULL,
    hash TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
  )`);

  await query(`CREATE TABLE IF NOT EXISTS conversations (
    id SERIAL PRIMARY KEY,
    user1 INTEGER NOT NULL,
    user2 INTEGER NOT NULL,
    last_message_at TIMESTAMPTZ,
    UNIQUE(user1, user2)
  )`);

  await query(`CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL,
    sender_id INTEGER NOT NULL,
    type TEXT NOT NULL DEFAULT 'text',
    content TEXT,
    media_id INTEGER,
    view_once BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL DEFAULT 'sent',
    created_at TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (conversation_id) REFERENCES conversations(id),
    FOREIGN KEY (sender_id) REFERENCES users(id)
  )`);

  await query(`CREATE TABLE IF NOT EXISTS media (
    id SERIAL PRIMARY KEY,
    filename TEXT NOT NULL,
    mimetype TEXT NOT NULL,
    owner_id INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (owner_id) REFERENCES users(id)
  )`);

  console.log("Base de données PostgreSQL initialisée");
}

async function createUser(username, password, displayName) {
  const { salt, hash } = auth.hashPassword(password);
  try {
    const res = await query(
      "INSERT INTO users (username, display_name, salt, hash) VALUES ($1, $2, $3, $4) RETURNING id, username, display_name",
      [username, displayName, salt, hash]
    );
    const { id, username: storedUsername, display_name } = res.rows[0];
    return { id, username: storedUsername, displayName: display_name };
  } catch (err) {
    if (err.code === "23505") throw new Error("Ce username est déjà utilisé");
    throw err;
  }
}

async function verifyUser(username, password) {
  const res = await query("SELECT * FROM users WHERE username = $1", [username]);
  const user = res.rows[0];
  if (!user) return null;
  if (!auth.verifyPassword(password, user.salt, user.hash)) return null;
  return { id: user.id, username: user.username, displayName: user.display_name };
}

async function getUsers() {
  const res = await query("SELECT id, username, display_name as \"displayName\" FROM users");
  return res.rows;
}

async function getConversationId(userA, userB) {
  const a = Math.min(userA, userB);
  const b = Math.max(userA, userB);
  const res = await query(
    "SELECT * FROM conversations WHERE user1 = $1 AND user2 = $2",
    [a, b]
  );
  return res.rows[0];
}

async function createConversation(userA, userB) {
  const a = Math.min(userA, userB);
  const b = Math.max(userA, userB);
  const res = await query(
    "INSERT INTO conversations (user1, user2) VALUES ($1, $2) ON CONFLICT (user1, user2) DO UPDATE SET user1 = EXCLUDED.user1 RETURNING *",
    [a, b]
  );
  return res.rows[0];
}

async function getConversationsForUser(userId, usersById) {
  const res = await query(
    "SELECT * FROM conversations WHERE user1 = $1 OR user2 = $2 ORDER BY last_message_at DESC",
    [userId, userId]
  );
  return res.rows
    .map((c) => {
      const otherId = c.user1 === userId ? c.user2 : c.user1;
      const other = usersById[otherId];
      return {
        id: c.id,
        userId: otherId,
        displayName: other ? other.displayName : "Utilisateur",
        lastMessageAt: c.last_message_at,
      };
    })
    .filter((c) => c.userId);
}

async function getMessages(conversationId) {
  const res = await query("SELECT * FROM messages WHERE conversation_id = $1 ORDER BY created_at, id", [
    conversationId,
  ]);
  return res.rows;
}

async function addMessage({ conversationId, senderId, type, content, mediaId, viewOnce }) {
  const res = await query(
    "INSERT INTO messages (conversation_id, sender_id, type, content, media_id, view_once, status) VALUES ($1, $2, $3, $4, $5, $6, 'sent') RETURNING *",
    [conversationId, senderId, type, content, mediaId, !!viewOnce]
  );
  await query("UPDATE conversations SET last_message_at = now() WHERE id = $1", [conversationId]);
  return res.rows[0];
}

async function markMessageRead(messageId) {
  await query("UPDATE messages SET status = 'read' WHERE id = $1", [messageId]);
}

async function createMedia(filename, mimetype, ownerId) {
  const res = await query(
    "INSERT INTO media (filename, mimetype, owner_id) VALUES ($1, $2, $3) RETURNING *",
    [filename, mimetype, ownerId]
  );
  return res.rows[0];
}

async function getMedia(id) {
  const res = await query("SELECT * FROM media WHERE id = $1", [id]);
  return res.rows[0];
}

async function deleteMedia(id) {
  await query("DELETE FROM media WHERE id = $1", [id]);
}

init().catch((err) => {
  console.error("Erreur d'initialisation de la base :", err.message);
  process.exit(1);
});

module.exports = {
  createUser,
  verifyUser,
  getUsers,
  getConversationId,
  createConversation,
  getConversationsForUser,
  getMessages,
  addMessage,
  markMessageRead,
  createMedia,
  getMedia,
  deleteMedia,
};