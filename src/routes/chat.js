const express = require('express');
const { body, param, query, validationResult } = require('express-validator');
const ChatSession = require('../models/ChatSession');
const ChatMessage = require('../models/ChatMessage');
const AnxietyTopic = require('../models/AnxietyTopic');
const deepseekService = require('../services/deepseekService');
const { asyncHandler } = require('../middleware/errorHandler');

const router = express.Router();

// Validation middleware
const validateChatSession = [
  body('topic_id')
    .isInt({ min: 1 })
    .withMessage('Valid topic_id is required'),
  body('title')
    .isLength({ min: 1, max: 200 })
    .withMessage('Title must be between 1 and 200 characters')
    .trim()
];

const validateMessage = [
  body('content')
    .isLength({ min: 1, max: 2000 })
    .withMessage('Message content must be between 1 and 2000 characters')
    .trim()
];

const validateSessionId = [
  param('sessionId').isInt({ min: 1 }).withMessage('Invalid session ID')
];

const validatePagination = [
  query('limit')
    .optional()
    .isInt({ min: 1, max: 100 })
    .withMessage('Limit must be between 1 and 100'),
  query('offset')
    .optional()
    .isInt({ min: 0 })
    .withMessage('Offset must be non-negative')
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

// Create a new chat session
router.post('/sessions', validateChatSession, handleValidationErrors, asyncHandler(async (req, res) => {
  const { topic_id, title } = req.body;
  const userId = req.user.id;

  // Verify topic exists and belongs to user
  const topic = await AnxietyTopic.findById(topic_id);
  if (!topic) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Topic not found'
    });
  }

  if (topic.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only create sessions for your own topics'
    });
  }

  try {
    const session = await ChatSession.create({
      user_id: userId,
      topic_id,
      title
    });

    const sessionWithTopic = await session.getWithTopic();

    res.status(201).json({
      success: true,
      message: 'Chat session created successfully',
      data: {
        session: sessionWithTopic.toJSON()
      }
    });

  } catch (error) {
    console.error('Session creation error:', error);
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to create chat session'
    });
  }
}));

// Get user's chat sessions
router.get('/sessions', validatePagination, handleValidationErrors, asyncHandler(async (req, res) => {
  const userId = req.user.id;
  const { status, limit = 20, offset = 0 } = req.query;

  const sessions = await ChatSession.findByUserId(userId, {
    status,
    limit: parseInt(limit),
    offset: parseInt(offset)
  });

  // Get sessions with topic information
  const sessionsWithTopics = await Promise.all(
    sessions.map(async (session) => {
      const sessionWithTopic = await session.getWithTopic();
      return sessionWithTopic ? sessionWithTopic.toJSON() : session.toJSON();
    })
  );

  res.json({
    success: true,
    data: {
      sessions: sessionsWithTopics,
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        has_more: sessions.length === parseInt(limit)
      }
    }
  });
}));

// Get specific chat session
router.get('/sessions/:sessionId', validateSessionId, handleValidationErrors, asyncHandler(async (req, res) => {
  const sessionId = parseInt(req.params.sessionId);
  const userId = req.user.id;

  const session = await ChatSession.findById(sessionId);
  
  if (!session) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Chat session not found'
    });
  }

  if (session.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only access your own chat sessions'
    });
  }

  const sessionWithTopic = await session.getWithTopic();

  res.json({
    success: true,
    data: {
      session: sessionWithTopic.toJSON()
    }
  });
}));

// Update chat session
router.put('/sessions/:sessionId', [
  ...validateSessionId,
  body('title').optional().isLength({ min: 1, max: 200 }).trim(),
  body('status').optional().isIn(['active', 'ended', 'archived'])
], handleValidationErrors, asyncHandler(async (req, res) => {
  const sessionId = parseInt(req.params.sessionId);
  const userId = req.user.id;
  const updateData = req.body;

  const session = await ChatSession.findById(sessionId);
  
  if (!session) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Chat session not found'
    });
  }

  if (session.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only update your own chat sessions'
    });
  }

  const updatedSession = await session.update(updateData);
  const sessionWithTopic = await updatedSession.getWithTopic();

  res.json({
    success: true,
    message: 'Chat session updated successfully',
    data: {
      session: sessionWithTopic.toJSON()
    }
  });
}));

