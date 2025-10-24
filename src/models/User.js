const { executeQuery } = require('../config/database');
const bcrypt = require('bcryptjs');

class User {
  constructor(data) {
    this.id = data.id;
    this.username = data.username;
    this.email = data.email;
    this.password_hash = data.password_hash;
    this.full_name = data.full_name;
    this.avatar_url = data.avatar_url;
    this.created_at = data.created_at;
    this.updated_at = data.updated_at;
    this.last_login = data.last_login;
    this.is_active = data.is_active;
  }

  // Create a new user
  static async create(userData) {
    const { username, email, password, full_name } = userData;
    
    // Hash password
    const saltRounds = 10;
    const password_hash = await bcrypt.hash(password, saltRounds);
    
    const query = `
      INSERT INTO users (username, email, password_hash, full_name)
      VALUES (?, ?, ?, ?)
    `;
    
    const result = await executeQuery(query, [username, email, password_hash, full_name]);
    
    // Return the created user
    return await User.findById(result.insertId);
  }

  // Find user by ID
  static async findById(id) {
    const query = 'SELECT * FROM users WHERE id = ? AND is_active = TRUE';
    const results = await executeQuery(query, [id]);
    
    if (results.length === 0) {
      return null;
    }
    
    return new User(results[0]);
  }

  // Find user by username
  static async findByUsername(username) {
    const query = 'SELECT * FROM users WHERE username = ? AND is_active = TRUE';
    const results = await executeQuery(query, [username]);
    
    if (results.length === 0) {
      return null;
    }
    
    return new User(results[0]);
  }

  // Find user by email
  static async findByEmail(email) {
    const query = 'SELECT * FROM users WHERE email = ? AND is_active = TRUE';
    const results = await executeQuery(query, [email]);
    
    if (results.length === 0) {
      return null;
    }
    
    return new User(results[0]);
  }

  // Verify password
  async verifyPassword(password) {
    return await bcrypt.compare(password, this.password_hash);
  }

  // Update last login
  async updateLastLogin() {
    const query = 'UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?';
    await executeQuery(query, [this.id]);
    this.last_login = new Date();
  }

  // Update user profile
  async update(updateData) {
    const allowedFields = ['full_name', 'avatar_url'];
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
    const query = `UPDATE users SET ${updates.join(', ')}, updated_at = CURRENT_TIMESTAMP WHERE id = ?`;
    
    await executeQuery(query, values);
    
    // Refresh user data
    return await User.findById(this.id);
  }

  // Soft delete user
  async deactivate() {
    const query = 'UPDATE users SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP WHERE id = ?';
    await executeQuery(query, [this.id]);
    this.is_active = false;
  }

  // Get user's public data (without sensitive information)
  toPublicJSON() {
    return {
      id: this.id,
      username: this.username,
      email: this.email,
      full_name: this.full_name,
      avatar_url: this.avatar_url,
      created_at: this.created_at,
      last_login: this.last_login
    };
  }

  // Check if username exists
  static async usernameExists(username, excludeId = null) {
    let query = 'SELECT COUNT(*) as count FROM users WHERE username = ?';
    let params = [username];
    
    if (excludeId) {
      query += ' AND id != ?';
      params.push(excludeId);
    }
    
    const results = await executeQuery(query, params);
    return results[0].count > 0;
  }

  // Check if email exists
  static async emailExists(email, excludeId = null) {
    let query = 'SELECT COUNT(*) as count FROM users WHERE email = ?';
    let params = [email];
    
    if (excludeId) {
      query += ' AND id != ?';
      params.push(excludeId);
    }
    
    const results = await executeQuery(query, params);
    return results[0].count > 0;
  }
}

module.exports = User;