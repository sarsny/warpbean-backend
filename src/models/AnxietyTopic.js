const { executeQuery } = require('../config/database');

class AnxietyTopic {
  constructor(data) {
    this.id = data.id;
    this.user_id = data.user_id;
    this.title = data.title;
    this.description = data.description;
    this.severity_level = data.severity_level;
    this.status = data.status;
    this.created_at = data.created_at;
    this.updated_at = data.updated_at;
  }

  // Create a new anxiety topic
  static async create(topicData) {
    const { user_id, title, description, severity_level = 'medium' } = topicData;
    
    const query = `
      INSERT INTO anxiety_topics (user_id, title, description, severity_level)
      VALUES (?, ?, ?, ?)
    `;
    
    const result = await executeQuery(query, [user_id, title, description, severity_level]);
    
    return await AnxietyTopic.findById(result.insertId);
  }

  // Find topic by ID
  static async findById(id) {
    const query = 'SELECT * FROM anxiety_topics WHERE id = ?';
    const results = await executeQuery(query, [id]);
    
    if (results.length === 0) {
      return null;
    }
    
    return new AnxietyTopic(results[0]);
  }

  // Find topics by user ID
  static async findByUserId(userId, options = {}) {
    const { status, limit = 50, offset = 0 } = options;
    
    let query = 'SELECT * FROM anxiety_topics WHERE user_id = ?';
    let params = [userId];
    
    if (status) {
      query += ' AND status = ?';
      params.push(status);
    }
    
    query += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);
    
    const results = await executeQuery(query, params);
    
    return results.map(row => new AnxietyTopic(row));
  }

  // Update topic
  async update(updateData) {
    const allowedFields = ['title', 'description', 'severity_level', 'status'];
    const updates = [];
    const values = [];
    
    for (const [key, value] of Object.entries(updateData)) {
      if (allowedFields.includes(key) && value !== undefined) {
        updates.push(`${key} = ?`);
        values.push(value);
      }
    }
    
    if (updates.length === 0) {
      return this;
    }
    
    values.push(this.id);
    const query = `UPDATE anxiety_topics SET ${updates.join(', ')}, updated_at = CURRENT_TIMESTAMP WHERE id = ?`;
    
    await executeQuery(query, values);
    
    return await AnxietyTopic.findById(this.id);
  }

  // Delete topic (soft delete by changing status)
  async archive() {
    return await this.update({ status: 'archived' });
  }

  // Get topic with suggestions count
  async getWithSuggestionsCount() {
    const query = `
      SELECT 
        at.*,
        COUNT(as.id) as suggestions_count
      FROM anxiety_topics at
      LEFT JOIN anxiety_suggestions as ON at.id = as.topic_id
      WHERE at.id = ?
      GROUP BY at.id
    `;
    
    const results = await executeQuery(query, [this.id]);
    
    if (results.length === 0) {
      return null;
    }
    
    const topicData = { ...results[0] };
    delete topicData.suggestions_count;
    
    const topic = new AnxietyTopic(topicData);
    topic.suggestions_count = results[0].suggestions_count;
    
    return topic;
  }

  // Get user's topic statistics
  static async getUserStats(userId) {
    const query = `
      SELECT 
        COUNT(*) as total_topics,
        COUNT(CASE WHEN status = 'active' THEN 1 END) as active_topics,
        COUNT(CASE WHEN status = 'resolved' THEN 1 END) as resolved_topics,
        COUNT(CASE WHEN severity_level = 'high' OR severity_level = 'critical' THEN 1 END) as high_severity_topics
      FROM anxiety_topics 
      WHERE user_id = ?
    `;
    
    const results = await executeQuery(query, [userId]);
    return results[0];
  }

  // Convert to JSON
  toJSON() {
    return {
      id: this.id,
      user_id: this.user_id,
      title: this.title,
      description: this.description,
      severity_level: this.severity_level,
      status: this.status,
      created_at: this.created_at,
      updated_at: this.updated_at,
      ...(this.suggestions_count !== undefined && { suggestions_count: this.suggestions_count })
    };
  }
}

module.exports = AnxietyTopic;