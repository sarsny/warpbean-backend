const express = require('express');
const { body, validationResult } = require('express-validator');
const deepseekService = require('../services/deepseekService');
const { asyncHandler } = require('../middleware/errorHandler');

const router = express.Router();

// Validation middleware (simplified)
const validateSuggestionRequest = [
  body('title')
    .isLength({ min: 1, max: 200 })
    .withMessage('Title must be between 1 and 200 characters')
    .trim(),
  body('personality')
    .optional()
    .isIn(['green', 'yellow', 'red'])
    .withMessage('Personality must be one of: green, yellow, red'),
  body('history')
    .optional()
    .isArray()
    .withMessage('History must be an array')
    .custom((value) => {
      if (value && value.length > 0) {
        for (const item of value) {
          if (!item.suggestion_text || !item.suggestion_type) {
            throw new Error('Each history item must have suggestion_text and suggestion_type');
          }
        }
      }
      return true;
    })
];

// Helper function to handle validation errors
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      error: 'Validation failed',
      details: errors.array()
    });
  }
  next();
};

// Generate anxiety suggestions (no auth, no database)
router.post('/generate', validateSuggestionRequest, handleValidationErrors, asyncHandler(async (req, res) => {
  const { title, personality = 'green' } = req.body;

  try {
    console.log(`🎯 生成建议请求: "${title}" (${personality}人格)`);
    
    // Generate suggestions using DeepSeek with personality support (no historical context for simplicity)
    const aiResponse = await deepseekService.generateAnxietySuggestions(title, [], personality);

    if (!aiResponse.success || !aiResponse.suggestions) {
      throw new Error('Failed to generate suggestions');
    }

    console.log(`✅ 成功生成 ${aiResponse.suggestions.length} 条建议 (${personality}人格)`);

    res.status(200).json({
      success: true,
      message: 'Suggestions generated successfully',
      suggestions: aiResponse.suggestions,
      usage: aiResponse.usage,
      personality: aiResponse.personality,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ 建议生成错误:', error.message);
    
    if (error.message.includes('DeepSeek') || error.message.includes('authentication')) {
      return res.status(503).json({
        error: 'AI service unavailable',
        message: 'Unable to generate suggestions at this time. Please check DeepSeek API configuration.',
        details: error.message
      });
    }
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to generate suggestions',
      details: error.message
    });
  }
}));

// Public suggestion generation endpoint (no authentication required)
router.post('/public/generate', validateSuggestionRequest, handleValidationErrors, asyncHandler(async (req, res) => {
  const { title, personality = 'green', history = [] } = req.body;

  try {
    console.log(`🌐 公开API建议生成请求: "${title}" (${personality}人格)${history.length > 0 ? ` 带${history.length}条历史记录` : ''}`);
    
    // Generate suggestions using DeepSeek with personality support and history context
    const aiResponse = await deepseekService.generateAnxietySuggestions(title, history, personality);

    if (!aiResponse.success || !aiResponse.suggestions) {
      throw new Error('Failed to generate suggestions');
    }

    console.log(`✅ 公开API成功生成 ${aiResponse.suggestions.length} 条建议 (${personality}人格)${history.length > 0 ? ` 基于${history.length}条历史记录` : ''}`);

    res.status(200).json({
      success: true,
      message: 'Public suggestions generated successfully',
      suggestions: aiResponse.suggestions,
      personality: personality,
      history_count: history.length,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ 公开API建议生成失败:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate public suggestions',
      message: error.message
    });
  }
}));

// Test endpoint for multiple suggestions with personality testing
router.post('/test-multiple', asyncHandler(async (req, res) => {
  const { personality = 'green' } = req.body;
  
  const testTopics = [
    '我想减肥',
    '工作压力很大', 
    '失眠睡不着',
    '人际关系焦虑'
  ];

  const results = [];

  try {
    console.log(`🧪 开始多主题测试 (${personality}人格)`);
    
    for (const topic of testTopics) {
      console.log(`🧪 测试主题: "${topic}" (${personality}人格)`);
      
      const aiResponse = await deepseekService.generateAnxietySuggestions(topic, [], personality);
      
      if (aiResponse.success && aiResponse.suggestions) {
        results.push({
          topic,
          success: true,
          suggestions: aiResponse.suggestions,
          usage: aiResponse.usage,
          personality: aiResponse.personality
        });
        console.log(`✅ "${topic}" - 生成 ${aiResponse.suggestions.length} 条建议 (${personality}人格)`);
      } else {
        results.push({
          topic,
          success: false,
          error: 'Failed to generate suggestions',
          personality: personality
        });
        console.log(`❌ "${topic}" - 生成失败 (${personality}人格)`);
      }
      
      // 避免请求过于频繁
      await new Promise(resolve => setTimeout(resolve, 1000));
    }

    res.status(200).json({
      success: true,
      message: `Multiple topic test completed with ${personality} personality`,
      results,
      personality: personality,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ 多主题测试错误:', error.message);
    
    res.status(500).json({
      error: 'Test failed',
      message: error.message,
      results
    });
  }
}));

// Health check for suggestion service
router.get('/health', asyncHandler(async (req, res) => {
  try {
    // Test DeepSeek service health
    const healthCheck = await deepseekService.checkHealth();
    
    res.status(200).json({
      status: 'OK',
      service: 'suggestion',
      deepseek: healthCheck,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(503).json({
      status: 'ERROR',
      service: 'suggestion',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
}));

module.exports = router;