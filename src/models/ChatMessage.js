const { executeQuery } = require('../config/database');

class ChatMessage {
  constructor(data) {
    this.id = data.id;
    this.session_id = data.session_id;
    this.user_id = data.user_id;
    this.message_type = data.message_type; // 'user' or 'assistant'
    this.content = data.content;
    this.metadata = data.metadata ? JSON.parse(data.metadata) : null;
    this.created_at = data.created_at;
  }

  // Create a new message
  static async create(messageData) {
    const { session_id, user_id, message_type, content, metadata } = messageData;
    
    const query = `
      INSERT INTO chat_messages (session_id, user_id, message_type, content, metadata, created_at)
      VALUES (?, ?, ?, ?, ?, NOW())
    `;
    
    const metadataJson = metadata ? JSON.stringify(metadata) : null;
    
    const result = await executeQuery(query, [
      session_id, 
      user_id, 
      message_type, 
      content, 
      metadataJson
    ]);
    
    return await this.findById(result.insertId);
  }

  // Create multiple messages (for batch operations)
  static async createMany(messages) {
    if (!messages || messages.length === 0) {
      return [];
    }

    const query = `
      INSERT INTO chat_messages (session_id, user_id, message_type, content, metadata, created_at)
      VALUES ?
    `;
    
    const values = messages.map(msg => [
      msg.session_id,
      msg.user_id,
      msg.message_type,
      msg.content,
      msg.metadata ? JSON.stringify(msg.metadata) : null,
      new Date()
    ]);
    
    const result = await executeQuery(query, [values]);
    
    // Return the created messages
    const createdMessages = [];
    for (let i = 0; i < messages.length; i++) {
      const message = await this.findById(result.insertId + i);
      if (message) {
        createdMessages.push(message);
      }
    }
    
    return createdMessages;
  }

  // Find message by ID
  static async findById(id) {
    const query = 'SELECT * FROM chat_messages WHERE id = ?';
    const results = await executeQuery(query, [id]);
    
    if (results.length === 0) {
      return null;
    }
    
    return new ChatMessage(results[0]);
  }

  // Find messages by session ID
  static async findBySessionId(sessionId, options = {}) {
    const { limit = 50, offset = 0, order = 'ASC' } = options;
    
    const query = `
      SELECT * FROM chat_messages 
      WHERE session_id = ?
      ORDER BY created_at ${order}
      LIMIT ? OFFSET ?
    `;
    
    const results = await executeQuery(query, [sessionId, limit, offset]);
    
    return results.map(row => new ChatMessage(row));
  }

  // Find recent messages by session ID (for context)
  static async findRecentBySessionId(sessionId, limit = 10) {
    const query = `
      SELECT * FROM chat_messages 
      WHERE session_id = ?
      ORDER BY created_at DESC
      LIMIT ?
    `;
    
    const results = await executeQuery(query, [sessionId, limit]);
    
    // Return in chronological order (oldest first)
    return results.reverse().map(row => new ChatMessage(row));
  }

  // Find messages by user ID
  static async findByUserId(userId, options = {}) {
    const { limit = 100, offset = 0, message_type } = options;
    
    let query = `
      SELECT cm.*, cs.title as session_title
      FROM chat_messages cm
      JOIN chat_sessions cs ON cm.session_id = cs.id
      WHERE cm.user_id = ?
    `;
    
    const params = [userId];
    
    if (message_type) {
      query += ' AND cm.message_type = ?';
      params.push(message_type);
    }
    
    query += `
      ORDER BY cm.created_at DESC
      LIMIT ? OFFSET ?
    `;
    
    params.push(limit, offset);
    
    const results = await executeQuery(query, params);
    
    return results.map(row => {
      const message = new ChatMessage(row);
      message.session_title = row.session_title;
      return message;
    });
  }

