// Global error handler middleware
const errorHandler = (err, req, res, next) => {
  console.error('Error occurred:', {
    message: err.message,
    stack: err.stack,
    url: req.url,
    method: req.method,
    timestamp: new Date().toISOString()
  });

  // Default error
  let error = {
    status: err.statusCode || 500,
    message: err.message || 'Internal Server Error'
  };

  // Mongoose validation error
  if (err.name === 'ValidationError') {
    const messages = Object.values(err.errors).map(val => val.message);
    error = {
      status: 400,
      message: 'Validation Error',
      details: messages
    };
  }

  // Mongoose duplicate key error
  if (err.code === 11000) {
    const field = Object.keys(err.keyValue)[0];
    error = {
      status: 400,
      message: `${field} already exists`
    };
  }

  // MySQL duplicate entry error
  if (err.code === 'ER_DUP_ENTRY') {
    error = {
      status: 400,
      message: 'Duplicate entry - resource already exists'
    };
  }

  // MySQL foreign key constraint error
  if (err.code === 'ER_NO_REFERENCED_ROW_2') {
    error = {
      status: 400,
      message: 'Referenced resource does not exist'
    };
  }

  // JWT errors
  if (err.name === 'JsonWebTokenError') {
    error = {
      status: 401,
      message: 'Invalid token'
    };
  }

  if (err.name === 'TokenExpiredError') {
    error = {
      status: 401,
      message: 'Token expired'
    };
  }

  // Express validator errors
  if (err.type === 'validation') {
    error = {
      status: 400,
      message: 'Validation failed',
      details: err.errors
    };
  }

  // Don't leak error details in production
  if (process.env.NODE_ENV === 'production' && error.status === 500) {
    error.message = 'Something went wrong';
  }

  res.status(error.status).json({
    error: error.message,
    ...(error.details && { details: error.details }),
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
};

// 404 handler
const notFound = (req, res, next) => {
  const error = new Error(`Route not found - ${req.originalUrl}`);
  error.statusCode = 404;
  next(error);
};

// Async error wrapper
const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};

module.exports = {
  errorHandler,
  notFound,
  asyncHandler
};