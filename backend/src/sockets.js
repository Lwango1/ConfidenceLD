function createSockets(io, db, auth, config) {
  const usersById = new Map();
  const userInCall = new Map();
  const activeCalls = new Map();

  function endCallForUser(uid, callId) {
    const call = activeCalls.get(callId);
    if (!call) return;
    for (const m of [call.caller, call.callee]) {
      if (userInCall.get(m) === callId) userInCall.delete(m);
    }
    activeCalls.delete(callId);
  }

  function findPeer(callId, uid) {
    const call = activeCalls.get(callId);
    if (!call) return null;
    if (call.caller === uid) return call.callee;
    if (call.callee === uid) return call.caller;
    return null;
  }

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

    function endCallForUser(uid, callId) {
      if (activeCalls.get(uid) === callId) activeCalls.delete(uid);
      if (activeCalls.get(callId) === uid) activeCalls.delete(callId);
    }

    socket.on("call:offer", async ({ toUserId, callId, isVideo }, callback) => {
      try {
        const targetOnline = io.sockets.adapter.rooms.has(`user:${toUserId}`)
          && io.sockets.adapter.rooms.get(`user:${toUserId}`).size > 0;
        if (!targetOnline) {
          return callback && callback({ ok: false, error: "offline" });
        }
        if (userInCall.get(toUserId) || userInCall.get(userId) || activeCalls.get(callId)) {
          return callback && callback({ ok: false, error: "busy" });
        }
        activeCalls.set(callId, { caller: userId, callee: toUserId });
        userInCall.set(userId, callId);
        userInCall.set(toUserId, callId);
        const caller = await db.getUserById(userId);
        io.to(`user:${toUserId}`).emit("call:incoming", {
          callId,
          fromUserId: userId,
          isVideo,
          fromDisplayName: caller ? caller.displayName : "Utilisateur",
          fromAvatar: caller ? caller.avatar : null,
        });
        if (callback) callback({ ok: true });
      } catch (e) {
        if (callback) callback({ ok: false, error: e.message });
      }
    });

    socket.on("call:accept", ({ callId, toUserId }, callback) => {
      if (findPeer(callId, userId) !== toUserId) {
        return callback && callback({ ok: false, error: "Appel introuvable" });
      }
      io.to(`user:${toUserId}`).emit("call:accepted", { callId });
      if (callback) callback({ ok: true });
    });

    socket.on("call:reject", ({ callId, toUserId }, callback) => {
      io.to(`user:${toUserId}`).emit("call:rejected", { callId });
      endCallForUser(userId, callId);
      endCallForUser(toUserId, callId);
      if (callback) callback({ ok: true });
    });

    socket.on("call:signal", ({ callId, toUserId, signal }, callback) => {
      if (findPeer(callId, userId) !== toUserId) {
        return callback && callback({ ok: false, error: "Appel introuvable" });
      }
      io.to(`user:${toUserId}`).emit("call:signal", { callId, fromUserId: userId, signal });
      if (callback) callback({ ok: true });
    });

    socket.on("call:end", ({ callId, toUserId }, callback) => {
      io.to(`user:${toUserId}`).emit("call:ended", { callId });
      endCallForUser(userId, callId);
      endCallForUser(toUserId, callId);
      if (callback) callback({ ok: true });
    });

    socket.on("call:busy", ({ callId, toUserId }, callback) => {
      io.to(`user:${toUserId}`).emit("call:busy", { callId });
      endCallForUser(userId, callId);
      endCallForUser(toUserId, callId);
      if (callback) callback({ ok: true });
    });

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
      const callId = userInCall.get(userId);
      if (callId) {
        const peer = findPeer(callId, userId);
        if (peer) io.to(`user:${peer}`).emit("call:ended", { callId });
        endCallForUser(userId, callId);
      }
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