/**
 * HealthImaging Proxy Server
 * 
 * Converts GET requests (for CloudFront caching) to POST requests
 * and signs them with SigV4 for AWS HealthImaging API.
 * 
 * Architecture: CloudFront → ALB → This Container → HealthImaging API
 */

const http = require('http');
const https = require('https');
const crypto = require('crypto');

const PORT = process.env.PORT || 8080;
const REGION = process.env.AWS_REGION || 'us-east-1';
const HEALTHIMAGING_HOST = `runtime-medical-imaging.${REGION}.amazonaws.com`;

// Create server
const server = http.createServer(async (req, res) => {
    // Health check endpoint
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'healthy' }));
        return;
    }

    // CORS preflight
    if (req.method === 'OPTIONS') {
        res.writeHead(204, {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '86400'
        });
        res.end();
        return;
    }

    try {
        await handleProxyRequest(req, res);
    } catch (error) {
        console.error('Proxy error:', error);
        res.writeHead(500, { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        });
        res.end(JSON.stringify({ error: error.message }));
    }
});

async function handleProxyRequest(req, res) {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const path = url.pathname;
    
    // Check if this is a getImageFrame request
    const isGetImageFrame = path.includes('/getImageFrame');
    
    let method = req.method;
    let body = '';
    
    if (isGetImageFrame && req.method === 'GET') {
        // Convert GET to POST for HealthImaging API
        method = 'POST';
        const imageFrameId = url.searchParams.get('imageFrameId');
        if (!imageFrameId) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Missing imageFrameId parameter' }));
            return;
        }
        body = JSON.stringify({ imageFrameId });
    } else if (req.method === 'POST') {
        // Read POST body
        body = await readBody(req);
    }

    // Get credentials from environment (ECS task role)
    const credentials = {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
        sessionToken: process.env.AWS_SESSION_TOKEN
    };

    // Sign the request
    const signedHeaders = signRequest({
        method,
        host: HEALTHIMAGING_HOST,
        path: path,
        body,
        credentials,
        region: REGION,
        service: 'medical-imaging'
    });

    // Make request to HealthImaging
    const options = {
        hostname: HEALTHIMAGING_HOST,
        port: 443,
        path: path,
        method: method,
        headers: {
            'Host': HEALTHIMAGING_HOST,
            'Content-Type': 'application/json',
            'X-Amz-Date': signedHeaders['x-amz-date'],
            'X-Amz-Content-Sha256': signedHeaders['x-amz-content-sha256'],
            'Authorization': signedHeaders['authorization'],
            ...(credentials.sessionToken && { 'X-Amz-Security-Token': credentials.sessionToken })
        }
    };

    const proxyReq = https.request(options, (proxyRes) => {
        // Forward response headers with CORS
        const responseHeaders = {
            ...proxyRes.headers,
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Expose-Headers': 'Content-Length, Content-Type'
        };
        
        res.writeHead(proxyRes.statusCode, responseHeaders);
        proxyRes.pipe(res);
    });

    proxyReq.on('error', (error) => {
        console.error('HealthImaging request error:', error);
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Failed to connect to HealthImaging' }));
    });

    if (body) {
        proxyReq.write(body);
    }
    proxyReq.end();
}

function readBody(req) {
    return new Promise((resolve, reject) => {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => resolve(body));
        req.on('error', reject);
    });
}

/**
 * Sign an AWS request using SigV4
 */
function signRequest({ method, host, path, body, credentials, region, service }) {
    const datetime = new Date().toISOString().replace(/[:-]|\.\d{3}/g, '');
    const date = datetime.substring(0, 8);
    
    const bodyHash = sha256(body || '');
    
    const headersList = [
        ['host', host],
        ['x-amz-content-sha256', bodyHash],
        ['x-amz-date', datetime]
    ];
    
    if (credentials.sessionToken) {
        headersList.push(['x-amz-security-token', credentials.sessionToken]);
    }
    
    headersList.sort((a, b) => a[0].localeCompare(b[0]));
    
    const canonicalHeaders = headersList.map(h => `${h[0]}:${h[1]}`).join('\n') + '\n';
    const signedHeadersList = headersList.map(h => h[0]).join(';');
    
    const canonicalRequest = [
        method,
        path,
        '',  // query string (empty for POST)
        canonicalHeaders,
        signedHeadersList,
        bodyHash
    ].join('\n');
    
    const credentialScope = `${date}/${region}/${service}/aws4_request`;
    const stringToSign = [
        'AWS4-HMAC-SHA256',
        datetime,
        credentialScope,
        sha256(canonicalRequest)
    ].join('\n');
    
    const signingKey = getSignatureKey(credentials.secretAccessKey, date, region, service);
    const signature = hmacHex(signingKey, stringToSign);
    
    const authorization = `AWS4-HMAC-SHA256 Credential=${credentials.accessKeyId}/${credentialScope}, SignedHeaders=${signedHeadersList}, Signature=${signature}`;
    
    return {
        'x-amz-date': datetime,
        'x-amz-content-sha256': bodyHash,
        'authorization': authorization
    };
}

function sha256(data) {
    return crypto.createHash('sha256').update(data || '', 'utf8').digest('hex');
}

function hmac(key, data) {
    return crypto.createHmac('sha256', key).update(data, 'utf8').digest();
}

function hmacHex(key, data) {
    return crypto.createHmac('sha256', key).update(data, 'utf8').digest('hex');
}

function getSignatureKey(secretKey, dateStamp, region, service) {
    const kDate = hmac('AWS4' + secretKey, dateStamp);
    const kRegion = hmac(kDate, region);
    const kService = hmac(kRegion, service);
    return hmac(kService, 'aws4_request');
}

server.listen(PORT, () => {
    console.log(`HealthImaging proxy listening on port ${PORT}`);
    console.log(`Region: ${REGION}`);
    console.log(`HealthImaging endpoint: ${HEALTHIMAGING_HOST}`);
});
