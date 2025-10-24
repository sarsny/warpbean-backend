const express = require('express');
const { body, validationResult } = require('express-validator');
const User = require('../models/User');
const { generateToken, authenticateToken, refreshToken } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errorHandler');

const router = express.Router();

// Validation middleware
const validateRegistration = [
  body('username')
    .isLength({ min: 3, max: 50 })
    .withMessage('Username must be between 3 and 50 characters')
    .matches(/^[a-zA-Z0-9_]+$/)
    .withMessage('Username can only contain letters, numbers, and underscores'),
  body('email')
    .isEmail()
    .withMessage('Please provide a valid email')
    .normalizeEmail(),
  body('password')
    .isLength({ min: 6 })
    .withMessage('Password must be at least 6 characters long')
    .matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .withMessage('Password must contain at least one lowercase letter, one uppercase letter, and one number'),
  body('full_name')
    .optional()
    .isLength({ min: 1, max: 100 })
    .withMessage('Full name must be between 1 and 100 characters')
];

const validateLogin = [
  body('username')
    .notEmpty()
    .withMessage('Username is required'),
  body('password')
    .notEmpty()
    .withMessage('Password is required')
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

// Register new user
router.post('/register', validateRegistration, handleValidationErrors, asyncHandler(async (req, res) => {
  const { username, email, password, full_name } = req.body;

  // Check if username already exists
  if (await User.usernameExists(username)) {
    return res.status(400).json({
      error: 'Registration failed',
      message: 'Username already exists'
    });
  }

  // Check if email already exists
  if (await User.emailExists(email)) {
    return res.status(400).json({
      error: 'Registration failed',
      message: 'Email already exists'
    });
  }

  // Create new user
  const user = await User.create({
    username,
    email,
    password,
    full_name
  });

  // Generate token
  const token = generateToken(user);

  res.status(201).json({
    success: true,
    message: 'User registered successfully',
    token,
    user: user.toPublicJSON()
  });
}));

// Login user
router.post('/login', validateLogin, handleValidationErrors, asyncHandler(async (req, res) => {
  const { username, password } = req.body;

  // Find user by username
  const user = await User.findByUsername(username);
  if (!user) {
    return res.status(401).json({
      error: 'Authentication failed',
      message: 'Invalid username or password'
    });
  }

  // Verify password
  const isPasswordValid = await user.verifyPassword(password);
  if (!isPasswordValid) {
    return res.status(401).json({
      error: 'Authentication failed',
      message: 'Invalid username or password'
    });
  }

  // Update last login
  await user.updateLastLogin();

  // Generate token
  const token = generateToken(user);

  res.json({
    success: true,
    message: 'Login successful',
    token,
    user: user.toPublicJSON()
  });
}));

// Get current user profile
router.get('/profile', authenticateToken, asyncHandler(async (req, res) => {
  res.json({
    success: true,
    user: req.user.toPublicJSON()
  });
}));

// Update user profile
router.put('/profile', authenticateToken, [
  body('full_name')
    .optional()
    .isLength({ min: 1, max: 100 })
    .withMessage('Full name must be between 1 and 100 characters'),
  body('avatar_url')
    .optional()
    .isURL()
    .withMessage('Avatar URL must be a valid URL')
], handleValidationErrors, asyncHandler(async (req, res) => {
  const { full_name, avatar_url } = req.body;

  const updatedUser = await req.user.update({
    full_name,
    avatar_url
  });

  res.json({
    success: true,
    message: 'Profile updated successfully',
    user: updatedUser.toPublicJSON()
  });
}));

// Refresh token
router.post('/refresh', authenticateToken, refreshToken);

// Logout (client-side token removal)
router.post('/logout', authenticateToken, asyncHandler(async (req, res) => {
  // In a more sophisticated setup, you might want to blacklist the token
  // For now, we'll just return a success message
  res.json({
    success: true,
    message: 'Logout successful'
  });
}));

// Check if username is available
router.get('/check-username/:username', asyncHandler(async (req, res) => {
  const { username } = req.params;
  
  if (username.length < 3 || username.length > 50) {
    return res.status(400).json({
      error: 'Invalid username',
      message: 'Username must be between 3 and 50 characters'
    });
  }

  const exists = await User.usernameExists(username);
  
  res.json({
    available: !exists,
    username
  });
}));

// Check if email is available
router.get('/check-email/:email', asyncHandler(async (req, res) => {
  const { email } = req.params;
  
  // Basic email validation
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    return res.status(400).json({
      error: 'Invalid email',
      message: 'Please provide a valid email address'
    });
  }

  const exists = await User.emailExists(email);
  
  res.json({
    available: !exists,
    email
  });
}));

module.exports = router;