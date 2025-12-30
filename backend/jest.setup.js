// Jest setup file for backend tests
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://dhakacart:secret@localhost:5432/dhakacartdb_test';
process.env.REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
process.env.LOG_LEVEL = 'error'; // Reduce log noise during tests

// Mock external dependencies that might not be available during testing
jest.mock('./database', () => {
    return class MockDatabaseConnectionPool {
        async initialize() {
            return {
                query: jest.fn().mockResolvedValue({ rows: [] }),
                totalCount: 0
            };
        }

        async query(sql, params) {
            // Mock different responses based on query
            if (sql.includes('SELECT * FROM products')) {
                return { rows: [{ id: 1, name: 'Test Product', price: 10.99 }] };
            }
            return { rows: [] };
        }

        async close() {
            return Promise.resolve();
        }
    };
});

jest.mock('./redis', () => {
    return class MockRedisConnectionPool {
        constructor() {
            this.isConnected = false;
        }

        async initialize() {
            return null;
        }

        async getCachedData() {
            return null;
        }

        async setCachedData() {
            return true;
        }

        async disconnect() {
            return Promise.resolve();
        }
    };
});