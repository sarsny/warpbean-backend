-- WarpBean Database Schema
-- Created: 2024-12-17

-- Create database if not exists
CREATE DATABASE IF NOT EXISTS warpbean CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE warpbean;

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    avatar_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE,
    INDEX idx_username (username),
    INDEX idx_email (email),
    INDEX idx_created_at (created_at)
);

-- Anxiety topics table
CREATE TABLE IF NOT EXISTS anxiety_topics (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    severity_level ENUM('low', 'medium', 'high', 'critical') DEFAULT 'medium',
    status ENUM('active', 'resolved', 'archived') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
);

-- Anxiety suggestions table
CREATE TABLE IF NOT EXISTS anxiety_suggestions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    topic_id INT NOT NULL,
    user_id INT NOT NULL,
    suggestion_text TEXT NOT NULL,
    suggestion_type ENUM('immediate', 'short_term', 'long_term', 'professional') DEFAULT 'immediate',
    is_helpful BOOLEAN NULL,
    helpful_rating INT CHECK (helpful_rating >= 1 AND helpful_rating <= 5),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (topic_id) REFERENCES anxiety_topics(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_topic_id (topic_id),
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at)
);

-- Chat sessions table
CREATE TABLE IF NOT EXISTS chat_sessions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    topic_id INT NULL,
    session_title VARCHAR(200),
    status ENUM('active', 'ended', 'archived') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    ended_at TIMESTAMP NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (topic_id) REFERENCES anxiety_topics(id) ON DELETE SET NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_topic_id (topic_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
);

-- Chat messages table
CREATE TABLE IF NOT EXISTS chat_messages (
    id INT PRIMARY KEY AUTO_INCREMENT,
    session_id INT NOT NULL,
    user_id INT NOT NULL,
    message_type ENUM('user', 'assistant') NOT NULL,
    content TEXT NOT NULL,
    metadata JSON NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_session_id (session_id),
    INDEX idx_user_id (user_id),
    INDEX idx_message_type (message_type),
    INDEX idx_created_at (created_at)
);

-- User activity log table
CREATE TABLE IF NOT EXISTS user_activity_log (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    activity_type ENUM('login', 'logout', 'suggestion_request', 'chat_start', 'chat_end') NOT NULL,
    details JSON NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_activity_type (activity_type),
    INDEX idx_created_at (created_at)
);

-- API usage tracking table
CREATE TABLE IF NOT EXISTS api_usage (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    endpoint VARCHAR(100) NOT NULL,
    method VARCHAR(10) NOT NULL,
    status_code INT NOT NULL,
    response_time_ms INT,
    request_size_bytes INT,
    response_size_bytes INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_endpoint (endpoint),
    INDEX idx_created_at (created_at)
);

-- Insert default admin user (password: admin123)
INSERT IGNORE INTO users (username, email, password_hash, full_name, is_active) VALUES 
('admin', 'admin@warpbean.com', '$2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'System Administrator', TRUE);