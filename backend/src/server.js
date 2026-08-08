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
    const { username, password, displayName } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: "username et password requis" });
    }
    const user = await db.createUser(username, password, displayName || username);
    const token = auth.sign({ id: user.id, username: user.username });
    res.json({
      user,
      token,
    });
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

app.get("/api/users", auth.middleware, (req, res) => {
  const users = db
    .getUsers()
    .filter((u) => u.id !== req.user.id)
    .map(({ id, username, displayName }) => ({ id, username, displayName }));
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