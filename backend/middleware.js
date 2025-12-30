const { v4: uuidv4 } = require('uuid');
const logger = require('./logger');
const { httpRequestDuration, httpRequestsTotal, activeConnections } = require('./metrics');

// Correlation ID middleware
const correlationIdMiddleware = (req, res, next) => {
    // Get correlation ID from header or generate new one
    const correlationId = req.headers['x-correlation-id'] || uuidv4();

    // Add to request object
    req.correlationId = correlationId;

    // Add to response headers
    res.setHeader('x-correlation-id', correlationId);

    next();
};

// Request logging middleware
const requestLoggingMiddleware = (req, res, next) => {
    const startTime = Date.now();

    // Track active connections
    activeConnections.inc();

    // Log incoming request
    logger.info('Incoming request', {
        correlationId: req.correlationId,
        method: req.method,
        url: req.url,
        userAgent: req.get('User-Agent'),
        ip: req.ip || req.connection.remoteAddress,
        userId: req.user?.id
    });

    // Override res.end to capture response details
    const originalEnd = res.end;
    res.end = function (...args) {
        const responseTime = Date.now() - startTime;
        const statusCode = res.statusCode;

        // Record metrics
        const route = req.route?.path || req.url;
        httpRequestDuration
            .labels(req.method, route, statusCode)
            .observe(responseTime / 1000);

        httpRequestsTotal
            .labels(req.method, route, statusCode)
            .inc();

        activeConnections.dec();

        // Log response
        logger.info('Request completed', {
            correlationId: req.correlationId,
            method: req.method,
            url: req.url,
            statusCode,
            responseTime,
            userId: req.user?.id
        });

        // Call original end method
        originalEnd.apply(this, args);
    };

    next();
};

// Error logging middleware
const errorLoggingMiddleware = (err, req, res, next) => {
    const errorId = uuidv4();

    logger.error('Request error', {
        errorId,
        correlationId: req.correlationId,
        message: err.message,
        stack: err.stack,
        method: req.method,
        url: req.url,
        userId: req.user?.id,
        statusCode: err.status || 500
    });

    // Add error ID to response for tracking
    res.setHeader('x-error-id', errorId);

    // Return sanitized error response
    res.status(err.status || 500).json({
        error: {
            id: errorId,
            message: process.env.NODE_ENV === 'production'
                ? 'Internal server error'
                : err.message,
            correlationId: req.correlationId,
            timestamp: new Date().toISOString()
        }
    });
};

module.exports = {
    correlationIdMiddleware,
    requestLoggingMiddleware,
    errorLoggingMiddleware
};