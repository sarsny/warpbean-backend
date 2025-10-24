const mysql = require('mysql2/promise');

const dbConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'warpbean',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  acquireTimeout: 60000,
  timeout: 60000,
  reconnect: true
};

// Allow disabling database via environment variable
const DB_DISABLED = process.env.DB_DISABLED === '1' || process.env.DB_DISABLED === 'true';

// Create connection pool (disabled when DB_DISABLED is set)
const pool = DB_DISABLED ? null : mysql.createPool(dbConfig);

// Test database connection
const testConnection = async () => {
  if (DB_DISABLED) {
    console.log('ℹ️ Database disabled, skipping connection test');
    return true;
  }
  try {
    const connection = await pool.getConnection();
    console.log('✅ Database connected successfully');
    connection.release();
    return true;
  } catch (error) {
    console.error('❌ Database connection failed:', error.message);
    return false;
  }
};

// Execute query with error handling
const executeQuery = async (query, params = []) => {
  if (DB_DISABLED) {
    throw new Error('Database disabled');
  }
  try {
    const [results] = await pool.execute(query, params);
    return results;
  } catch (error) {
    console.error('Database query error:', error);
    throw error;
  }
};

// Get a single connection for transactions
const getConnection = async () => {
  if (DB_DISABLED) {
    throw new Error('Database disabled');
  }
  return await pool.getConnection();
};

module.exports = {
  pool,
  testConnection,
  executeQuery,
  getConnection
};