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
    phone TEXT,
    salt TEXT NOT NULL,
    hash TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
  )`);
  await query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT`);
  await query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar TEXT`);

  await query(`CREATE TABLE IF NOT EXISTS conversations (
    id SERIAL PRIMARY KEY,
    user1 INTEGER,
    user2 INTEGER,
    type TEXT NOT NULL DEFAULT 'direct',
    name TEXT,
    creator_id INTEGER,
    last_message_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
  )`);

  await query(`ALTER TABLE conversations ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'direct'`);
  await query(`ALTER TABLE conversations ADD COLUMN IF NOT EXISTS name TEXT`);
  await query(`ALTER TABLE conversations ADD COLUMN IF NOT EXISTS creator_id INTEGER`);
  await query(`ALTER TABLE conversations ALTER COLUMN user1 DROP NOT NULL`);
  await query(`ALTER TABLE conversations ALTER COLUMN user2 DROP NOT NULL`);

  await query(`CREATE TABLE IF NOT EXISTS conversation_members (
    conversation_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    is_favorite BOOLEAN NOT NULL DEFAULT false,
    last_read_at TIMESTAMPTZ DEFAULT now(),
    joined_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (conversation_id, user_id)
  )`);

  await query(`INSERT INTO conversation_members (conversation_id, user_id)
    SELECT id, user1 FROM conversations WHERE type = 'direct' AND user1 IS NOT NULL
    ON CONFLICT DO NOTHING`);
  await query(`INSERT INTO conversation_members (conversation_id, user_id)
    SELECT id, user2 FROM conversations WHERE type = 'direct' AND user2 IS NOT NULL
    ON CONFLICT DO NOTHING`);

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

function localDigits(phone) {
  let p = String(phone || "").replace(/[^\d]/g, "");
  if (p.startsWith("00")) p = p.slice(2);
  return p.startsWith("0") ? p.slice(1) : p;
}

async function normalizePhone(phone) {
  return localDigits(phone);
}

async function createUser(username, password, displayName, phone) {
  const { salt, hash } = auth.hashPassword(password);
  const cleanPhone = await normalizePhone(phone);
  try {
    const res = await query(
      "INSERT INTO users (username, display_name, salt, hash, phone) VALUES ($1, $2, $3, $4, $5) RETURNING id, username, display_name, phone",
      [username, displayName, salt, hash, cleanPhone]
    );
    const { id, username: storedUsername, display_name } = res.rows[0];
    return { id, username: storedUsername, displayName: display_name, phone: cleanPhone, avatar: null };
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
  return {
    id: user.id,
    username: user.username,
    displayName: user.display_name,
    phone: user.phone,
    avatar: user.avatar,
  };
}

async function getUsers() {
  const res = await query(
    'SELECT id, username, display_name as "displayName", phone, avatar FROM users'
  );
  return res.rows;
}

async function setAvatar(userId, avatarPath) {
  await query("UPDATE users SET avatar = $1 WHERE id = $2", [avatarPath, userId]);
}

async function getUserById(userId) {
  const res = await query(
    'SELECT id, username, display_name as "displayName", phone, avatar FROM users WHERE id = $1',
    [userId]
  );
  return res.rows[0] || null;
}

async function matchContacts(phoneNumbers) {
  const candidates = [];
  for (const p of phoneNumbers) {
    const l = await normalizePhone(p);
    if (l.length >= 6 && !candidates.includes(l)) candidates.push(l);
  }
  if (candidates.length === 0) return [];

  const res = await query(
    'SELECT id, username, display_name as "displayName", phone, avatar FROM users WHERE phone IS NOT NULL AND length(phone) > 0'
  );

  const matched = [];
  const used = new Array(candidates.length).fill(false);
  for (const row of res.rows) {
    const userLocal = await normalizePhone(row.phone);
    if (userLocal.length < 6) continue;
    for (let i = 0; i < candidates.length; i++) {
      if (used[i]) continue;
      const shorter = candidates[i].length <= userLocal.length ? candidates[i] : userLocal;
      const longer = candidates[i].length <= userLocal.length ? userLocal : candidates[i];
      if (shorter.length >= 6 && longer.endsWith(shorter)) {
        matched.push(row);
        used[i] = true;
        break;
      }
    }
  }
  return matched;
}

/* ============ CONVERSATIONS ============ */

async function getDirectConversation(userA, userB) {
  const res = await query(
    `SELECT c.* FROM conversations c
     JOIN conversation_members m1 ON m1.conversation_id = c.id AND m1.user_id = $1
     JOIN conversation_members m2 ON m2.conversation_id = c.id AND m2.user_id = $2
     WHERE c.type = 'direct'`,
    [userA, userB]
  );
  return res.rows[0] || null;
}

async function createDirectConversation(userA, userB) {
  const res = await query(
    "INSERT INTO conversations (type) VALUES ('direct') RETURNING *"
  );
  const convId = res.rows[0].id;
  await query(
    "INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)",
    [convId, userA, userB]
  );
  return res.rows[0];
}

async function getOrCreateDirectConversation(userA, userB) {
  const existing = await getDirectConversation(userA, userB);
  if (existing) return existing;
  return createDirectConversation(userA, userB);
}

async function createGroup(name, creatorId, memberIds) {
  const res = await query(
    "INSERT INTO conversations (type, name, creator_id) VALUES ('group', $1, $2) RETURNING *",
    [name, creatorId]
  );
  const convId = res.rows[0].id;
  const allMembers = [...new Set([creatorId, ...memberIds])];
  for (const uid of allMembers) {
    await query(
      "INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2)",
      [convId, uid]
    );
  }
  return res.rows[0];
}

async function addGroupMember(conversationId, userId) {
  await query(
    "INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
    [conversationId, userId]
  );
}

async function getGroupMembers(conversationId) {
  const res = await query(
    `SELECT m.user_id as id, m.joined_at
     FROM conversation_members m
     WHERE m.conversation_id = $1`,
    [conversationId]
  );
  return res.rows;
}

async function setFavorite(conversationId, userId, isFavorite) {
  await query(
    "UPDATE conversation_members SET is_favorite = $1 WHERE conversation_id = $2 AND user_id = $3",
    [!!isFavorite, conversationId, userId]
  );
}

async function getConversationsForUser(userId, usersById) {
  const res = await query(
    `SELECT c.id, c.type, c.name, c.last_message_at,
            m.is_favorite,
            m.last_read_at
     FROM conversations c
     JOIN conversation_members m ON m.conversation_id = c.id
     WHERE m.user_id = $1
     ORDER BY c.last_message_at DESC NULLS LAST`,
    [userId]
  );
  const conversations = [];
  for (const c of res.rows) {
    let displayName = null;
    let avatar = null;
    let otherUserId = null;
    let memberCount = null;
    if (c.type === "direct") {
      const members = await getGroupMembers(c.id);
      const other = members.find((m) => m.id !== userId);
      if (other) {
        otherUserId = other.id;
        const u = usersById[other.id];
        displayName = u ? u.displayName : "Utilisateur";
        avatar = u ? u.avatar : null;
      }
    } else {
      const members = await getGroupMembers(c.id);
      memberCount = members.length;
      displayName = c.name || "Groupe";
    }
    const unread = await getUnreadCount(c.id, userId);
    const lastMessage = await getLastMessage(c.id);
    conversations.push({
      id: c.id,
      type: c.type,
      userId: otherUserId,
      displayName,
      avatar,
      memberCount,
      isFavorite: c.is_favorite,
      unreadCount: unread,
      lastMessage: lastMessage
        ? { senderId: lastMessage.sender_id, content: lastMessage.content, type: lastMessage.type }
        : null,
      lastMessageAt: c.last_message_at,
    });
  }
  return conversations;
}

async function getLastMessage(conversationId) {
  const res = await query(
    "SELECT sender_id, content, type FROM messages WHERE conversation_id = $1 ORDER BY created_at DESC, id DESC LIMIT 1",
    [conversationId]
  );
  return res.rows[0] || null;
}

async function getUnreadCount(conversationId, userId) {
  const res = await query(
    `SELECT COUNT(*)::int as cnt FROM messages
     WHERE conversation_id = $1 AND sender_id <> $2 AND created_at > (
       SELECT COALESCE(last_read_at, '1970-01-01') FROM conversation_members
       WHERE conversation_id = $1 AND user_id = $2
     )`,
    [conversationId, userId]
  );
  return res.rows[0].cnt;
}

async function getMessages(conversationId, userId, offset = 0) {
  const res = await query(
    "SELECT * FROM messages WHERE conversation_id = $1 ORDER BY created_at DESC, id DESC LIMIT 100 OFFSET $2",
    [conversationId, offset]
  );
  const rows = res.rows.reverse();
  if (userId) await markAllRead(conversationId, userId);
  return rows;
}

async function markAllRead(conversationId, userId) {
  await query(
    "UPDATE conversation_members SET last_read_at = now() WHERE conversation_id = $1 AND user_id = $2",
    [conversationId, userId]
  );
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
  matchContacts,
  setAvatar,
  getUserById,
  getOrCreateDirectConversation,
  createGroup,
  addGroupMember,
  getGroupMembers,
  setFavorite,
  getConversationsForUser,
  getMessages,
  addMessage,
  markAllRead,
  getUnreadCount,
  markMessageRead,
  createMedia,
  getMedia,
  deleteMedia,
};