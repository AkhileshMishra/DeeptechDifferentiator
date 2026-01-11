/**
 * Lambda@Edge Origin Request Handler
 * Signs requests to AWS HealthImaging using SigV4
 * 
 * Converts GET requests with query params to POST requests with JSON body
 * for GetImageFrame API (required by HealthImaging API)
 */

const crypto = require('crypto');

const REGION = 'us-east-1';
const SERVICE = 'medical-imaging';

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    
    try {
        // Get AWS credentials from Lambda execution role
        const credentials = {
            accessKeyId: process.env.AWS_ACCESS_KEY_ID,
            secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
            sessionToken: process.env.AWS_SESSION_TOKEN
        };
        
        const host = `runtime-medical-imaging.${REGION}.amazonaws.com`;
        let method = request.method;
        let path = request.uri;
        let body = '';
        
        // Check if this is a getImageFrame request (needs GET→POST conversion)
        // CloudFront sends GET for caching, but HealthImaging API requires POST
        if (path.includes('/getImageFrame') && request.querystring) {
            const params = new URLSearchParams(request.querystring);
            const imageFrameId = params.get('imageFrameId');
            
            if (imageFrameId) {
                // Convert to POST with JSON body
                method = 'POST';
                body = JSON.stringify({ imageFrameId: imageFrameId });
                
                // Update request method
                request.method = 'POST';
                
                // Set body - must use base64 encoding for origin-request
                request.body = {
                    action: 'replace',
                    encoding: 'base64',
                    data: Buffer.from(body).toString('base64')
                };
                
                // Clear query string since we moved imageFrameId to body
                request.querystring = '';
                
                // Set required headers for POST with JSON body
                request.headers['content-type'] = [{ key: 'Content-Type', value: 'application/json' }];
                request.headers['content-length'] = [{ key: 'Content-Length', value: String(Buffer.byteLength(body)) }];
            }
        } else if (request.body && request.body.data) {
            // Handle existing POST requests
            body = request.body.encoding === 'base64' 
                ? Buffer.from(request.body.data, 'base64').toString('utf8')
                : request.body.data;
        }
        
        // Sign the request
        const signedHeaders = signRequest({
            method,
            host,
            path,
            querystring: request.querystring || '',
            body,
            credentials,
            region: REGION,
            service: SERVICE
        });
        
        // Update request headers with signed headers
        request.headers['host'] = [{ key: 'Host', value: host }];
        request.headers['x-amz-date'] = [{ key: 'X-Amz-Date', value: signedHeaders['x-amz-date'] }];
        request.headers['x-amz-content-sha256'] = [{ key: 'X-Amz-Content-Sha256', value: signedHeaders['x-amz-content-sha256'] }];
        request.headers['authorization'] = [{ key: 'Authorization', value: signedHeaders['authorization'] }];
        
        if (credentials.sessionToken) {
            request.headers['x-amz-security-token'] = [{ key: 'X-Amz-Security-Token', value: credentials.sessionToken }];
        }
        
        return request;
        
    } catch (error) {
        console.error('Error signing request:', error);
        return {
            status: '500',
            statusDescription: 'Internal Server Error',
            headers: {
                'content-type': [{ key: 'Content-Type', value: 'application/json' }]
            },
            body: JSON.stringify({ error: 'Failed to sign request: ' + error.message })
        };
    }
};

/**
 * Sign an AWS request using SigV4
 */
function signRequest({ method, host, path, querystring, body, credentials, region, service }) {
    const datetime = new Date().toISOString().replace(/[:-]|\.\d{3}/g, '');
    const date = datetime.substring(0, 8);
    
    // Hash the body
    const bodyHash = sha256(body);
    
    // Create canonical headers
    const headersList = [
        ['host', host],
        ['x-amz-content-sha256', bodyHash],
        ['x-amz-date', datetime]
    ];
    
    if (credentials.sessionToken) {
        headersList.push(['x-amz-security-token', credentials.sessionToken]);
    }
    
    // Sort headers
    headersList.sort((a, b) => a[0].localeCompare(b[0]));
    
    const canonicalHeaders = headersList.map(h => `${h[0]}:${h[1]}`).join('\n') + '\n';
    const signedHeadersList = headersList.map(h => h[0]).join(';');
    
    const canonicalRequest = [
        method,
        path,
        querystring,
        canonicalHeaders,
        signedHeadersList,
        bodyHash
    ].join('\n');
    
    // Create string to sign
    const credentialScope = `${date}/${region}/${service}/aws4_request`;
    const stringToSign = [
        'AWS4-HMAC-SHA256',
        datetime,
        credentialScope,
        sha256(canonicalRequest)
    ].join('\n');
    
    // Calculate signature
    const signingKey = getSignatureKey(credentials.secretAccessKey, date, region, service);
    const signature = hmacHex(signingKey, stringToSign);
    
    // Build authorization header
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
