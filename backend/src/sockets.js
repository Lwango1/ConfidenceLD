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
      async ({ conversationId, toUserId, type, content, mediaId, viewOnce }, callback) => {
        try {
          let conv;
          if (conversationId) {
            conv = await getMemberConversation(conversationId, userId);
          } else if (toUserId) {
            conv = await db.getOrCreateDirectConversation(userId, toUserId);
          } else {
            return callback && callback({ ok: false, error: "Conversation ou destinataire manquant" });
          }
          const msg = await db.addMessage({
            conversationId: conv.id,
            senderId: userId,
            type,
            content: content || null,
            mediaId: mediaId || null,
            viewOnce: !!viewOnce,
          });
          const payload = await serializeMessage(msg, userId);
          await emitToConversation(conv.id, "message:new", payload, userId);
          await refreshUnread(conv.id, userId);
          if (callback) callback({ ok: true, message: payload });
        } catch (e) {
          if (callback) callback({ ok: false, error: e.message });
        }
      }
    );

    socket.on("conversation:read", async ({ conversationId }, callback) => {
      try {
        await db.markAllRead(conversationId, userId);
        io.to(`user:${userId}`).emit("conversation:read", { conversationId, userId });
        if (callback) callback({ ok: true });
      } catch (e) {
        if (callback) callback({ ok: false });
      }
    });

    socket.on("conversation:favorite", async ({ conversationId, isFavorite }, callback) => {
      try {
        await db.setFavorite(conversationId, userId, isFavorite);
        io.to(`user:${userId}`).emit("conversation:favorite", { conversationId, isFavorite });
        if (callback) callback({ ok: true });
      } catch (e) {
        if (callback) callback({ ok: false });
      }
    });

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

  async function getMemberConversation(conversationId, userId) {
    const members = await db.getGroupMembers(conversationId);
    if (!members.some((m) => m.id === userId)) {
      const err = new Error("Vous ne faites pas partie de cette conversation");
      throw err;
    }
    return { id: conversationId };
  }

  async function emitToConversation(conversationId, event, payload, exceptUserId) {
    const members = await db.getGroupMembers(conversationId);
    const memberIds = members.map((m) => m.id);
    for (const mid of memberIds) {
      if (mid !== exceptUserId) io.to(`user:${mid}`).emit(event, payload);
    }
    io.to(`user:${exceptUserId}`).emit(event, payload);
  }

  async function refreshUnread(conversationId, senderId) {
    const members = await db.getGroupMembers(conversationId);
    for (const m of members) {
      if (m.id === senderId) continue;
      const count = await db.getUnreadCount(conversationId, m.id);
      io.to(`user:${m.id}`).emit("conversation:unread", { conversationId, userId: m.id, count });
    }
  }

  async function serializeMessage(msg, viewerId) {
    let mediaUrl = null;
    let viewOnce = !!msg.view_once;
    if (msg.media_id) {
      const media = await db.getMedia(msg.media_id);
      if (media) mediaUrl = `/uploads/${media.filename}`;
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
async function socketGetConversations(userId) {
    const users = await getUsersMap();
    return db.getConversationsForUser(userId, users);
  }

  async function getUsersMap() {
    const users = await db.getUsers();
    const map = {};
    for (const u of users) map[u.id] = u;
    return map;
  }
}

module.exports = createSockets;