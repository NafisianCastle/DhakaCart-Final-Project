import React, { useEffect, useState } from 'react';
import logo from './logo.svg';
import './App.css';
import logger from './logger';
import apiClient from './api';

function App() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    logger.info('App component mounted', {
      timestamp: new Date().toISOString(),
      userAgent: navigator.userAgent
    });

    // Load products on component mount
    loadProducts();
  }, []);

  const loadProducts = async () => {
    setLoading(true);
    setError(null);

    try {
      logger.info('Loading products');
      const response = await apiClient.get('/products');

      setProducts(response.data.data || []);

      logger.info('Products loaded successfully', {
        productCount: response.data.count,
        correlationId: response.correlationId
      });
    } catch (err) {
      const errorMessage = 'Failed to load products';
      setError(errorMessage);

      logger.error(errorMessage, {
        error: err.message,
        stack: err.stack
      });
    } finally {
      setLoading(false);
    }
  };

  const handleRefresh = () => {
    logger.info('User requested products refresh');
    loadProducts();
  };

  return (
    <div className="App">
      <header className="App-header">
        <img src={logo} className="App-logo" alt="logo" />
        <h1>DhakaCart</h1>

        <div style={{ margin: '20px 0' }}>
          <button
            onClick={handleRefresh}
            disabled={loading}
            style={{
              padding: '10px 20px',
              fontSize: '16px',
              backgroundColor: '#61dafb',
              border: 'none',
              borderRadius: '5px',
              cursor: loading ? 'not-allowed' : 'pointer'
            }}
          >
            {loading ? 'Loading...' : 'Load Products'}
          </button>
        </div>

        {error && (
          <div style={{
            color: '#ff6b6b',
            margin: '10px 0',
            padding: '10px',
            border: '1px solid #ff6b6b',
            borderRadius: '5px',
            backgroundColor: 'rgba(255, 107, 107, 0.1)'
          }}>
            Error: {error}
          </div>
        )}

        {products.length > 0 && (
          <div style={{ margin: '20px 0' }}>
            <h2>Products ({products.length})</h2>
            <div style={{
              display: 'grid',
              gap: '10px',
              maxWidth: '600px',
              textAlign: 'left'
            }}>
              {products.map((product) => (
                <div
                  key={product.id}
                  style={{
                    padding: '10px',
                    border: '1px solid #ccc',
                    borderRadius: '5px',
                    backgroundColor: 'rgba(255, 255, 255, 0.1)'
                  }}
                >
                  <strong>{product.name}</strong> - ${product.price}
                </div>
              ))}
            </div>
          </div>
        )}

        <p style={{ fontSize: '14px', opacity: 0.7 }}>
          Session ID: {logger.sessionId}
        </p>
      </header>
    </div>
  );
}

export default App;

export default App;
