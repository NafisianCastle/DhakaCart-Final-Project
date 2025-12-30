const request = require('supertest');
const app = require('../index');

describe('Health Endpoints', () => {
    test('GET /health should return 200', async () => {
        const response = await request(app)
            .get('/health')
            .expect(200);

        expect(response.body).toHaveProperty('status', 'healthy');
        expect(response.body).toHaveProperty('timestamp');
    });

    test('GET /ready should return 200', async () => {
        const response = await request(app)
            .get('/ready')
            .expect(200);

        expect(response.body).toHaveProperty('status', 'ready');
    });

    test('GET /metrics should return prometheus metrics', async () => {
        const response = await request(app)
            .get('/metrics')
            .expect(200);

        expect(response.text).toContain('# HELP');
        expect(response.headers['content-type']).toMatch(/text\/plain/);
    });
});

describe('API Endpoints', () => {
    test('GET /api/products should return products array', async () => {
        const response = await request(app)
            .get('/api/products')
            .expect(200);

        expect(Array.isArray(response.body)).toBe(true);
    });

    test('GET /api/products/:id should return 404 for non-existent product', async () => {
        await request(app)
            .get('/api/products/99999')
            .expect(404);
    });
});