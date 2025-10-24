const axios = require('axios');

const BASE_URL = 'http://localhost:3000/api/suggestion-test';

// 测试配置
const TEST_CONFIG = {
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json'
  }
};

// 测试主题
const TEST_TOPIC = '工作压力很大';

// 测试三种人格的建议生成
async function testPersonalities() {
  console.log('🧪 开始测试三种人格的建议生成...\n');
  
  const personalities = ['green', 'yellow', 'red'];
  const results = [];
  
  for (const personality of personalities) {
    console.log(`🎭 测试 ${personality.toUpperCase()} 人格...`);
    
    try {
      const response = await axios.post(`${BASE_URL}/generate`, {
        title: TEST_TOPIC,
        personality: personality
      }, TEST_CONFIG);
      
      if (response.data.success) {
        console.log(`✅ ${personality.toUpperCase()} 人格测试成功`);
        console.log(`   生成建议数量: ${response.data.suggestions.length}`);
        console.log(`   使用的人格: ${response.data.personality}`);
        console.log(`   示例建议: "${response.data.suggestions[0]?.text || 'N/A'}"`);
        console.log(`   API使用统计: ${JSON.stringify(response.data.usage)}\n`);
        
        results.push({
          personality,
          success: true,
          suggestions: response.data.suggestions,
          usage: response.data.usage
        });
      } else {
        console.log(`❌ ${personality.toUpperCase()} 人格测试失败: ${response.data.message}\n`);
        results.push({
          personality,
          success: false,
          error: response.data.message
        });
      }
      
      // 避免请求过于频繁
      await new Promise(resolve => setTimeout(resolve, 2000));
      
    } catch (error) {
      console.log(`❌ ${personality.toUpperCase()} 人格测试出错: ${error.message}\n`);
      results.push({
        personality,
        success: false,
        error: error.message
      });
    }
  }
  
  return results;
}

// 测试多主题多人格
async function testMultipleTopicsWithPersonality() {
  console.log('🧪 开始测试多主题多人格...\n');
  
  const personalities = ['green', 'yellow', 'red'];
  const results = [];
  
  for (const personality of personalities) {
    console.log(`🎭 测试 ${personality.toUpperCase()} 人格的多主题生成...`);
    
    try {
      const response = await axios.post(`${BASE_URL}/test-multiple`, {
        personality: personality
      }, TEST_CONFIG);
      
      if (response.data.success) {
        console.log(`✅ ${personality.toUpperCase()} 人格多主题测试成功`);
        console.log(`   测试主题数量: ${response.data.results.length}`);
        console.log(`   成功生成数量: ${response.data.results.filter(r => r.success).length}`);
        console.log(`   使用的人格: ${response.data.personality}\n`);
        
        results.push({
          personality,
          success: true,
          results: response.data.results
        });
      } else {
        console.log(`❌ ${personality.toUpperCase()} 人格多主题测试失败: ${response.data.message}\n`);
        results.push({
          personality,
          success: false,
          error: response.data.message
        });
      }
      
      // 避免请求过于频繁
      await new Promise(resolve => setTimeout(resolve, 3000));
      
    } catch (error) {
      console.log(`❌ ${personality.toUpperCase()} 人格多主题测试出错: ${error.message}\n`);
      results.push({
        personality,
        success: false,
        error: error.message
      });
    }
  }
  
  return results;
}

// 检查服务健康状态
async function checkHealth() {
  console.log('🏥 检查服务健康状态...');
  
  try {
    const response = await axios.get(`${BASE_URL}/health`, TEST_CONFIG);
    
    if (response.data.success) {
      console.log('✅ 服务健康状态正常');
      console.log(`   DeepSeek服务状态: ${response.data.deepseek_status}`);
      console.log(`   服务器时间: ${response.data.timestamp}\n`);
      return true;
    } else {
      console.log('❌ 服务健康检查失败\n');
      return false;
    }
  } catch (error) {
    console.log(`❌ 服务健康检查出错: ${error.message}\n`);
    return false;
  }
}

// 主测试函数
async function runTests() {
  console.log('🚀 开始人格API测试...\n');
  
  // 1. 检查服务健康状态
  const isHealthy = await checkHealth();
  if (!isHealthy) {
    console.log('❌ 服务不健康，终止测试');
    return;
  }
  
  // 2. 测试三种人格的单个建议生成
  const personalityResults = await testPersonalities();
  
  // 3. 测试多主题多人格
  const multipleResults = await testMultipleTopicsWithPersonality();
  
  // 4. 输出测试总结
  console.log('📊 测试总结:');
  console.log('='.repeat(50));
  
  console.log('\n🎭 单个建议生成测试:');
  personalityResults.forEach(result => {
    const status = result.success ? '✅' : '❌';
    console.log(`   ${status} ${result.personality.toUpperCase()} 人格: ${result.success ? '成功' : result.error}`);
  });
  
  console.log('\n🎭 多主题生成测试:');
  multipleResults.forEach(result => {
    const status = result.success ? '✅' : '❌';
    console.log(`   ${status} ${result.personality.toUpperCase()} 人格: ${result.success ? '成功' : result.error}`);
  });
  
  const totalSuccess = personalityResults.filter(r => r.success).length + multipleResults.filter(r => r.success).length;
  const totalTests = personalityResults.length + multipleResults.length;
  
  console.log(`\n🎯 总体结果: ${totalSuccess}/${totalTests} 测试通过`);
  console.log('='.repeat(50));
}

// 运行测试
if (require.main === module) {
  runTests().catch(error => {
    console.error('❌ 测试运行失败:', error.message);
    process.exit(1);
  });
}

module.exports = {
  testPersonalities,
  testMultipleTopicsWithPersonality,
  checkHealth,
  runTests
};