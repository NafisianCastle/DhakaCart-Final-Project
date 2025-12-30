const express = require("express");
const { Pool } = require("pg");
const { createClient } = require('redis');
const rateLimit = require("express-rate-limit");
const logger = require('./logger');
const { register, databaseConnectionsTotal, databaseConnectionsActive, databaseQueryDuration, businessMetrics } = require('./metrics');
const { correlationIdMiddleware, requestLoggingMiddleware, errorLoggingMiddleware } = require('./middleware');
const HealthChecker = require('./health');
require("dotenv").config();

const app = express();

// Middleware setup
app.use(express.json());
app.use(correlationIdMiddleware);
app.use(requestLoggingMiddleware);

// Database connection with metrics
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Redis connection (optional)
let redisClient = null;
if (process.env.REDIS_URL || process.env.REDIS_HOST) {
  const redisConfig = process.env.REDIS_URL ?
    { url: process.env.REDIS_URL } :
    {
      host: process.env.REDIS_HOST || 'localhost',
      port: process.env.REDIS_PORT || 6379,
      password: process.env.REDIS_PASSWORD
    };

  redisClient = createClient(redisConfig);

  redisClient.on('error', (err) => {
    logger.error('Redis client error', { error: err.message });
  });

  redisClient.on('connect', () => {
    logger.info('Redis client connected');
  });

  redisClient.on('ready', () => {
    logger.info('Redis client ready');
  });

  redisClient.on('end', () => {
    logger.info('Redis client disconnected');
  });

  // Connect to Redis
  redisClient.connect().catch((err) => {
    logger.error('Failed to connect to Redis', { error: err.message });
    redisClient = null; // Disable Redis if connection fails
  });
}

// Initialize health checker
const healthChecker = new HealthChecker(pool, redisClient);

// Monitor database connection pool
pool.on('connect', () => {
  databaseConnectionsActive.inc();
  logger.debug('Database connection established');
});

pool.on('remove', () => {
  databaseConnectionsActive.dec();
  logger.debug('Database connection removed');
});

pool.on('error', (err) => {
  logger.error('Database pool error', { error: err.message });
  businessMetrics.apiErrors.labels('database_error', 'pool').inc();
});

// Update total connections metric
setInterval(() => {
  databaseConnectionsTotal.set(pool.totalCount);
}, 5000);

// Rate limiting
const productsLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs for /products
});

const healthLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 60, // limit each IP to 60 health check requests per minute
});

// Metrics endpoint
app.get("/metrics", async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (err) {
    logger.error('Error generating metrics', {
      correlationId: req.correlationId,
      error: err.message
    });
    res.status(500).end(err);
  }
});

// Comprehensive health check endpoint
app.get("/health", healthLimiter, async (req, res) => {
  try {
    const healthResult = await healthChecker.performHealthCheck();

    const statusCode = healthResult.status === 'healthy' ? 200 :
      healthResult.status === 'degraded' ? 200 : 503;

    logger.info('Health check completed', {
      correlationId: req.correlationId,
      status: healthResult.status,
      responseTime: healthResult.responseTime
    });

    res.status(statusCode).json({
      ...healthResult,
      correlationId: req.correlationId
    });
  } catch (err) {
    logger.error('Health check failed', {
      correlationId: req.correlationId,
      error: err.message
    });

    res.status(503).json({
      status: "unhealthy",
      error: "Health check failed",
      timestamp: new Date().toISOString(),
      correlationId: req.correlationId
    });
  }
});

// Kubernetes readiness probe endpoint
app.get("/ready", async (req, res) => {
  try {
    const readinessResult = await healthChecker.performReadinessCheck();

    const statusCode = readinessResult.status === 'ready' ? 200 : 503;

    logger.debug('Readiness check completed', {
      correlationId: req.correlationId,
      status: readinessResult.status
    });

    res.status(statusCode).json({
      ...readinessResult,
      correlationId: req.correlationId
    });
  } catch (err) {
    logger.error('Readiness check failed', {
      correlationId: req.correlationId,
      error: err.message
    });

    res.status(503).json({
      status: "not_ready",
      reason: "Readiness check failed",
      timestamp: new Date().toISOString(),
      correlationId: req.correlationId
    });
  }
});

// Kubernetes liveness probe endpoint (simple)
app.get("/live", (req, res) => {
  res.status(200).json({
    status: "alive",
    timestamp: new Date().toISOString(),
    correlationId: req.correlationId
  });
});

// Products endpoint with enhanced logging and metrics
app.get("/products", productsLimiter, async (req, res) => {
  const startTime = Date.now();

  try {
    logger.info('Fetching products', {
      correlationId: req.correlationId,
      userId: req.user?.id
    });

    const result = await pool.query("SELECT * FROM products");
    const queryTime = Date.now() - startTime;

    databaseQueryDuration.labels('select_products').observe(queryTime / 1000);
    businessMetrics.productsViewed.inc();

    logger.info('Products fetched successfully', {
      correlationId: req.correlationId,
      productCount: result.rows.length,
      dbResponseTime: queryTime,
      userId: req.user?.id
    });

    res.json({
      data: result.rows,
      count: result.rows.length,
      timestamp: new Date().toISOString(),
      correlationId: req.correlationId
    });
  } catch (err) {
    const queryTime = Date.now() - startTime;

    databaseQueryDuration.labels('select_products').observe(queryTime / 1000);
    businessMetrics.apiErrors.labels('database_error', '/products').inc();

    logger.error('Error fetching products', {
      correlationId: req.correlationId,
      error: err.message,
      dbResponseTime: queryTime,
      userId: req.user?.id
    });

    throw err; // Let error middleware handle it
  }
});

// Error handling middleware (must be last)
app.use(errorLoggingMiddleware);

const server = app.listen(5000, () => {
  logger.info("Backend server started", {
    port: 5000,
    environment: process.env.NODE_ENV || 'development',
    nodeVersion: process.version,
    redisEnabled: !!redisClient
  });
});

// Graceful shutdown handling
let isShuttingDown = false;

const gracefulShutdown = (signal) => {
  logger.info(`Received ${signal}. Starting graceful shutdown...`);

  if (isShuttingDown) {
    logger.warn('Shutdown already in progress...');
    return;
  }

  isShuttingDown = true;
  healthChecker.setShuttingDown(true);

  // Stop accepting new connections
  server.close((err) => {
    if (err) {
      logger.error('Error during server shutdown', { error: err.message });
      process.exit(1);
    }

    logger.info('HTTP server closed');

    // Close database connections
    const dbClosePromise = new Promise((resolve) => {
      pool.end(() => {
        logger.info('Database connections closed');
        resolve();
      });
    });

    // Close Redis connection
    const redisClosePromise = redisClient ?
      redisClient.quit().then(() => {
        logger.info('Redis connection closed');
      }).catch((err) => {
        logger.warn('Error closing Redis connection', { error: err.message });
      }) :
      Promise.resolve();

    Promise.all([dbClosePromise, redisClosePromise]).then(() => {
      logger.info('Graceful shutdown completed');
      process.exit(0);
    });
  });

  // Force shutdown after 30 seconds
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 30000);
};

// Handle shutdown signals
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
  logger.error('Uncaught exception', {
    error: err.message,
    stack: err.stack
  });
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled rejection', {
    reason: reason?.message || reason,
    promise: promise.toString()
  });
  process.exit(1);
});