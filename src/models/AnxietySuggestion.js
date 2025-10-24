const { executeQuery } = require('../config/database');

class AnxietySuggestion {
  constructor(data) {
    this.id = data.id;
    this.topic_id = data.topic_id;
    this.user_id = data.user_id;
    this.suggestion_text = data.suggestion_text;
    this.suggestion_type = data.suggestion_type;
    this.is_helpful = data.is_helpful;
    this.helpful_rating = data.helpful_rating;
    this.created_at = data.created_at;
    this.updated_at = data.updated_at;
  }

  // Create a new suggestion
  static async create(suggestionData) {
    const { topic_id, user_id, suggestion_text, suggestion_type = 'immediate' } = suggestionData;
    
    const query = `
      INSERT INTO anxiety_suggestions (topic_id, user_id, suggestion_text, suggestion_type)
      VALUES (?, ?, ?, ?)
    `;
    
    const result = await executeQuery(query, [topic_id, user_id, suggestion_text, suggestion_type]);
    
    return await AnxietySuggestion.findById(result.insertId);
  }

  // Create multiple suggestions
  static async createMany(suggestions) {
    if (!suggestions || suggestions.length === 0) {
      return [];
    }

    const query = `
      INSERT INTO anxiety_suggestions (topic_id, user_id, suggestion_text, suggestion_type)
      VALUES ?
    `;
    
    const values = suggestions.map(s => [
      s.topic_id,
      s.user_id,
      s.suggestion_text,
      s.suggestion_type || 'immediate'
    ]);
    
    const result = await executeQuery(query, [values]);
    
    // Get all created suggestions
    const createdSuggestions = [];
    for (let i = 0; i < suggestions.length; i++) {
      const suggestion = await AnxietySuggestion.findById(result.insertId + i);
      if (suggestion) {
        createdSuggestions.push(suggestion);
      }
    }
    
    return createdSuggestions;
  }

  // Find suggestion by ID
  static async findById(id) {
    const query = 'SELECT * FROM anxiety_suggestions WHERE id = ?';
    const results = await executeQuery(query, [id]);
    
    if (results.length === 0) {
      return null;
    }
    
    return new AnxietySuggestion(results[0]);
  }

  // Find suggestions by topic ID
  static async findByTopicId(topicId, options = {}) {
    const { limit = 50, offset = 0, type } = options;
    
    let query = 'SELECT * FROM anxiety_suggestions WHERE topic_id = ?';
    let params = [topicId];
    
    if (type) {
      query += ' AND suggestion_type = ?';
      params.push(type);
    }
    
    query += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);
    
    const results = await executeQuery(query, params);
    
    return results.map(row => new AnxietySuggestion(row));
  }

  // Find suggestions by user ID
  static async findByUserId(userId, options = {}) {
    const { limit = 50, offset = 0, type } = options;
    
    let query = 'SELECT * FROM anxiety_suggestions WHERE user_id = ?';
    let params = [userId];
    
    if (type) {
      query += ' AND suggestion_type = ?';
      params.push(type);
    }
    
    query += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);
    
    const results = await executeQuery(query, params);
    
    return results.map(row => new AnxietySuggestion(row));
  }

  // Update suggestion feedback
  async updateFeedback(feedbackData) {
    const { is_helpful, helpful_rating } = feedbackData;
    const updates = [];
    const values = [];
    
    if (is_helpful !== undefined) {
      updates.push('is_helpful = ?');
      values.push(is_helpful);
    }
    
    if (helpful_rating !== undefined && helpful_rating >= 1 && helpful_rating <= 5) {
      updates.push('helpful_rating = ?');
      values.push(helpful_rating);
    }
    
    if (updates.length === 0) {
      return this;
    }
    
    values.push(this.id);
    const query = `UPDATE anxiety_suggestions SET ${updates.join(', ')}, updated_at = CURRENT_TIMESTAMP WHERE id = ?`;
    
    await executeQuery(query, values);
    
    return await AnxietySuggestion.findById(this.id);
  }

  // Get suggestions with topic information
  static async findWithTopicInfo(userId, options = {}) {
    const { limit = 50, offset = 0 } = options;
    
    const query = `
      SELECT 
        as.*,
        at.title as topic_title,
        at.severity_level as topic_severity
      FROM anxiety_suggestions as
      JOIN anxiety_topics at ON as.topic_id = at.id
      WHERE as.user_id = ?
      ORDER BY as.created_at DESC
      LIMIT ? OFFSET ?
    `;
    
    const results = await executeQuery(query, [userId, limit, offset]);
    
    return results.map(row => {
      const suggestion = new AnxietySuggestion(row);
      suggestion.topic_title = row.topic_title;
      suggestion.topic_severity = row.topic_severity;
      return suggestion;
    });
  }

  // Get suggestion statistics for a user
  static async getUserStats(userId) {
    const query = `
      SELECT 
        COUNT(*) as total_suggestions,
        COUNT(CASE WHEN is_helpful = TRUE THEN 1 END) as helpful_suggestions,
        COUNT(CASE WHEN is_helpful = FALSE THEN 1 END) as not_helpful_suggestions,
        AVG(helpful_rating) as average_rating,
        COUNT(CASE WHEN suggestion_type = 'immediate' THEN 1 END) as immediate_suggestions,
        COUNT(CASE WHEN suggestion_type = 'short_term' THEN 1 END) as short_term_suggestions,
        COUNT(CASE WHEN suggestion_type = 'long_term' THEN 1 END) as long_term_suggestions,
        COUNT(CASE WHEN suggestion_type = 'professional' THEN 1 END) as professional_suggestions
      FROM anxiety_suggestions 
      WHERE user_id = ?
    `;
    
    const results = await executeQuery(query, [userId]);
    return results[0];
  }

  // Convert to JSON
  toJSON() {
    return {
      id: this.id,
      topic_id: this.topic_id,
      user_id: this.user_id,
      suggestion_text: this.suggestion_text,
      suggestion_type: this.suggestion_type,
      is_helpful: this.is_helpful,
      helpful_rating: this.helpful_rating,
      created_at: this.created_at,
      updated_at: this.updated_at,
      ...(this.topic_title && { topic_title: this.topic_title }),
      ...(this.topic_severity && { topic_severity: this.topic_severity })
    };
  }
}

module.exports = AnxietySuggestion;