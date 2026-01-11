/**
 * Lambda@Edge Viewer Request Handler
 * Handles CORS preflight OPTIONS requests
 */

// Allowed origins for CORS
const ALLOWED_ORIGINS = [
    /^https:\/\/[a-z0-9]+\.cloudfront\.net$/,  // Any CloudFront distribution
    /^http:\/\/localhost(:\d+)?$/,              // localhost with any port
    /^http:\/\/127\.0\.0\.1(:\d+)?$/            // 127.0.0.1 with any port
];

function isAllowedOrigin(origin) {
    if (!origin) return false;
    return ALLOWED_ORIGINS.some(pattern => pattern.test(origin));
}

function getOriginHeader(request) {
    const originHeader = request.headers['origin'];
    if (originHeader && originHeader.length > 0) {
        return originHeader[0].value;
    }
    return null;
}

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const origin = getOriginHeader(request);
    
    // Determine the allowed origin to return
    const allowedOrigin = (origin && isAllowedOrigin(origin)) ? origin : '*';
    
    // Handle CORS preflight - return immediately without going to origin
    if (request.method === 'OPTIONS') {
        return {
            status: '204',
            statusDescription: 'No Content',
            headers: {
                'access-control-allow-origin': [{ key: 'Access-Control-Allow-Origin', value: allowedOrigin }],
                'access-control-allow-methods': [{ key: 'Access-Control-Allow-Methods', value: 'GET, POST, OPTIONS, HEAD' }],
                'access-control-allow-headers': [{ key: 'Access-Control-Allow-Headers', value: 'Authorization, Content-Type, X-Amz-Date, X-Amz-Security-Token, Accept' }],
                'access-control-max-age': [{ key: 'Access-Control-Max-Age', value: '86400' }],
                'access-control-expose-headers': [{ key: 'Access-Control-Expose-Headers', value: 'Content-Length, Content-Type' }]
            }
        };
    }
    
    // For other requests, continue to origin
    return request;
};
