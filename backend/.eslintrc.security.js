module.exports = {
    extends: [
        './.eslintrc.js'
    ],
    plugins: [
        'security',
        'no-secrets'
    ],
    rules: {
        // Security plugin rules
        'security/detect-buffer-noassert': 'error',
        'security/detect-child-process': 'warn',
        'security/detect-disable-mustache-escape': 'error',
        'security/detect-eval-with-expression': 'error',
        'security/detect-new-buffer': 'error',
        'security/detect-no-csrf-before-method-override': 'error',
        'security/detect-non-literal-fs-filename': 'warn',
        'security/detect-non-literal-regexp': 'warn',
        'security/detect-non-literal-require': 'warn',
        'security/detect-object-injection': 'warn',
        'security/detect-possible-timing-attacks': 'warn',
        'security/detect-pseudoRandomBytes': 'error',
        'security/detect-unsafe-regex': 'error',

        // No secrets plugin rules
        'no-secrets/no-secrets': ['error', {
            'tolerance': 4.2,
            'ignoreContent': [
                'test',
                'spec',
                'example',
                'sample',
                'demo',
                'localhost',
                '127.0.0.1',
                'password',
                'secret',
                'token'
            ],
            'ignoreModules': true,
            'ignoreIdentifiers': [
                'password',
                'secret',
                'token',
                'key',
                'api_key',
                'apikey',
                'access_token'
            ]
        }],

        // Additional security-focused rules
        'no-eval': 'error',
        'no-implied-eval': 'error',
        'no-new-func': 'error',
        'no-script-url': 'error',
        'strict': ['error', 'global']
    },
    env: {
        node: true,
        es2021: true,
        jest: true
    }
};