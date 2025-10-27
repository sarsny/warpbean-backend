const express = require('express');
const { body, param, validationResult } = require('express-validator');
const AnxietyTopic = require('../models/AnxietyTopic');
const AnxietySuggestion = require('../models/AnxietySuggestion');
const deepseekService = require('../services/deepseekService');
const { asyncHandler } = require('../middleware/errorHandler');

const router = express.Router();

// Validation middleware
const validateSuggestionRequest = [
  body('title')
    .isLength({ min: 1, max: 200 })
    .withMessage('Title must be between 1 and 200 characters')
    .trim(),
  body('description')
    .optional()
    .isLength({ max: 1000 })
    .withMessage('Description must not exceed 1000 characters')
    .trim(),
  body('title_context')
    .optional()
    .isLength({ max: 500 })
    .withMessage('title_context must not exceed 500 characters')
    .trim(),
  body('severity_level')
    .optional()
    .isIn(['low', 'medium', 'high', 'critical'])
    .withMessage('Severity level must be one of: low, medium, high, critical'),
  body('personality')
    .optional()
    .isIn(['green', 'yellow', 'red'])
    .withMessage('Personality must be one of: green, yellow, red')
];

const validateFeedback = [
  param('id').isInt({ min: 1 }).withMessage('Invalid suggestion ID'),
  body('is_helpful')
    .optional()
    .isBoolean()
    .withMessage('is_helpful must be a boolean'),
  body('helpful_rating')
    .optional()
    .isInt({ min: 1, max: 5 })
    .withMessage('helpful_rating must be between 1 and 5')
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

// Generate anxiety suggestions
router.post('/', validateSuggestionRequest, handleValidationErrors, asyncHandler(async (req, res) => {
  const { title, description, title_context, severity_level = 'medium', personality = 'green' } = req.body;
  const userId = req.user.id;

  try {
    // Create or find existing anxiety topic
    let topic = await AnxietyTopic.create({
      user_id: userId,
      title,
      description,
      severity_level
    });

    // Get historical suggestions for this user to provide context
    const historicalSuggestions = await AnxietySuggestion.findByUserId(userId, { limit: 10 });
    
    // Generate suggestions using DeepSeek with personality support
    const aiResponse = await deepseekService.generateAnxietySuggestions(
      title,
      historicalSuggestions.map(s => ({
        suggestion_text: s.suggestion_text,
        suggestion_type: s.suggestion_type
      })),
      personality,
      title_context || description
    );

    if (!aiResponse.success || !aiResponse.suggestions) {
      throw new Error('Failed to generate suggestions');
    }

    // Save suggestions to database
    const suggestionsToCreate = aiResponse.suggestions.map(suggestion => ({
      topic_id: topic.id,
      user_id: userId,
      suggestion_text: suggestion.text,
      suggestion_type: suggestion.type || 'immediate'
    }));

    const createdSuggestions = await AnxietySuggestion.createMany(suggestionsToCreate);

    res.status(201).json({
      success: true,
      message: 'Suggestions generated successfully',
      data: {
        topic: topic.toJSON(),
        suggestions: createdSuggestions.map(s => s.toJSON()),
        usage: aiResponse.usage,
        personality: aiResponse.personality
      }
    });

  } catch (error) {
    console.error('Suggestion generation error:', error);
    
    if (error.message.includes('DeepSeek')) {
      return res.status(503).json({
        error: 'AI service unavailable',
        message: 'Unable to generate suggestions at this time. Please try again later.'
      });
    }
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to generate suggestions'
    });
  }
}));

// Get user's anxiety topics
router.get('/topics', asyncHandler(async (req, res) => {
  const userId = req.user.id;
  const { status, limit = 20, offset = 0 } = req.query;

  const topics = await AnxietyTopic.findByUserId(userId, {
    status,
    limit: parseInt(limit),
    offset: parseInt(offset)
  });

  // Get suggestions count for each topic
  const topicsWithCounts = await Promise.all(
    topics.map(async (topic) => {
      const topicWithCount = await topic.getWithSuggestionsCount();
      return topicWithCount ? topicWithCount.toJSON() : topic.toJSON();
    })
  );

  res.json({
    success: true,
    data: {
      topics: topicsWithCounts,
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        has_more: topics.length === parseInt(limit)
      }
    }
  });
}));

// Get specific topic with suggestions
router.get('/topics/:id', param('id').isInt({ min: 1 }), handleValidationErrors, asyncHandler(async (req, res) => {
  const topicId = parseInt(req.params.id);
  const userId = req.user.id;

  const topic = await AnxietyTopic.findById(topicId);
  
  if (!topic) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Topic not found'
    });
  }

  // Check if topic belongs to user
  if (topic.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only access your own topics'
    });
  }

  // Get suggestions for this topic
  const suggestions = await AnxietySuggestion.findByTopicId(topicId);

  res.json({
    success: true,
    data: {
      topic: topic.toJSON(),
      suggestions: suggestions.map(s => s.toJSON())
    }
  });
}));

// Update topic
router.put('/topics/:id', [
  param('id').isInt({ min: 1 }),
  body('title').optional().isLength({ min: 1, max: 200 }).trim(),
  body('description').optional().isLength({ max: 1000 }).trim(),
  body('severity_level').optional().isIn(['low', 'medium', 'high', 'critical']),
  body('status').optional().isIn(['active', 'resolved', 'archived'])
], handleValidationErrors, asyncHandler(async (req, res) => {
  const topicId = parseInt(req.params.id);
  const userId = req.user.id;
  const updateData = req.body;

  const topic = await AnxietyTopic.findById(topicId);
  
  if (!topic) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Topic not found'
    });
  }

  if (topic.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only update your own topics'
    });
  }

  const updatedTopic = await topic.update(updateData);

  res.json({
    success: true,
    message: 'Topic updated successfully',
    data: {
      topic: updatedTopic.toJSON()
    }
  });
}));

// Get user's suggestions with pagination
router.get('/history', asyncHandler(async (req, res) => {
  const userId = req.user.id;
  const { type, limit = 20, offset = 0 } = req.query;

  const suggestions = await AnxietySuggestion.findWithTopicInfo(userId, {
    type,
    limit: parseInt(limit),
    offset: parseInt(offset)
  });

  res.json({
    success: true,
    data: {
      suggestions: suggestions.map(s => s.toJSON()),
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        has_more: suggestions.length === parseInt(limit)
      }
    }
  });
}));

// Provide feedback on suggestion
router.post('/feedback/:id', validateFeedback, handleValidationErrors, asyncHandler(async (req, res) => {
  const suggestionId = parseInt(req.params.id);
  const userId = req.user.id;
  const { is_helpful, helpful_rating } = req.body;

  const suggestion = await AnxietySuggestion.findById(suggestionId);
  
  if (!suggestion) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Suggestion not found'
    });
  }

  if (suggestion.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only provide feedback on your own suggestions'
    });
  }

  const updatedSuggestion = await suggestion.updateFeedback({
    is_helpful,
    helpful_rating
  });

  res.json({
    success: true,
    message: 'Feedback recorded successfully',
    data: {
      suggestion: updatedSuggestion.toJSON()
    }
  });
}));

// Get user statistics
router.get('/stats', asyncHandler(async (req, res) => {
  const userId = req.user.id;

  const [topicStats, suggestionStats] = await Promise.all([
    AnxietyTopic.getUserStats(userId),
    AnxietySuggestion.getUserStats(userId)
  ]);

  res.json({
    success: true,
    data: {
      topics: topicStats,
      suggestions: suggestionStats
    }
  });
}));

module.exports = router;