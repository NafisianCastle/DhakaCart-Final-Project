const winston = require('winston');

// Custom format for structured logging
const logFormat = winston.format.combine(
    winston.format.timestamp({
        format: 'YYYY-MM-DD HH:mm:ss'
    }),
    winston.format.errors({ stack: true }),
    winston.format.json(),
    winston.format.printf(({ timestamp, level, message, correlationId, userId, method, url, statusCode, responseTime, ...meta }) => {
        const logEntry = {
            timestamp,
            level,
            message,
            service: 'dhakacart-backend',
            environment: process.env.NODE_ENV || 'development',
            ...(correlationId && { correlationId }),
            ...(userId && { userId }),
            ...(method && { method }),
            ...(url && { url }),
            ...(statusCode && { statusCode }),
            ...(responseTime && { responseTime }),
            ...meta
        };

        return JSON.stringify(logEntry);
    })
);

// Create logger instance
const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: logFormat,
    defaultMeta: {
        service: 'dhakacart-backend'
    },
    transports: [
        // Console transport for development
        new winston.transports.Console({
            format: process.env.NODE_ENV === 'production'
                ? logFormat
                : winston.format.combine(
                    winston.format.colorize(),
                    winston.format.simple()
                )
        })
    ]
});

// Add file transport for production
if (process.env.NODE_ENV === 'production') {
    logger.add(new winston.transports.File({
        filename: '/var/log/app/error.log',
        level: 'error',
        maxsize: 5242880, // 5MB
        maxFiles: 5
    }));

    logger.add(new winston.transports.File({
        filename: '/var/log/app/combined.log',
        maxsize: 5242880, // 5MB
        maxFiles: 5
    }));
}

module.exports = logger;