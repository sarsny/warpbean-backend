const { executeQuery } = require('../config/database');

class ChatSession {
  constructor(data) {
    this.id = data.id;
    this.user_id = data.user_id;
    this.topic_id = data.topic_id;
    this.title = data.title;
    this.status = data.status || 'active';
    this.created_at = data.created_at;
    this.updated_at = data.updated_at;
    this.last_message_at = data.last_message_at;
    this.message_count = data.message_count || 0;
  }

  // Create a new chat session
  static async create(sessionData) {
    const { user_id, topic_id, title } = sessionData;
    
    const query = `
      INSERT INTO chat_sessions (user_id, topic_id, title, status, created_at, updated_at)
      VALUES (?, ?, ?, 'active', NOW(), NOW())
    `;
    
    const result = await executeQuery(query, [user_id, topic_id, title]);
    
    return await this.findById(result.insertId);
  }

  // Find session by ID
  static async findById(id) {
    const query = `
      SELECT cs.*, 
             COUNT(cm.id) as message_count,
             MAX(cm.created_at) as last_message_at
      FROM chat_sessions cs
      LEFT JOIN chat_messages cm ON cs.id = cm.session_id
      WHERE cs.id = ?
      GROUP BY cs.id
    `;
    
    const results = await executeQuery(query, [id]);
    
    if (results.length === 0) {
      return null;
    }
    
    return new ChatSession(results[0]);
  }

  // Find sessions by user ID
  static async findByUserId(userId, options = {}) {
    const { status, limit = 20, offset = 0 } = options;
    
    let query = `
      SELECT cs.*, 
             COUNT(cm.id) as message_count,
             MAX(cm.created_at) as last_message_at
      FROM chat_sessions cs
      LEFT JOIN chat_messages cm ON cs.id = cm.session_id
      WHERE cs.user_id = ?
    `;
    
    const params = [userId];
    
    if (status) {
      query += ' AND cs.status = ?';
      params.push(status);
    }
    
    query += `
      GROUP BY cs.id
      ORDER BY cs.updated_at DESC
      LIMIT ? OFFSET ?
    `;
    
    params.push(limit, offset);
    
    const results = await executeQuery(query, params);
    
    return results.map(row => new ChatSession(row));
  }

  // Find sessions by topic ID
  static async findByTopicId(topicId, options = {}) {
    const { status, limit = 10, offset = 0 } = options;
    
    let query = `
      SELECT cs.*, 
             COUNT(cm.id) as message_count,
             MAX(cm.created_at) as last_message_at
      FROM chat_sessions cs
      LEFT JOIN chat_messages cm ON cs.id = cm.session_id
      WHERE cs.topic_id = ?
    `;
    
    const params = [topicId];
    
    if (status) {
      query += ' AND cs.status = ?';
      params.push(status);
    }
    
    query += `
      GROUP BY cs.id
      ORDER BY cs.updated_at DESC
      LIMIT ? OFFSET ?
    `;
    
    params.push(limit, offset);
    
    const results = await executeQuery(query, params);
    
    return results.map(row => new ChatSession(row));
  }

  // Update session
  async update(updateData) {
    const allowedFields = ['title', 'status'];
    const updates = [];
    const params = [];
    
    for (const [key, value] of Object.entries(updateData)) {
      if (allowedFields.includes(key) && value !== undefined) {
        updates.push(`${key} = ?`);
        params.push(value);
      }
    }
    
    if (updates.length === 0) {
      return this;
    }
    
    updates.push('updated_at = NOW()');
    params.push(this.id);
    
    const query = `
      UPDATE chat_sessions 
      SET ${updates.join(', ')}
      WHERE id = ?
    `;
    
    await executeQuery(query, params);
    
    return await ChatSession.findById(this.id);
  }

  // Update last message timestamp
  async updateLastMessage() {
    const query = `
      UPDATE chat_sessions 
      SET updated_at = NOW(), last_message_at = NOW()
      WHERE id = ?
    `;
    
    await executeQuery(query, [this.id]);
    
    return await ChatSession.findById(this.id);
  }

  // Archive session
  async archive() {
    return await this.update({ status: 'archived' });
  }

  // End session
  async end() {
    return await this.update({ status: 'ended' });
  }

  // Get session with topic information
  async getWithTopic() {
    const query = `
      SELECT cs.*, 
             at.title as topic_title,
             at.description as topic_description,
             at.severity_level as topic_severity,
             COUNT(cm.id) as message_count,
             MAX(cm.created_at) as last_message_at
      FROM chat_sessions cs
      LEFT JOIN anxiety_topics at ON cs.topic_id = at.id
      LEFT JOIN chat_messages cm ON cs.id = cm.session_id
      WHERE cs.id = ?
      GROUP BY cs.id
    `;
    
    const results = await executeQuery(query, [this.id]);
    
    if (results.length === 0) {
      return null;
    }
    
    const sessionData = results[0];
    const session = new ChatSession(sessionData);
    
    // Add topic information
    session.topic = {
      id: this.topic_id,
      title: sessionData.topic_title,
      description: sessionData.topic_description,
      severity_level: sessionData.topic_severity
    };
    
    return session;
  }

  // Get user statistics
  static async getUserStats(userId) {
    const query = `
      SELECT 
        COUNT(*) as total_sessions,
        COUNT(CASE WHEN status = 'active' THEN 1 END) as active_sessions,
        COUNT(CASE WHEN status = 'ended' THEN 1 END) as ended_sessions,
        COUNT(CASE WHEN status = 'archived' THEN 1 END) as archived_sessions,
        AVG(
          (SELECT COUNT(*) FROM chat_messages cm WHERE cm.session_id = cs.id)
        ) as avg_messages_per_session,
        MAX(updated_at) as last_session_date
      FROM chat_sessions cs
      WHERE user_id = ?
    `;
    
    const results = await executeQuery(query, [userId]);
    
    return results[0] || {
      total_sessions: 0,
      active_sessions: 0,
      ended_sessions: 0,
      archived_sessions: 0,
      avg_messages_per_session: 0,
      last_session_date: null
    };
  }

  // Convert to JSON
  toJSON() {
    return {
      id: this.id,
      user_id: this.user_id,
      topic_id: this.topic_id,
      title: this.title,
      status: this.status,
      message_count: this.message_count,
      created_at: this.created_at,
      updated_at: this.updated_at,
      last_message_at: this.last_message_at,
      ...(this.topic && { topic: this.topic })
    };
  }
}

module.exports = ChatSession;