  // Get conversation context for AI
  static async getConversationContext(sessionId, maxMessages = 20) {
    const messages = await this.findRecentBySessionId(sessionId, maxMessages);
    
    return messages.map(msg => ({
      role: msg.message_type === 'user' ? 'user' : 'assistant',
      content: msg.content,
      timestamp: msg.created_at
    }));
  }

  // Update message content (for editing)
  async update(updateData) {
    const { content, metadata } = updateData;
    
    const updates = [];
    const params = [];
    
    if (content !== undefined) {
      updates.push('content = ?');
      params.push(content);
    }
    
    if (metadata !== undefined) {
      updates.push('metadata = ?');
      params.push(metadata ? JSON.stringify(metadata) : null);
    }
    
    if (updates.length === 0) {
      return this;
    }
    
    params.push(this.id);
    
    const query = `
      UPDATE chat_messages 
      SET ${updates.join(', ')}
      WHERE id = ?
    `;
    
    await executeQuery(query, params);
    
    return await ChatMessage.findById(this.id);
  }

  // Delete message
  async delete() {
    const query = 'DELETE FROM chat_messages WHERE id = ?';
    await executeQuery(query, [this.id]);
    return true;
  }

  // Get message statistics for a user
  static async getUserStats(userId) {
    const query = `
      SELECT 
        COUNT(*) as total_messages,
        COUNT(CASE WHEN message_type = 'user' THEN 1 END) as user_messages,
        COUNT(CASE WHEN message_type = 'assistant' THEN 1 END) as assistant_messages,
        COUNT(DISTINCT session_id) as sessions_with_messages,
        AVG(CHAR_LENGTH(content)) as avg_message_length,
        MAX(created_at) as last_message_date,
        MIN(created_at) as first_message_date
      FROM chat_messages
      WHERE user_id = ?
    `;
    
    const results = await executeQuery(query, [userId]);
    
    return results[0] || {
      total_messages: 0,
      user_messages: 0,
      assistant_messages: 0,
      sessions_with_messages: 0,
      avg_message_length: 0,
      last_message_date: null,
      first_message_date: null
    };
  }

  // Get session message statistics
  static async getSessionStats(sessionId) {
    const query = `
      SELECT 
        COUNT(*) as total_messages,
        COUNT(CASE WHEN message_type = 'user' THEN 1 END) as user_messages,
        COUNT(CASE WHEN message_type = 'assistant' THEN 1 END) as assistant_messages,
        AVG(CHAR_LENGTH(content)) as avg_message_length,
        MAX(created_at) as last_message_date,
        MIN(created_at) as first_message_date
      FROM chat_messages
      WHERE session_id = ?
    `;
    
    const results = await executeQuery(query, [sessionId]);
    
    return results[0] || {
      total_messages: 0,
      user_messages: 0,
      assistant_messages: 0,
      avg_message_length: 0,
      last_message_date: null,
      first_message_date: null
    };
  }

  // Search messages by content
  static async search(userId, searchTerm, options = {}) {
    const { limit = 20, offset = 0 } = options;
    
    const query = `
      SELECT cm.*, cs.title as session_title
      FROM chat_messages cm
      JOIN chat_sessions cs ON cm.session_id = cs.id
      WHERE cm.user_id = ? AND cm.content LIKE ?
      ORDER BY cm.created_at DESC
      LIMIT ? OFFSET ?
    `;
    
    const searchPattern = `%${searchTerm}%`;
    const results = await executeQuery(query, [userId, searchPattern, limit, offset]);
    
    return results.map(row => {
      const message = new ChatMessage(row);
      message.session_title = row.session_title;
      return message;
    });
  }

  // Convert to JSON
  toJSON() {
    return {
      id: this.id,
      session_id: this.session_id,
      user_id: this.user_id,
      message_type: this.message_type,
      content: this.content,
      metadata: this.metadata,
      created_at: this.created_at,
      ...(this.session_title && { session_title: this.session_title })
    };
  }
}

module.exports = ChatMessage;