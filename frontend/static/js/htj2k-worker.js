/**
 * HTJ2K Decoder Web Worker
 * Uses OpenJPH (openjphjs) WASM for decoding AWS HealthImaging frames
 */

// Load the OpenJPH WASM module
self.importScripts('./openjphjs.js');

let decoder = null;
let isReady = false;

// Initialize decoder when WASM is ready
Module.onRuntimeInitialized = () => {
    decoder = new Module.HTJ2KDecoder();
    isReady = true;
    postMessage({ type: 'ready' });
};

/**
 * Decode HTJ2K encoded image frame
 */
function decodeFrame(encodedData) {
    const encodedBitStream = new Uint8Array(encodedData);
    const encodedBuffer = decoder.getEncodedBuffer(encodedBitStream.length);
    encodedBuffer.set(encodedBitStream);

    decoder.readHeader();
    const decodeStart = performance.now();
    decoder.decode();
    const decodeTime = performance.now() - decodeStart;

    const frameInfo = decoder.getFrameInfo();
    const decodedBuffer = decoder.getDecodedBuffer();
    const pixelData = new Uint8Array(decodedBuffer.length);
    pixelData.set(decodedBuffer);

    return {
        frameInfo: {
            width: frameInfo.width,
            height: frameInfo.height,
            bitsPerSample: frameInfo.bitsPerSample,
            componentCount: frameInfo.componentCount,
            isSigned: frameInfo.isSigned
        },
        pixelData: pixelData.buffer,
        decodeTime: decodeTime,
        encodedSize: encodedBitStream.length
    };
}

/**
 * Fetch and decode image frame from HealthImaging
 */
async function fetchAndDecode(request) {
    const { url, headers, imageFrameId } = request;
    
    try {
        const fetchStart = performance.now();
        
        const response = await fetch(url, {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({ imageFrameId: imageFrameId })
        });

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const arrayBuffer = await response.arrayBuffer();
        const fetchTime = performance.now() - fetchStart;

        const decoded = decodeFrame(arrayBuffer);
        
        return {
            success: true,
            imageFrameId: imageFrameId,
            frameInfo: decoded.frameInfo,
            pixelData: decoded.pixelData,
            metrics: {
                fetchTime: fetchTime,
                decodeTime: decoded.decodeTime,
                encodedSize: decoded.encodedSize,
                decodedSize: decoded.pixelData.byteLength
            }
        };
    } catch (error) {
        return {
            success: false,
            imageFrameId: imageFrameId,
            error: error.message
        };
    }
}

/**
 * Progressive loading - decode chunks as they arrive
 */
async function fetchProgressive(request) {
    const { url, headers, imageFrameId } = request;
    
    try {
        const response = await fetch(url, {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({ imageFrameId: imageFrameId })
        });

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const reader = response.body.getReader();
        let result = new Uint8Array([]);
        let chunkCount = 0;

        while (true) {
            const { done, value } = await reader.read();
            
            if (done) break;

            // Append chunk
            const newResult = new Uint8Array(result.length + value.length);
            newResult.set(result);
            newResult.set(value, result.length);
            result = newResult;
            chunkCount++;

            // Try to decode current data
            try {
                const decoded = decodeFrame(result.buffer);
                
                postMessage({
                    type: 'progressive',
                    imageFrameId: imageFrameId,
                    chunkCount: chunkCount,
                    frameInfo: decoded.frameInfo,
                    pixelData: decoded.pixelData,
                    isComplete: false
                }, [decoded.pixelData]);
            } catch (e) {
                // Not enough data yet, continue
            }
        }

        // Final decode
        const decoded = decodeFrame(result.buffer);
        postMessage({
            type: 'progressive',
            imageFrameId: imageFrameId,
            chunkCount: chunkCount,
            frameInfo: decoded.frameInfo,
            pixelData: decoded.pixelData,
            isComplete: true
        }, [decoded.pixelData]);

    } catch (error) {
        postMessage({
            type: 'error',
            imageFrameId: imageFrameId,
            error: error.message
        });
    }
}

// Handle messages from main thread
onmessage = async function(e) {
    const { type, requestId, ...data } = e.data;

    if (!isReady && type !== 'ping') {
        postMessage({ type: 'error', requestId, error: 'Decoder not ready' });
        return;
    }

    switch (type) {
        case 'ping':
            postMessage({ type: 'pong', ready: isReady });
            break;

        case 'decode':
            const result = await fetchAndDecode(data);
            postMessage({ 
                type: 'decoded', 
                requestId,
                ...result 
            }, result.success ? [result.pixelData] : []);
            break;

        case 'decodeProgressive':
            await fetchProgressive(data);
            break;

        case 'decodeBuffer':
            // Decode raw buffer (already fetched)
            try {
                const decoded = decodeFrame(data.buffer);
                postMessage({
                    type: 'decoded',
                    requestId,
                    success: true,
                    frameInfo: decoded.frameInfo,
                    pixelData: decoded.pixelData
                }, [decoded.pixelData]);
            } catch (error) {
                postMessage({
                    type: 'decoded',
                    requestId,
                    success: false,
                    error: error.message
                });
            }
            break;

        default:
            postMessage({ type: 'error', requestId, error: `Unknown message type: ${type}` });
    }
};
