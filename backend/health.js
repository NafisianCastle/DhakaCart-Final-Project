const logger = require('./logger');

class HealthChecker {
    constructor(pool, redisClient = null) {
        this.pool = pool;
        this.redisClient = redisClient;
        this.startTime = Date.now();
        this.isShuttingDown = false;
    }

    setShuttingDown(status) {
        this.isShuttingDown = status;
    }

    async checkDatabase() {
        const startTime = Date.now();
        try {
            const result = await this.pool.query('SELECT 1 as health_check, NOW() as timestamp');
            const responseTime = Date.now() - startTime;

            return {
                status: 'healthy',
                responseTime,
                details: {
                    query: 'SELECT 1',
                    timestamp: result.rows[0].timestamp,
                    totalConnections: this.pool.totalCount,
                    idleConnections: this.pool.idleCount,
                    waitingClients: this.pool.waitingCount
                }
            };
        } catch (error) {
            const responseTime = Date.now() - startTime;
            logger.error('Database health check failed', {
                error: error.message,
                responseTime
            });

            return {
                status: 'unhealthy',
                responseTime,
                error: error.message,
                details: {
                    totalConnections: this.pool.totalCount,
                    idleConnections: this.pool.idleCount,
                    waitingClients: this.pool.waitingCount
                }
            };
        }
    }

    async checkRedis() {
        if (!this.redisClient) {
            return {
                status: 'not_configured',
                message: 'Redis client not configured'
            };
        }

        const startTime = Date.now();
        try {
            const testKey = `health_check_${Date.now()}`;
            const testValue = 'ok';

            // Test write
            await this.redisClient.set(testKey, testValue, { EX: 10 });

            // Test read
            const result = await this.redisClient.get(testKey);

            // Cleanup
            await this.redisClient.del(testKey);

            const responseTime = Date.now() - startTime;

            if (result === testValue) {
                return {
                    status: 'healthy',
                    responseTime,
                    details: {
                        operation: 'set/get/del',
                        connected: this.redisClient.isReady
                    }
                };
            } else {
                return {
                    status: 'unhealthy',
                    responseTime,
                    error: 'Redis read/write test failed',
                    details: {
                        expected: testValue,
                        received: result,
                        connected: this.redisClient.isReady
                    }
                };
            }
        } catch (error) {
            const responseTime = Date.now() - startTime;
            logger.error('Redis health check failed', {
                error: error.message,
                responseTime
            });

            return {
                status: 'unhealthy',
                responseTime,
                error: error.message,
                details: {
                    connected: this.redisClient?.isReady || false
                }
            };
        }
    }

    async checkMemory() {
        const memUsage = process.memoryUsage();
        const totalMemory = memUsage.rss + memUsage.heapUsed + memUsage.external;
        const memoryLimitMB = parseInt(process.env.MEMORY_LIMIT_MB) || 512;
        const memoryUsagePercent = (totalMemory / (memoryLimitMB * 1024 * 1024)) * 100;

        return {
            status: memoryUsagePercent > 90 ? 'unhealthy' : 'healthy',
            details: {
                rss: Math.round(memUsage.rss / 1024 / 1024),
                heapTotal: Math.round(memUsage.heapTotal / 1024 / 1024),
                heapUsed: Math.round(memUsage.heapUsed / 1024 / 1024),
                external: Math.round(memUsage.external / 1024 / 1024),
                arrayBuffers: Math.round(memUsage.arrayBuffers / 1024 / 1024),
                totalMB: Math.round(totalMemory / 1024 / 1024),
                limitMB: memoryLimitMB,
                usagePercent: Math.round(memoryUsagePercent * 100) / 100
            }
        };
    }

    getUptime() {
        const uptimeMs = Date.now() - this.startTime;
        const uptimeSeconds = Math.floor(uptimeMs / 1000);
        const uptimeMinutes = Math.floor(uptimeSeconds / 60);
        const uptimeHours = Math.floor(uptimeMinutes / 60);

        return {
            milliseconds: uptimeMs,
            seconds: uptimeSeconds,
            minutes: uptimeMinutes,
            hours: uptimeHours,
            formatted: `${uptimeHours}h ${uptimeMinutes % 60}m ${uptimeSeconds % 60}s`
        };
    }

    async performHealthCheck() {
        const startTime = Date.now();

        try {
            const [dbHealth, redisHealth, memoryHealth] = await Promise.all([
                this.checkDatabase(),
                this.checkRedis(),
                Promise.resolve(this.checkMemory())
            ]);

            const overallStatus = this.determineOverallStatus([
                dbHealth.status,
                redisHealth.status === 'not_configured' ? 'healthy' : redisHealth.status,
                memoryHealth.status
            ]);

            const totalResponseTime = Date.now() - startTime;

            return {
                status: overallStatus,
                timestamp: new Date().toISOString(),
                uptime: this.getUptime(),
                responseTime: totalResponseTime,
                version: process.env.npm_package_version || '1.0.0',
                environment: process.env.NODE_ENV || 'development',
                checks: {
                    database: dbHealth,
                    redis: redisHealth,
                    memory: memoryHealth
                }
            };
        } catch (error) {
            logger.error('Health check failed', { error: error.message });

            return {
                status: 'unhealthy',
                timestamp: new Date().toISOString(),
                uptime: this.getUptime(),
                responseTime: Date.now() - startTime,
                error: error.message,
                version: process.env.npm_package_version || '1.0.0',
                environment: process.env.NODE_ENV || 'development'
            };
        }
    }

    async performReadinessCheck() {
        // Readiness check is simpler - just check if we can accept traffic
        if (this.isShuttingDown) {
            return {
                status: 'not_ready',
                reason: 'Application is shutting down',
                timestamp: new Date().toISOString()
            };
        }

        try {
            // Quick database connectivity check
            const dbResult = await this.pool.query('SELECT 1');

            return {
                status: 'ready',
                timestamp: new Date().toISOString(),
                checks: {
                    database: 'connected',
                    shutdown: 'false'
                }
            };
        } catch (error) {
            logger.error('Readiness check failed', { error: error.message });

            return {
                status: 'not_ready',
                reason: 'Database connection failed',
                timestamp: new Date().toISOString(),
                error: error.message
            };
        }
    }

    determineOverallStatus(statuses) {
        if (statuses.includes('unhealthy')) {
            return 'unhealthy';
        }
        if (statuses.every(status => status === 'healthy')) {
            return 'healthy';
        }
        return 'degraded';
    }
}

module.exports = HealthChecker;