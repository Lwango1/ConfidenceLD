function createSockets(io, db, auth, config) {
  const usersById = new Map();

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error("Token manquant"));
    try {
      socket.user = auth.verify(token);
      next();
    } catch (e) {
      next(new Error("Token invalide"));
    }
  });

  io.on("connection", (socket) => {
    const userId = socket.user.id;
    usersById.set(userId, socket.user);
    socket.join(`user:${userId}`);
    console.log(`Connecté : ${socket.user.username} (socket ${socket.id})`);

    socket.on("conversations:list", async (callback) => {
      try {
        const convos = await socketGetConversations(userId);
        callback({ ok: true, conversations: convos });
      } catch (e) {
        callback({ ok: false, error: e.message });
      }
    });

    socket.on(
      "message:send",
      async ({ toUserId, type, content, mediaId, viewOnce }, callback) => {
        try {
          if (!toUserId) return callback && callback({ ok: false, error: "Destinataire manquant" });
          let conv = await db.getConversationId(userId, toUserId);
          if (!conv) conv = await db.createConversation(userId, toUserId);
          const msg = await db.addMessage({
            conversationId: conv.id,
            senderId: userId,
            type,
            content: content || null,
            mediaId: mediaId || null,
            viewOnce: !!viewOnce,
          });
          const payload = await serializeMessage(msg, userId);
          io.to(`user:${toUserId}`).emit("message:new", payload);
          io.to(`user:${userId}`).emit("message:new", payload);
          if (callback) callback({ ok: true, message: payload });
        } catch (e) {
          if (callback) callback({ ok: false, error: e.message });
        }
      }
    );

    socket.on("message:read", async ({ messageId }, callback) => {
      try {
        await db.markMessageRead(messageId);
        io.to(`user:${userId}`).emit("message:read", { id: messageId });
        if (callback) callback({ ok: true });
      } catch (e) {
        if (callback) callback({ ok: false });
      }
    });

    socket.on("media:viewed", async ({ mediaId, ownerId }, callback) => {
      try {
        const media = await db.getMedia(mediaId);
        if (!media) return callback && callback({ ok: false });
        const filePath = require("path").join(config.uploadDir, media.filename);
        const fs = require("fs");
        if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
        await db.deleteMedia(mediaId);
        io.to(`user:${userId}`).emit("media:destroyed", { mediaId });
        if (callback) callback({ ok: true });
      } catch (e) {
        if (callback) callback({ ok: false, error: e.message });
      }
    });

    socket.on("disconnect", () => {
      usersById.delete(userId);
    });
  });

  async function serializeMessage(msg, viewerId) {
    let mediaUrl = null;
    let viewOnce = !!msg.view_once;
    if (msg.media_id) {
      const media = await db.getMedia(msg.media_id);
      if (media && !viewOnce) mediaUrl = `/uploads/${media.filename}`;
    }
    return {
      id: msg.id,
      conversationId: msg.conversation_id,
      senderId: msg.sender_id,
      type: msg.type,
      content: msg.content,
      mediaId: msg.media_id,
      mediaUrl,
      viewOnce,
      status: msg.status,
      createdAt: msg.created_at,
    };
  }
}

async function socketGetConversations(userId) {
  const users = await getUsersMap();
  return db.getConversationsForUser(userId, users);
}

async function getUsersMap() {
  const users = await require("./data").getUsers();
  const map = {};
  for (const u of users) map[u.id] = u;
  return map;
}

module.exports = createSockets;