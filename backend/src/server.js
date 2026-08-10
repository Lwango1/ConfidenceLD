require("dotenv").config();
const express = require("express");
const http = require("http");
const cors = require("cors");
const path = require("path");
const fs = require("fs");
const multer = require("multer");
const { Server } = require("socket.io");

const config = {
  port: process.env.PORT || 3000,
  uploadDir: path.join(__dirname, "..", "uploads"),
};

if (!fs.existsSync(config.uploadDir)) fs.mkdirSync(config.uploadDir, { recursive: true });

const db = require("./data");
const auth = require("./auth");
const createSockets = require("./sockets");

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin: "*", methods: ["GET", "POST"] },
  maxHttpBufferSize: 10 * 1024 * 1024,
});

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use("/uploads", express.static(config.uploadDir));

app.get("/health", (req, res) => res.json({ ok: true }));

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, config.uploadDir),
  filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});
const upload = multer({ storage });

app.post("/api/register", async (req, res) => {
  try {
    const { username, password, displayName, phone } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: "username et password requis" });
    }
    if (!phone) {
      return res
        .status(400)
        .json({ error: "Le numéro de téléphone est requis (comme WhatsApp)" });
    }
    const user = await db.createUser(username, password, displayName || username, phone);
    const token = auth.sign({ id: user.id, username: user.username });
    res.json({
      user,
      token,
    });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.post("/api/contacts/match", auth.middleware, async (req, res) => {
  try {
    const { phones } = req.body;
    if (!Array.isArray(phones)) {
      return res.status(400).json({ error: "Liste de numéros attendue" });
    }
    const matches = await db.matchContacts(phones);
    res.json({ matches });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.post("/api/login", async (req, res) => {
  const { username, password } = req.body;
  const user = await db.verifyUser(username, password);
  if (!user) return res.status(401).json({ error: "Identifiants invalides" });
  const token = auth.sign({ id: user.id, username: user.username });
  res.json({
    user,
    token,
  });
});

app.post(
  "/api/avatar",
  auth.middleware,
  upload.single("avatar"),
  async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ error: "Image manquante" });
      const avatarPath = `/uploads/${req.file.filename}`;
      await db.setAvatar(req.user.id, avatarPath);
      res.json({ avatar: avatarPath });
    } catch (e) {
      res.status(400).json({ error: e.message });
    }
  }
);

let versionCache = null;
let versionCacheTime = 0;
const GITHUB_REPO = "Lwango1/ConfidenceLD";

app.get("/api/version", async (req, res) => {
  try {
    if (versionCache && Date.now() - versionCacheTime < 5 * 60 * 1000) {
      return res.json(versionCache);
    }
    const gh = await fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!gh.ok) throw new Error("Aucune release GitHub");
    const release = await gh.json();
    const apkAsset = (release.assets || []).find((a) => a.name.endsWith(".apk"));
    versionCache = {
      version: release.tag_name,
      apkUrl: apkAsset ? apkAsset.browser_download_url : null,
      releaseNotes: release.body || "",
      publishedAt: release.published_at || null,
    };
    versionCacheTime = Date.now();
    res.json(versionCache);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get("/api/users", auth.middleware, async (req, res) => {
  const all = await db.getUsers();
  const users = all
    .filter((u) => u.id !== req.user.id)
    .map(({ id, username, displayName, avatar }) => ({ id, username, displayName, avatar }));
  res.json(users);
});

app.post(
  "/api/upload",
  auth.middleware,
  upload.single("file"),
  (req, res) => {
    if (!req.file) return res.status(400).json({ error: "Fichier manquant" });
    const media = db.createMedia(req.file.filename, req.file.mimetype, req.user.id);
    res.json({
      mediaId: media.id,
      url: `/uploads/${media.filename}`,
      mimeType: media.mimetype,
    });
  }
);

app.post("/api/groups", auth.middleware, async (req, res) => {
  try {
    const { name, memberIds } = req.body;
    if (!name) return res.status(400).json({ error: "Nom du groupe requis" });
    if (!Array.isArray(memberIds) || memberIds.length === 0) {
      return res.status(400).json({ error: "Au moins un membre requis" });
    }
    const group = await db.createGroup(name, req.user.id, memberIds);
    res.json({ group });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.get("/api/conversations", auth.middleware, async (req, res) => {
  try {
    const users = {};
    const all = await db.getUsers();
    for (const u of all) users[u.id] = u;
    const conversations = await db.getConversationsForUser(req.user.id, users);
    res.json({ conversations });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.get("/api/messages/:conversationId", auth.middleware, async (req, res) => {
  try {
    const members = await db.getGroupMembers(Number(req.params.conversationId));
    if (!members.some((m) => m.id === req.user.id)) {
      return res.status(403).json({ error: "Accès refusé" });
    }
    const messages = await db.getMessages(Number(req.params.conversationId), req.user.id);
    const full = [];
    for (const m of messages) {
      let mediaUrl = null;
      if (m.media_id && !m.view_once) {
        const media = await db.getMedia(m.media_id);
        if (media) mediaUrl = `/uploads/${media.filename}`;
      }
      full.push({
        id: m.id,
        conversationId: m.conversation_id,
        senderId: m.sender_id,
        type: m.type,
        content: m.content,
        mediaId: m.media_id,
        mediaUrl,
        viewOnce: m.view_once,
        status: m.status,
        createdAt: m.created_at,
      });
    }
    res.json({ messages: full });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.post("/api/conversations/:id/read", auth.middleware, async (req, res) => {
  try {
    await db.markAllRead(Number(req.params.id), req.user.id);
    res.json({ ok: true });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.post("/api/conversations/:id/favorite", auth.middleware, async (req, res) => {
  try {
    const { isFavorite } = req.body;
    await db.setFavorite(Number(req.params.id), req.user.id, isFavorite);
    res.json({ ok: true });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.get("/api/groups/:id/members", auth.middleware, async (req, res) => {
  try {
    const members = await db.getGroupMembers(Number(req.params.id));
    res.json({ members });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

app.delete("/api/media/:id", auth.middleware, (req, res) => {
  const media = db.getMedia(req.params.id);
  if (!media) return res.status(404).json({ error: "Média introuvable" });
  const filePath = path.join(config.uploadDir, media.filename);
  if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
  db.deleteMedia(req.params.id);
  res.json({ ok: true });
});

createSockets(io, db, auth, config);

server.listen(config.port, () => {
  console.log(`ConfidenceLD backend démarré sur http://localhost:${config.port}`);
});