// Send message and get AI response
router.post('/sessions/:sessionId/messages', [
  ...validateSessionId,
  ...validateMessage
], handleValidationErrors, asyncHandler(async (req, res) => {
  const sessionId = parseInt(req.params.sessionId);
  const userId = req.user.id;
  const { content } = req.body;

  // Verify session exists and belongs to user
  const session = await ChatSession.findById(sessionId);
  
  if (!session) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Chat session not found'
    });
  }

  if (session.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only send messages to your own chat sessions'
    });
  }

  if (session.status !== 'active') {
    return res.status(400).json({
      error: 'Invalid session state',
      message: 'Cannot send messages to inactive sessions'
    });
  }

  try {
    // Save user message
    const userMessage = await ChatMessage.create({
      session_id: sessionId,
      user_id: userId,
      message_type: 'user',
      content
    });

    // Get conversation context
    const conversationContext = await ChatMessage.getConversationContext(sessionId, 20);

    // Generate AI response
    const aiResponse = await deepseekService.generateChatResponse(conversationContext);

    if (!aiResponse.success) {
      throw new Error('Failed to generate AI response');
    }

    // Save AI message
    const aiMessage = await ChatMessage.create({
      session_id: sessionId,
      user_id: userId,
      message_type: 'assistant',
      content: aiResponse.content,
      metadata: {
        usage: aiResponse.usage,
        model: aiResponse.model
      }
    });

    // Update session last message timestamp
    await session.updateLastMessage();

    res.status(201).json({
      success: true,
      message: 'Messages sent successfully',
      data: {
        user_message: userMessage.toJSON(),
        ai_message: aiMessage.toJSON(),
        usage: aiResponse.usage
      }
    });

  } catch (error) {
    console.error('Chat message error:', error);
    
    if (error.message.includes('DeepSeek')) {
      return res.status(503).json({
        error: 'AI service unavailable',
        message: 'Unable to generate response at this time. Please try again later.'
      });
    }
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to process chat message'
    });
  }
}));

// Get messages for a chat session
router.get('/sessions/:sessionId/messages', [
  ...validateSessionId,
  ...validatePagination
], handleValidationErrors, asyncHandler(async (req, res) => {
  const sessionId = parseInt(req.params.sessionId);
  const userId = req.user.id;
  const { limit = 50, offset = 0 } = req.query;

  // Verify session exists and belongs to user
  const session = await ChatSession.findById(sessionId);
  
  if (!session) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Chat session not found'
    });
  }

  if (session.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only access messages from your own chat sessions'
    });
  }

  const messages = await ChatMessage.findBySessionId(sessionId, {
    limit: parseInt(limit),
    offset: parseInt(offset),
    order: 'ASC' // Chronological order for chat display
  });

  res.json({
    success: true,
    data: {
      messages: messages.map(msg => msg.toJSON()),
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        has_more: messages.length === parseInt(limit)
      }
    }
  });
}));

