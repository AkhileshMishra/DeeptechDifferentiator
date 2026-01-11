/**
 * Lambda@Edge Viewer Request Handler
 * Validates JWT tokens from Cognito and handles CORS preflight
 */

const crypto = require('crypto');

// Cognito configuration - will be replaced during deployment
const COGNITO_REGION = '${cognito_region}';
const COGNITO_USER_POOL_ID = '${cognito_user_pool_id}';
const COGNITO_CLIENT_ID = '${cognito_client_id}';

// JWKS cache
let jwksCache = null;
let jwksCacheTime = 0;
const JWKS_CACHE_TTL = 3600000; // 1 hour

// Allowed origins for CORS
const ALLOWED_ORIGINS = [
    /^https:\/\/[a-z0-9]+\.cloudfront\.net$/,
    /^http:\/\/localhost(:\d+)?$/
];

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const headers = request.headers;
    
    // Get origin for CORS
    const origin = headers.origin ? headers.origin[0].value : '*';
    const allowedOrigin = isAllowedOrigin(origin) ? origin : '*';
    
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
        return {
            status: '204',
            statusDescription: 'No Content',
            headers: {
                'access-control-allow-origin': [{ key: 'Access-Control-Allow-Origin', value: allowedOrigin }],
                'access-control-allow-methods': [{ key: 'Access-Control-Allow-Methods', value: 'GET, POST, OPTIONS' }],
                'access-control-allow-headers': [{ key: 'Access-Control-Allow-Headers', value: 'Authorization, Content-Type' }],
                'access-control-max-age': [{ key: 'Access-Control-Max-Age', value: '86400' }]
            }
        };
    }
    
    // Health check bypass
    if (request.uri === '/health') {
        return request;
    }
    
    // Validate JWT token
    const authHeader = headers.authorization ? headers.authorization[0].value : null;
    
    if (!authHeader) {
        return unauthorizedResponse('Missing Authorization header', allowedOrigin);
    }
    
    const token = authHeader.replace(/^Bearer\s+/i, '');
    
    try {
        const decoded = await verifyToken(token);
        
        // Add user info to headers for downstream services
        request.headers['x-user-sub'] = [{ key: 'X-User-Sub', value: decoded.sub }];
        request.headers['x-user-email'] = [{ key: 'X-User-Email', value: decoded.email || '' }];
        
        // Remove Authorization header before forwarding (ALB doesn't need it)
        delete request.headers.authorization;
        
        return request;
        
    } catch (error) {
        console.error('JWT validation error:', error.message);
        return unauthorizedResponse(error.message, allowedOrigin);
    }
};

function isAllowedOrigin(origin) {
    if (!origin) return false;
    return ALLOWED_ORIGINS.some(pattern => pattern.test(origin));
}

function unauthorizedResponse(message, origin) {
    return {
        status: '401',
        statusDescription: 'Unauthorized',
        headers: {
            'content-type': [{ key: 'Content-Type', value: 'application/json' }],
            'access-control-allow-origin': [{ key: 'Access-Control-Allow-Origin', value: origin }]
        },
        body: JSON.stringify({ error: 'Unauthorized', message })
    };
}

async function verifyToken(token) {
    // Decode token header to get key ID
    const [headerB64] = token.split('.');
    const header = JSON.parse(Buffer.from(headerB64, 'base64url').toString());
    
    // Get JWKS
    const jwks = await getJwks();
    const key = jwks.keys.find(k => k.kid === header.kid);
    
    if (!key) {
        throw new Error('Key not found in JWKS');
    }
    
    // Verify signature
    const [, payloadB64, signatureB64] = token.split('.');
    const signatureInput = `${headerB64}.${payloadB64}`;
    const signature = Buffer.from(signatureB64, 'base64url');
    
    const publicKey = jwkToPem(key);
    const isValid = crypto.verify(
        'RSA-SHA256',
        Buffer.from(signatureInput),
        publicKey,
        signature
    );
    
    if (!isValid) {
        throw new Error('Invalid signature');
    }
    
    // Decode and validate payload
    const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString());
    
    // Check expiration
    if (payload.exp && payload.exp < Date.now() / 1000) {
        throw new Error('Token expired');
    }
    
    // Check issuer
    const expectedIssuer = `https://cognito-idp.${COGNITO_REGION}.amazonaws.com/${COGNITO_USER_POOL_ID}`;
    if (payload.iss !== expectedIssuer) {
        throw new Error('Invalid issuer');
    }
    
    // Check audience (for id_token) or client_id (for access_token)
    if (payload.aud && payload.aud !== COGNITO_CLIENT_ID) {
        throw new Error('Invalid audience');
    }
    if (payload.client_id && payload.client_id !== COGNITO_CLIENT_ID) {
        throw new Error('Invalid client_id');
    }
    
    return payload;
}

async function getJwks() {
    const now = Date.now();
    if (jwksCache && (now - jwksCacheTime) < JWKS_CACHE_TTL) {
        return jwksCache;
    }
    
    const jwksUrl = `https://cognito-idp.${COGNITO_REGION}.amazonaws.com/${COGNITO_USER_POOL_ID}/.well-known/jwks.json`;
    
    const response = await fetch(jwksUrl);
    if (!response.ok) {
        throw new Error('Failed to fetch JWKS');
    }
    
    jwksCache = await response.json();
    jwksCacheTime = now;
    return jwksCache;
}

function jwkToPem(jwk) {
    // Convert JWK to PEM format for crypto.verify
    const n = Buffer.from(jwk.n, 'base64url');
    const e = Buffer.from(jwk.e, 'base64url');
    
    // Build DER encoded public key
    const nLen = n.length;
    const eLen = e.length;
    
    // RSA public key structure
    const sequence = Buffer.concat([
        Buffer.from([0x30]), // SEQUENCE
        encodeLength(nLen + eLen + 4 + (n[0] & 0x80 ? 1 : 0) + (e[0] & 0x80 ? 1 : 0)),
        Buffer.from([0x02]), // INTEGER (n)
        encodeLength(nLen + (n[0] & 0x80 ? 1 : 0)),
        n[0] & 0x80 ? Buffer.from([0x00]) : Buffer.alloc(0),
        n,
        Buffer.from([0x02]), // INTEGER (e)
        encodeLength(eLen + (e[0] & 0x80 ? 1 : 0)),
        e[0] & 0x80 ? Buffer.from([0x00]) : Buffer.alloc(0),
        e
    ]);
    
    // Wrap in SubjectPublicKeyInfo
    const algorithmId = Buffer.from([
        0x30, 0x0d, // SEQUENCE
        0x06, 0x09, // OID
        0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, // rsaEncryption
        0x05, 0x00  // NULL
    ]);
    
    const bitString = Buffer.concat([
        Buffer.from([0x03]), // BIT STRING
        encodeLength(sequence.length + 1),
        Buffer.from([0x00]), // unused bits
        sequence
    ]);
    
    const spki = Buffer.concat([
        Buffer.from([0x30]), // SEQUENCE
        encodeLength(algorithmId.length + bitString.length),
        algorithmId,
        bitString
    ]);
    
    const pem = '-----BEGIN PUBLIC KEY-----\n' +
        spki.toString('base64').match(/.{1,64}/g).join('\n') +
        '\n-----END PUBLIC KEY-----';
    
    return pem;
}

function encodeLength(len) {
    if (len < 128) {
        return Buffer.from([len]);
    } else if (len < 256) {
        return Buffer.from([0x81, len]);
    } else {
        return Buffer.from([0x82, (len >> 8) & 0xff, len & 0xff]);
    }
}
