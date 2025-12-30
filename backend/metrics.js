const client = require('prom-client');

// Create a Registry to register the metrics
const register = new client.Registry();

// Add default metrics (CPU, memory, etc.)
client.collectDefaultMetrics({
    register,
    prefix: 'dhakacart_backend_'
});

// Custom metrics
const httpRequestDuration = new client.Histogram({
    name: 'dhakacart_backend_http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});

const httpRequestsTotal = new client.Counter({
    name: 'dhakacart_backend_http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'status_code']
});

const activeConnections = new client.Gauge({
    name: 'dhakacart_backend_active_connections',
    help: 'Number of active connections'
});

const databaseConnectionsTotal = new client.Gauge({
    name: 'dhakacart_backend_database_connections_total',
    help: 'Total number of database connections'
});

const databaseConnectionsActive = new client.Gauge({
    name: 'dhakacart_backend_database_connections_active',
    help: 'Number of active database connections'
});

const databaseQueryDuration = new client.Histogram({
    name: 'dhakacart_backend_database_query_duration_seconds',
    help: 'Duration of database queries in seconds',
    labelNames: ['query_type'],
    buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 3, 5]
});

const businessMetrics = {
    productsViewed: new client.Counter({
        name: 'dhakacart_backend_products_viewed_total',
        help: 'Total number of product views'
    }),

    apiErrors: new client.Counter({
        name: 'dhakacart_backend_api_errors_total',
        help: 'Total number of API errors',
        labelNames: ['error_type', 'endpoint']
    })
};

// Register all metrics
register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestsTotal);
register.registerMetric(activeConnections);
register.registerMetric(databaseConnectionsTotal);
register.registerMetric(databaseConnectionsActive);
register.registerMetric(databaseQueryDuration);
register.registerMetric(businessMetrics.productsViewed);
register.registerMetric(businessMetrics.apiErrors);

module.exports = {
    register,
    httpRequestDuration,
    httpRequestsTotal,
    activeConnections,
    databaseConnectionsTotal,
    databaseConnectionsActive,
    databaseQueryDuration,
    businessMetrics
};