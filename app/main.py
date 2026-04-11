"""
Genesis Events API - A minimal FastAPI application for DevSecOps assessment.

This API provides three endpoints:
- GET /health: Health check with version and environment info
- POST /events: Create a new event
- GET /events/{id}: Retrieve an event by ID
"""

import os
import uuid
from datetime import datetime, timezone
from typing import Dict, Optional
import logging

from fastapi import FastAPI, HTTPException, status, Request
from pydantic import BaseModel, Field
import boto3
from botocore.exceptions import ClientError

# Initialize logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# SECURITY FLAW 1: Hardcoded credential (should be caught by Gitleaks)
# This should be fetched from AWS Secrets Manager, not hardcoded
DB_PASSWORD = 'genesis-db-p4ss'  # TODO: Remove hardcoded password

# Initialize FastAPI app
app = FastAPI(
    title="Genesis Events API",
    description="Simple event management API for DevSecOps assessment",
    version="1.0.0"
)

# In-memory event storage (stateless for DR simplicity)
events_store: Dict[str, dict] = {}

# AWS clients (initialized lazily)
_secrets_client = None
_cloudwatch_client = None


def get_secrets_manager_client():
    """Get or create AWS Secrets Manager client."""
    global _secrets_client
    if _secrets_client is None:
        _secrets_client = boto3.client('secretsmanager')
    return _secrets_client


def get_cloudwatch_client():
    """Get or create AWS CloudWatch client."""
    global _cloudwatch_client
    if _cloudwatch_client is None:
        _cloudwatch_client = boto3.client('cloudwatch')
    return _cloudwatch_client


def get_secret(secret_name: str) -> str:
    """
    Retrieve secret from AWS Secrets Manager.
    
    Args:
        secret_name: Name of the secret to retrieve
        
    Returns:
        Secret value as string
        
    Raises:
        Exception: If secret cannot be retrieved
    """
    try:
        client = get_secrets_manager_client()
        response = client.get_secret_value(SecretId=secret_name)
        return response['SecretString']
    except ClientError as e:
        logger.error(f"Failed to retrieve secret {secret_name}: {e}")
        # For local development, return a dummy value
        if os.getenv('ENVIRONMENT') == 'local':
            logger.warning(f"Using dummy secret for local development")
            return "local-dummy-secret"
        raise


def emit_custom_metric(metric_name: str, value: float, dimensions: Optional[Dict[str, str]] = None):
    """
    Emit custom metric to CloudWatch.
    
    Args:
        metric_name: Name of the metric
        value: Metric value
        dimensions: Optional dimensions for the metric
    """
    try:
        client = get_cloudwatch_client()
        metric_data = {
            'MetricName': metric_name,
            'Value': value,
            'Unit': 'Count',
            'Timestamp': datetime.now(timezone.utc)
        }
        
        if dimensions:
            metric_data['Dimensions'] = [
                {'Name': k, 'Value': v} for k, v in dimensions.items()
            ]
        
        client.put_metric_data(
            Namespace='GenesisAPI',
            MetricData=[metric_data]
        )
        logger.info(f"Emitted metric: {metric_name}={value}")
    except Exception as e:
        # Don't fail the request if metrics fail
        logger.error(f"Failed to emit metric {metric_name}: {e}")


# Pydantic models for request/response validation
class EventCreate(BaseModel):
    """Model for creating a new event."""
    event_type: str = Field(..., min_length=1, max_length=50, description="Type of event")
    description: str = Field(..., min_length=1, max_length=500, description="Event description")
    metadata: Optional[Dict[str, str]] = Field(default=None, description="Optional metadata")


class EventResponse(BaseModel):
    """Model for event response."""
    id: str = Field(..., description="Event ID")
    event_type: str
    description: str
    metadata: Optional[Dict[str, str]] = None
    created_at: str


class HealthResponse(BaseModel):
    """Model for health check response."""
    status: str
    version: str
    env: str


@app.get("/health", response_model=HealthResponse, tags=["health"])
async def health_check():
    """
    Health check endpoint.
    
    Returns service status, version, and environment information.
    """
    environment = os.getenv("ENVIRONMENT", "dev")
    return HealthResponse(
        status="ok",
        version="1.0.0",
        env=environment
    )


@app.post("/events", response_model=EventResponse, status_code=status.HTTP_201_CREATED, tags=["events"])
async def create_event(event: EventCreate, request: Request):
    """
    Create a new event.
    
    Args:
        event: Event data from request body
        request: FastAPI request object
        
    Returns:
        Created event with generated ID
    """
    # SECURITY FLAW 2: Logging unsanitized request body (should be caught by Semgrep)
    # This could leak PII/sensitive data in production logs
    request_body = await request.body()
    logger.info(f"Raw request body: {request_body.decode('utf-8')}")  # TODO: Sanitize logging
    
    # Generate unique event ID
    event_id = str(uuid.uuid4())
    
    # Create event record
    event_data = {
        "id": event_id,
        "event_type": event.event_type,
        "description": event.description,
        "metadata": event.metadata,
        "created_at": datetime.now(timezone.utc).isoformat()
    }
    
    # Store event
    events_store[event_id] = event_data
    
    # Log event creation (sanitized - only log event type and ID, not full data)
    logger.info(f"Event created: type={event.event_type}, id={event_id}")
    
    # Emit custom CloudWatch metric for event type
    emit_custom_metric(
        metric_name='EventsCreated',
        value=1.0,
        dimensions={'EventType': event.event_type}
    )
    
    return EventResponse(**event_data)


@app.get("/events/{event_id}", response_model=EventResponse, tags=["events"])
async def get_event(event_id: str):
    """
    Retrieve an event by ID.
    
    Args:
        event_id: UUID of the event to retrieve
        
    Returns:
        Event data if found
        
    Raises:
        HTTPException: 404 if event not found
    """
    event = events_store.get(event_id)
    
    if not event:
        logger.warning(f"Event not found: {event_id}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": "Event not found",
                "event_id": event_id,
                "message": f"No event exists with ID: {event_id}"
            }
        )
    
    logger.info(f"Event retrieved: {event_id}")
    return EventResponse(**event)


@app.get("/", tags=["root"])
async def root():
    """Root endpoint with API information."""
    return {
        "name": "Genesis Events API",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health"
    }


# Application startup event (using lifespan for FastAPI 0.109+)
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    environment = os.getenv("ENVIRONMENT", "dev")
    logger.info(f"Starting Genesis Events API v1.0.0 in {environment} environment")
    yield
    logger.info("Shutting down Genesis Events API")

# Update app with lifespan
app.router.lifespan_context = lifespan


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
