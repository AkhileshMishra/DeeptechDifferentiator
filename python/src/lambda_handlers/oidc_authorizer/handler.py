"""
Healthcare Imaging MLOps Platform - OIDC Authorizer Lambda
Validates JWT tokens from Cognito for AWS HealthImaging DICOMweb API access.
Based on AWS HealthImaging samples reference implementation.
"""

import os
import json
import logging
import urllib.request
from jose import jwt, jwk
from jose.utils import base64url_decode

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger = logging.getLogger()
logger.setLevel(log_level)

# Environment variables
USER_POOL_ID = os.environ.get('USER_POOL_ID')
CLIENT_ID = os.environ.get('CLIENT_ID')
DICOMWEB_ROLE_ARN = os.environ.get('DICOMWEB_ROLE_ARN')
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')

# Cognito JWKS URL
JWKS_URL = f'https://cognito-idp.{AWS_REGION}.amazonaws.com/{USER_POOL_ID}/.well-known/jwks.json'

# Cache for JWKS keys
_jwks_cache = None


def get_jwks():
    """Fetch and cache JWKS from Cognito."""
    global _jwks_cache
    if _jwks_cache is None:
        logger.info(f"Fetching JWKS from {JWKS_URL}")
        with urllib.request.urlopen(JWKS_URL) as response:
            _jwks_cache = json.loads(response.read().decode('utf-8'))
    return _jwks_cache


def get_signing_key(token):
    """Get the signing key for the token from JWKS."""
    jwks = get_jwks()
    
    # Get the kid from the token header
    headers = jwt.get_unverified_headers(token)
    kid = headers.get('kid')
    
    if not kid:
        raise ValueError("Token does not have a 'kid' header")
    
    # Find the matching key
    for key in jwks.get('keys', []):
        if key.get('kid') == kid:
            return jwk.construct(key)
    
    raise ValueError(f"Unable to find matching key for kid: {kid}")


def validate_token(token):
    """
    Validate the JWT token from Cognito.
    
    Returns:
        dict: The decoded token claims if valid
        
    Raises:
        Exception: If token is invalid
    """
    try:
        # Get the signing key
        signing_key = get_signing_key(token)
        
        # Decode and validate the token
        claims = jwt.decode(
            token,
            signing_key,
            algorithms=['RS256'],
            audience=CLIENT_ID,
            issuer=f'https://cognito-idp.{AWS_REGION}.amazonaws.com/{USER_POOL_ID}'
        )
        
        # Verify token_use is 'access' or 'id'
        token_use = claims.get('token_use')
        if token_use not in ['access', 'id']:
            raise ValueError(f"Invalid token_use: {token_use}")
        
        logger.info(f"Token validated successfully for user: {claims.get('sub', 'unknown')}")
        return claims
        
    except jwt.ExpiredSignatureError:
        logger.warning("Token has expired")
        raise
    except jwt.JWTClaimsError as e:
        logger.warning(f"Token claims validation failed: {e}")
        raise
    except Exception as e:
        logger.error(f"Token validation failed: {e}")
        raise


def lambda_handler(event, context):
    """
    AWS HealthImaging Lambda Authorizer handler.
    
    This function is invoked by AWS HealthImaging for each DICOMweb API request.
    It validates the JWT token and returns an authorization response.
    
    Event structure from HealthImaging:
    {
        "accessToken": "Bearer <token>" or "<token>",
        "datastoreId": "...",
        "operation": "SearchDICOMStudies" | "GetDICOMInstance" | etc.
    }
    
    Response structure:
    {
        "isAuthorized": true/false,
        "iamRoleArn": "arn:aws:iam::...:role/..." (if authorized)
    }
    """
    logger.info(f"Authorizer invoked with event keys: {list(event.keys())}")
    
    try:
        # Extract the access token
        access_token = event.get('accessToken', '')
        
        # Remove 'Bearer ' prefix if present
        if access_token.startswith('Bearer '):
            access_token = access_token[7:]
        
        if not access_token:
            logger.warning("No access token provided")
            return {
                'isAuthorized': False
            }
        
        # Validate the token
        claims = validate_token(access_token)
        
        # Token is valid, return authorized response with IAM role
        logger.info(f"Authorization successful for operation: {event.get('operation', 'unknown')}")
        
        return {
            'isAuthorized': True,
            'iamRoleArn': DICOMWEB_ROLE_ARN
        }
        
    except Exception as e:
        logger.error(f"Authorization failed: {str(e)}")
        return {
            'isAuthorized': False
        }
