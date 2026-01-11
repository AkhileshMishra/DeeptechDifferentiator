/**
 * Lambda@Edge Viewer Request Handler
 * Handles CORS preflight OPTIONS requests
 */

const PREFLIGHT_RESPONSE = {
    status: '204',
    statusDescription: 'No Content',
    headers: {
        'access-control-allow-origin': [{ key: 'Access-Control-Allow-Origin', value: '*' }],
        'access-control-allow-methods': [{ key: 'Access-Control-Allow-Methods', value: 'GET, POST, OPTIONS' }],
        'access-control-allow-headers': [{ key: 'Access-Control-Allow-Headers', value: '*' }],
        'access-control-max-age': [{ key: 'Access-Control-Max-Age', value: '86400' }]
    }
};

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    
    // Handle CORS preflight - return immediately without going to origin
    if (request.method === 'OPTIONS') {
        return PREFLIGHT_RESPONSE;
    }
    
    // For other requests, continue to origin
    return request;
};