// Stream chat response (for real-time chat)
router.post('/sessions/:sessionId/stream', [
  ...validateSessionId,
  ...validateMessage
], handleValidationErrors, asyncHandler(async (req, res) => {
  const sessionId = parseInt(req.params.sessionId);
  const userId = req.user.id;
  const { content } = req.body;

  // Verify session exists and belongs to user
  const session = await ChatSession.findById(sessionId);
  
  if (!session) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Chat session not found'
    });
  }

  if (session.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only send messages to your own chat sessions'
    });
  }

  if (session.status !== 'active') {
    return res.status(400).json({
      error: 'Invalid session state',
      message: 'Cannot send messages to inactive sessions'
    });
  }

  try {
    // Save user message
    const userMessage = await ChatMessage.create({
      session_id: sessionId,
      user_id: userId,
      message_type: 'user',
      content
    });

    // Set up Server-Sent Events
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Cache-Control'
    });

    // Send user message confirmation
    res.write(`data: ${JSON.stringify({
      type: 'user_message',
      data: userMessage.toJSON()
    })}\n\n`);

    // Get conversation context
    const conversationContext = await ChatMessage.getConversationContext(sessionId, 20);

    // Stream AI response
    let aiResponseContent = '';
    
    await deepseekService.streamChatResponse(conversationContext, (chunk) => {
      if (chunk.type === 'content') {
        aiResponseContent += chunk.content;
        res.write(`data: ${JSON.stringify({
          type: 'ai_chunk',
          content: chunk.content
        })}\n\n`);
      } else if (chunk.type === 'done') {
        // Save complete AI message
        ChatMessage.create({
          session_id: sessionId,
          user_id: userId,
          message_type: 'assistant',
          content: aiResponseContent,
          metadata: {
            usage: chunk.usage,
            model: chunk.model
          }
        }).then(aiMessage => {
          // Update session last message timestamp
          session.updateLastMessage();
          
          res.write(`data: ${JSON.stringify({
            type: 'ai_complete',
            data: aiMessage.toJSON(),
            usage: chunk.usage
          })}\n\n`);
          
          res.write('data: [DONE]\n\n');
          res.end();
        });
      } else if (chunk.type === 'error') {
        res.write(`data: ${JSON.stringify({
          type: 'error',
          error: chunk.error
        })}\n\n`);
        res.end();
      }
    });

  } catch (error) {
    console.error('Stream chat error:', error);
    res.write(`data: ${JSON.stringify({
      type: 'error',
      error: 'Failed to process chat message'
    })}\n\n`);
    res.end();
  }
}));

// Search messages
router.get('/messages/search', [
  query('q').isLength({ min: 1 }).withMessage('Search query is required'),
  ...validatePagination
], handleValidationErrors, asyncHandler(async (req, res) => {
  const userId = req.user.id;
  const { q: searchTerm, limit = 20, offset = 0 } = req.query;

  const messages = await ChatMessage.search(userId, searchTerm, {
    limit: parseInt(limit),
    offset: parseInt(offset)
  });

  res.json({
    success: true,
    data: {
      messages: messages.map(msg => msg.toJSON()),
      search_term: searchTerm,
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        has_more: messages.length === parseInt(limit)
      }
    }
  });
}));

// Get chat statistics
router.get('/stats', asyncHandler(async (req, res) => {
  const userId = req.user.id;

  const [sessionStats, messageStats] = await Promise.all([
    ChatSession.getUserStats(userId),
    ChatMessage.getUserStats(userId)
  ]);

  res.json({
    success: true,
    data: {
      sessions: sessionStats,
      messages: messageStats
    }
  });
}));

// Archive chat session
router.post('/sessions/:sessionId/archive', validateSessionId, handleValidationErrors, asyncHandler(async (req, res) => {
  const sessionId = parseInt(req.params.sessionId);
  const userId = req.user.id;

  const session = await ChatSession.findById(sessionId);
  
  if (!session) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Chat session not found'
    });
  }

  if (session.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only archive your own chat sessions'
    });
  }

  const archivedSession = await session.archive();

  res.json({
    success: true,
    message: 'Chat session archived successfully',
    data: {
      session: archivedSession.toJSON()
    }
  });
}));

// End chat session
router.post('/sessions/:sessionId/end', validateSessionId, handleValidationErrors, asyncHandler(async (req, res) => {
  const sessionId = parseInt(req.params.sessionId);
  const userId = req.user.id;

  const session = await ChatSession.findById(sessionId);
  
  if (!session) {
    return res.status(404).json({
      error: 'Not found',
      message: 'Chat session not found'
    });
  }

  if (session.user_id !== userId) {
    return res.status(403).json({
      error: 'Access denied',
      message: 'You can only end your own chat sessions'
    });
  }

  const endedSession = await session.end();

  res.json({
    success: true,
    message: 'Chat session ended successfully',
    data: {
      session: endedSession.toJSON()
    }
  });
}));

module.exports = router;