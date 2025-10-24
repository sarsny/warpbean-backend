const fs = require('fs').promises;
const path = require('path');
const { pool, testConnection } = require('../config/database');

const runMigration = async () => {
  try {
    console.log('🔄 Starting database migration...');
    
    // Test database connection
    const isConnected = await testConnection();
    if (!isConnected) {
      throw new Error('Database connection failed');
    }

    // Read schema file
    const schemaPath = path.join(__dirname, 'schema.sql');
    const schema = await fs.readFile(schemaPath, 'utf8');
    
    // Split schema into individual statements
    const statements = schema
      .split(';')
      .map(stmt => stmt.trim())
      .filter(stmt => stmt.length > 0 && !stmt.startsWith('--'));

    console.log(`📝 Found ${statements.length} SQL statements to execute`);

    // Execute each statement
    for (let i = 0; i < statements.length; i++) {
      const statement = statements[i];
      try {
        await pool.execute(statement);
        console.log(`✅ Statement ${i + 1}/${statements.length} executed successfully`);
      } catch (error) {
        console.error(`❌ Error executing statement ${i + 1}:`, error.message);
        console.error('Statement:', statement);
        throw error;
      }
    }

    console.log('🎉 Database migration completed successfully!');
    
  } catch (error) {
    console.error('💥 Migration failed:', error.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
};

// Run migration if this file is executed directly
if (require.main === module) {
  runMigration();
}

module.exports = { runMigration };